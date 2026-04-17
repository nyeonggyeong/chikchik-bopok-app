import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

import '../models/detection_result.dart';
import '../services/api_service.dart';
import 'calibration_screen.dart';
import '../widgets/painters/detection_overlay_painter.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;
  final ApiService _apiService = ApiService();
  final FlutterTts _flutterTts = FlutterTts();
  Timer? _captureTimer;
  Timer? _reconnectTimer;

  bool _isCameraReady = false;
  bool _isGuidanceRunning = false;
  bool _isReconnecting = false;
  bool _hasAnnouncedReconnect = false;
  bool _isSendingFrame = false;
  bool _isDisposed = false;

  List<DetectionResult> _detections = const [];

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _initializeCamera();
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage('ko-KR');
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty || !mounted) return;

    final backCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _cameraController = controller;
      _isCameraReady = true;
    });
  }

  Future<void> _toggleGuidance() async {
    if (!_isCameraReady || _cameraController == null) return;

    // 💡 핵심: 복구 중(_isReconnecting)이거나 안내 중일 때 더블 탭하면 무조건 종료!
    if (_isGuidanceRunning || _isReconnecting) {
      _captureTimer?.cancel();
      _reconnectTimer?.cancel(); // 복구 타이머도 확실히 꺼줌
      await _stopCurrentSpeech();
      
      if (!mounted) return;
      setState(() {
        _isGuidanceRunning = false;
        _isReconnecting = false; // 복구 상태 해제
        _hasAnnouncedReconnect = false; // 음성 플래그 초기화
        _detections = const [];
      });
      
      await _speak('안내를 중지합니다.'); // 종료 피드백 추가
      return;
    }

    // 켜기 로직
    setState(() {
      _isGuidanceRunning = true;
    });
    await _speak('안내를 시작합니다.'); // 시작 피드백 추가
    _startPeriodicCapture();
  }

  void _startPeriodicCapture() {
    _captureTimer?.cancel();
    _captureAndPredict();
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _captureAndPredict(),
    );
  }

  Future<void> _captureAndPredict() async {
    if (!_isGuidanceRunning || _isReconnecting || _isSendingFrame || _cameraController == null) {
      return;
    }

    final controller = _cameraController!;
    if (!controller.value.isInitialized || controller.value.isTakingPicture) return;

    _isSendingFrame = true;
    try {
      final XFile frame = await controller.takePicture();
      final detectionsOrNull = await _apiService.predictFromXFilePath(frame.path);
      if (detectionsOrNull == null) {
        await _pauseGuidanceDueToNetworkError();
        return;
      }
      final detections = detectionsOrNull;
      if (!_isDisposed && mounted) {
        setState(() {
          _detections = detections;
        });
      }
      await _handleVoiceGuidance(detections);
    } catch (_) {
      await _pauseGuidanceDueToNetworkError();
    } finally {
      _isSendingFrame = false;
    }
  }

  Future<void> _handleVoiceGuidance(List<DetectionResult> detections) async {
    if (detections.isEmpty) {
      // 안전 구간은 무음 유지
      return;
    }

    final nearest = detections.reduce(
      (a, b) => a.distanceM <= b.distanceM ? a : b,
    );

    final message =
        '전방 ${nearest.distanceM.toStringAsFixed(1)}미터에 ${nearest.objectClass} 주의';
    await _speak(message);
    await _triggerDynamicHaptic(nearest.distanceM);
  }

  Future<void> _pauseGuidanceDueToNetworkError() async {
    _captureTimer?.cancel();
    if (_isReconnecting) return;

    if (!_isDisposed && mounted) {
      setState(() {
        _isReconnecting = true;
        _detections = const [];
      });
    }

    if (!_hasAnnouncedReconnect) {
      _hasAnnouncedReconnect = true;
      await _speak('네트워크가 불안정하여 3초 후 연결을 재시도합니다.');
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _retryConnection();
    });
  }

  Future<void> _retryConnection() async {
    if (_isDisposed || !_isReconnecting || _cameraController == null) return;
    final controller = _cameraController!;
    if (!controller.value.isInitialized || controller.value.isTakingPicture) {
      _scheduleReconnect();
      return;
    }

    try {
      final probeFrame = await controller.takePicture();
      final reconnectResult = await _apiService.predictFromXFilePath(probeFrame.path);

      if (reconnectResult == null) {
        _scheduleReconnect();
        return;
      }

      if (!_isDisposed && mounted) {
        setState(() {
          _isReconnecting = false;
          _isGuidanceRunning = true;
          _detections = reconnectResult;
        });
      } else {
        _isReconnecting = false;
        _isGuidanceRunning = true;
      }

      _hasAnnouncedReconnect = false;
      await _speak('네트워크가 복구되어 안내를 재개합니다.');
      await _handleVoiceGuidance(reconnectResult);
      _startPeriodicCapture();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _triggerDynamicHaptic(double distanceM) async {
    final hasVibrator = await Vibration.hasVibrator() ?? false;
    if (!hasVibrator) return;

    if (distanceM <= 1.0) {
      await Vibration.vibrate(pattern: [0, 250, 120, 250], intensities: [0, 255, 0, 255]);
      return;
    }
    if (distanceM <= 2.0) {
      await Vibration.vibrate(pattern: [0, 160, 100, 160], intensities: [0, 180, 0, 180]);
      return;
    }
    await Vibration.vibrate(duration: 100, amplitude: 100);
  }

  Future<void> _stopCurrentSpeech() async {
    await _flutterTts.stop();
  }

  Future<void> _speak(String message) async {
    await _stopCurrentSpeech();
    await _flutterTts.speak(message);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _captureTimer?.cancel();
    _reconnectTimer?.cancel();
    _flutterTts.stop();
    _apiService.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _toggleGuidance,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCameraPreview(),
            IgnorePointer(
              child: CustomPaint(
                painter: DetectionOverlayPainter(
                  detections: _detections,
                  strokeColor: const Color(0xFF00E5FF),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: AnimatedOpacity(
                    opacity: _isCameraReady ? 0.8 : 1,
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      _isCameraReady
                          ? (_isReconnecting
                                ? '네트워크 복구 중 · 자동으로 재시도합니다'
                                : (_isGuidanceRunning
                                      ? '안내 실행 중 · 화면 아무 곳이나 더블 탭하면 중지'
                                      : '화면 아무 곳이나 더블 탭하여 안내 시작'))
                          : '카메라를 준비하고 있습니다...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 12,
              child: SafeArea(
                child: IconButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CalibrationScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune, color: Colors.white),
                  tooltip: '거리 보정 설정',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isCameraReady || _cameraController == null) {
      return const ColoredBox(color: Colors.black);
    }

    final controller = _cameraController!;
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const ColoredBox(color: Colors.black);
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
