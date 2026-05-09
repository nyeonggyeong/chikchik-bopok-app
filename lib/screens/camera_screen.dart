import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  double _dangerThreshold = 1.5;

  // 피드백 쿨다운용 상태 변수
  DateTime? _lastSpokenTime;
  String? _lastSpokenClass;
  DateTime? _lastHapticTime;
  DateTime? _lastDelayWarningTime;

  List<DetectionResult> _detections = const [];

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _initializeCamera();
    _loadDangerThreshold();
  }

  Future<void> _loadDangerThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _dangerThreshold = prefs.getDouble('dangerThreshold') ?? 1.5;
      });
    }
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
        _lastSpokenTime = null; // 쿨다운 초기화
        _lastSpokenClass = null;
        _lastHapticTime = null;
        _lastDelayWarningTime = null;
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
    _startContinuousCapture();
  }

  void _startContinuousCapture() {
    if (_isGuidanceRunning && !_isReconnecting) {
      _continuousCaptureLoop();
    }
  }

  Future<void> _continuousCaptureLoop() async {
    // 종료되었거나 통신 복구 중이면 루프 중단 (과부하 방지)
    if (!_isGuidanceRunning || _isReconnecting || _isSendingFrame || _cameraController == null) {
      return;
    }

    final controller = _cameraController!;
    if (!controller.value.isInitialized || controller.value.isTakingPicture) {
      // 카메라가 바쁘면 아주 잠깐 대기 후 다시 시도
      await Future.delayed(const Duration(milliseconds: 100));
      _startContinuousCapture();
      return;
    }

    _isSendingFrame = true;
    try {
      final XFile frame = await controller.takePicture();
      final requestStart = DateTime.now();
      
      // Isolate 연산 + 네트워크 통신 (UI 멈춤 없음)
      final detectionsOrNull = await _apiService.predictFromXFilePath(
        frame.path,
        dangerThreshold: _dangerThreshold,
      );
      
      if (detectionsOrNull == null) {
        await _pauseGuidanceDueToNetworkError(ApiErrorType.unknown);
        return; // 에러 시 루프 잠시 중단
      }
      
      final elapsed = DateTime.now().difference(requestStart);
      if (elapsed.inSeconds >= 2) {
        if (_lastDelayWarningTime == null || DateTime.now().difference(_lastDelayWarningTime!).inSeconds >= 10) {
          _lastDelayWarningTime = DateTime.now();
          _speak('분석이 지연되고 있습니다. 잠시 멈춰주세요.');
        }
      }
      
      if (!_isDisposed && mounted) {
        setState(() {
          _detections = detectionsOrNull;
        });
      }
      await _handleVoiceGuidance(detectionsOrNull);

    } on ApiException catch (e) {
      await _pauseGuidanceDueToNetworkError(e.type);
    } catch (_) {
      await _pauseGuidanceDueToNetworkError(ApiErrorType.unknown);
    } finally {
      _isSendingFrame = false;
      // 작업이 완전히 끝나면 곧바로 다음 사진 촬영 (자연스러운 스로틀링으로 기기 과부하 방지)
      if (mounted && _isGuidanceRunning && !_isReconnecting) {
        // 백엔드 여유를 위해 100ms 정도만 쉬고 바로 다음 프레임 요청 (1초에 약 3~5장 달성)
        Future.delayed(const Duration(milliseconds: 100), _startContinuousCapture);
      }
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

    final now = DateTime.now();

    // --- 1. 음성 안내(TTS) 쿨다운 (3초) ---
    bool shouldSpeak = false;
    // 물체가 바뀌었거나, 3초가 지났다면 다시 말해줌
    if (_lastSpokenClass != nearest.objectClass) {
      shouldSpeak = true;
    } else if (_lastSpokenTime == null || now.difference(_lastSpokenTime!).inSeconds >= 3) {
      shouldSpeak = true;
    }

    if (shouldSpeak) {
      _lastSpokenClass = nearest.objectClass;
      _lastSpokenTime = now;
      // 한국어 이름(koreanName) 사용
      final message = '전방 ${nearest.distanceM.toStringAsFixed(1)}미터에 ${nearest.koreanName} 주의';
      // _speak 내부에서 await 하지만, 프레임 루프를 완전히 멈추지 않게 쿨다운 로직이 보호해줌
      _speak(message); 
    }

    // --- 2. 진동(Haptic) 쿨다운 (1.5초) ---
    // 진동 패턴이 길게 이어지므로 끊기지 않게 1.5초 쿨다운을 줌
    bool shouldVibrate = false;
    if (_lastHapticTime == null || now.difference(_lastHapticTime!).inMilliseconds >= 1500) {
      shouldVibrate = true;
    }

    if (shouldVibrate) {
      _lastHapticTime = now;
      _triggerDynamicHaptic(nearest.distanceM);
    }
  }

  Future<void> _pauseGuidanceDueToNetworkError(ApiErrorType errorType) async {
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
      String message;
      switch (errorType) {
        case ApiErrorType.noInternet:
          message = '인터넷 연결을 확인해 주세요. 재연결을 시도합니다.';
          break;
        case ApiErrorType.timeout:
          message = '서버 응답이 없습니다. 잠시 후 재시도합니다.';
          break;
        case ApiErrorType.serverError:
          message = '서버 오류가 발생했습니다. 탐지가 일시 중단됩니다.';
          break;
        default:
          message = '네트워크가 불안정하여 연결을 재시도합니다.';
      }
      await _speak(message);
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
      final reconnectResult = await _apiService.predictFromXFilePath(
        probeFrame.path,
        dangerThreshold: _dangerThreshold,
      );

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
      _startContinuousCapture();
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
                    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

                    // 안내가 실행 중이면 먼저 종료
                    if (_isGuidanceRunning || _isReconnecting) {
                      _captureTimer?.cancel();
                      _reconnectTimer?.cancel();
                      await _stopCurrentSpeech();
                      setState(() {
                        _isGuidanceRunning = false;
                        _isReconnecting = false;
                      });
                    }

                    if (!mounted) return;

                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CalibrationScreen(cameraController: _cameraController!),
                      ),
                    );
                    
                    // 돌아오면 설정값만 불러오기
                    if (mounted) {
                      await _loadDangerThreshold();
                    }
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
    var cameraRatio = controller.value.aspectRatio;
    if (cameraRatio > 1) {
      cameraRatio = 1 / cameraRatio; // 세로 모드 보정
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: cameraRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller),
              IgnorePointer(
                child: CustomPaint(
                  painter: DetectionOverlayPainter(
                    detections: _detections,
                    strokeColor: const Color(0xFF00E5FF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
