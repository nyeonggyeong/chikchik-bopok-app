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

class _CameraScreenState extends State<CameraScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
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
  double _referenceDepth = 1.0;

  // 피드백 쿨다운 및 상태 변수
  String _lastRiskLevel = 'safe';
  String _lastMainHazard = '';
  String _lastSpokenMessage = '';
  DateTime? _lastFeedbackTime;
  String _lastSafeDirection = 'forward';

  DateTime? _lastDelayWarningTime;

  String _mainHazard = '';
  String _riskLevel = 'safe';
  String _safeDirection = 'forward';

  final List<List<DetectionResult>> _history = [];
  final List<String> _directionHistory = [];
  List<DetectionResult> _detections = const [];
  PredictionResponse? _lastResponse; // UI 표시용 저장

  // 디버그 모드 및 애니메이션
  bool _debugMode = false;
  late AnimationController _pulseController;

  // TTS 큐 및 상태 관리
  bool _isSpeaking = false;
  final List<Map<String, dynamic>> _speechQueue = [];
  String? _currentSpeakingMessage;
  String? _lastSituationKey;
  DateTime? _queuedMessageTimestamp;

  // 안정화용 변수 (Motion Stability)
  String _candidateMainHazard = '';
  int _candidateHazardCount = 0;
  String _candidateSafeDirection = 'forward';
  int _candidateDirectionCount = 0;
  int _safeCounter = 0;
  int _hazardHoldCounter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('[Lifecycle] CameraScreen initState');
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _initializeTts();
    _initializeCamera();
    _loadCalibrationData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[Lifecycle] state changed to: $state');
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      debugPrint('[Lifecycle] App is backgrounded or detached. Stopping speech.');
      _stopCurrentSpeech();
    }
  }

  Future<void> _loadCalibrationData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _dangerThreshold = prefs.getDouble('dangerThreshold') ?? 1.5;
        _referenceDepth = prefs.getDouble('referenceDepth') ?? 1.0;
      });
    }
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage('ko-KR');
    await _flutterTts.setSpeechRate(0.5); // 약간 더 빠르게 조절
    await _flutterTts.setVolume(1.0);
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setStartHandler(() {
      if (mounted) setState(() => _isSpeaking = true);
      debugPrint('TTS started: $_currentSpeakingMessage');
    });

    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
      debugPrint('TTS completed');
      _processNextSpeech();
    });

    _flutterTts.setErrorHandler((msg) {
      if (mounted) setState(() => _isSpeaking = false);
      debugPrint('TTS error: $msg');
      _processNextSpeech();
    });
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
      debugPrint('[Action] Guidance stopping manually by user toggle');
      _captureTimer?.cancel();
      _reconnectTimer?.cancel(); 
      await _stopCurrentSpeech();
      
      if (!mounted || _isDisposed) return;
      setState(() {
        _isGuidanceRunning = false;
        _isReconnecting = false;
        // ... (기존 변수 초기화 로직 유지)
        _lastRiskLevel = 'safe';
        _lastMainHazard = '';
        _lastSpokenMessage = '';
        _lastFeedbackTime = null;
        _lastSafeDirection = 'forward';
        _mainHazard = '';
        _riskLevel = 'safe';
        _safeDirection = 'forward';
        _speechQueue.clear();
        _isSpeaking = false;
        _currentSpeakingMessage = null;
      });
      
      // 앱이 종료 중이 아닐 때만 음성 안내
      if (!_isDisposed) {
        await _speak('안내를 중지합니다.');
      }
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
    if (!_isGuidanceRunning || _isReconnecting || _isSendingFrame || _cameraController == null || _isDisposed) {
      return;
    }

    final controller = _cameraController!;
    if (!controller.value.isInitialized || controller.value.isTakingPicture || _isDisposed) {
      // 카메라가 바쁘거나 종료 중이면 아주 잠깐 대기 후 다시 시도
      await Future.delayed(const Duration(milliseconds: 100));
      _startContinuousCapture();
      return;
    }

    _isSendingFrame = true;
    try {
      if (_isDisposed) return;
      final XFile frame = await controller.takePicture();
      if (_isDisposed) return;
      
      final requestStart = DateTime.now();
      
      final responseOrNull = await _apiService.predictFromXFilePath(
        frame.path,
        dangerThreshold: _dangerThreshold,
        referenceDepth: _referenceDepth,
      );
      
      if (_isDisposed) return;
      
      if (responseOrNull == null) {
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
        final displayObjects = responseOrNull.displayObjects;
        final smoothedDetections = _smoothDetections(displayObjects);
        
        // 안전 방향 스무딩 (안정화)
        final rawSafeDir = responseOrNull.safeDirection;
        _directionHistory.add(rawSafeDir);
        if (_directionHistory.length > 3) _directionHistory.removeAt(0);
        
        String finalSafeDir = rawSafeDir;
        if (rawSafeDir != 'stop') {
          final counts = <String, int>{};
          for (var d in _directionHistory) {
            counts[d] = (counts[d] ?? 0) + 1;
          }
          final mostFrequent = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
          if (mostFrequent.value >= 2) {
            finalSafeDir = mostFrequent.key;
          } else {
            finalSafeDir = _safeDirection;
          }
        }

        setState(() {
          _mainHazard = responseOrNull.mainHazard;
          _riskLevel = responseOrNull.riskLevel;
          _safeDirection = finalSafeDir;
          _detections = smoothedDetections;
          _lastResponse = responseOrNull;
        });
        await _handleVoiceGuidance(smoothedDetections, responseOrNull);
      }

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

  List<DetectionResult> _smoothDetections(List<DetectionResult> currentDetections) {
    _history.add(currentDetections);
    if (_history.length > 3) _history.removeAt(0);

    List<DetectionResult> smoothed = [];
    for (var current in currentDetections) {
      double totalDist = 0;
      int count = 0;
      int maxRisk = current.riskLevel;

      for (var frame in _history) {
        for (var past in frame) {
          if (past.label == current.label) {
            totalDist += past.distanceM;
            count++;
            if (past.riskLevel > maxRisk) maxRisk = past.riskLevel;
            break;
          }
        }
      }

      // 프레임 플리커링 방지: 최소 2번 이상 등장했거나, 매우 위험(riskLevel == 2)하면 즉시 포함
      if (count >= 2 || current.riskLevel == 2) {
        final avgDist = count > 0 ? totalDist / count : current.distanceM;
        smoothed.add(DetectionResult(
          label: current.label,
          labelKo: current.labelKo,
          estimatedDistanceM: avgDist,
          bbox: current.bbox,
          confidence: current.confidence,
          distanceRaw: current.distanceRaw,
          distanceText: current.distanceText,
          position: current.position,
          positionKo: current.positionKo,
          description: current.description,
          isEmpty: current.isEmpty,
          riskLevel: maxRisk,
          motionState: current.motionState,
          rawDepthValue: current.rawDepthValue,
          referenceDepth: current.referenceDepth,
          distanceConfidence: current.distanceConfidence,
        ));
      }
    }
    return smoothed;
  }

  Future<void> _handleVoiceGuidance(List<DetectionResult> detections, PredictionResponse response) async {
    if (!_isGuidanceRunning || _isReconnecting) return;

    final riskyObjects = detections.where((d) => d.riskLevel > 0).toList();
    
    String currentRiskLevel = response.riskLevel;
    String currentMainHazard = response.mainHazard;
    String spokenSentence = '';

    if (riskyObjects.isNotEmpty) {
      _hazardHoldCounter = 0;
      _safeCounter = 0;
    } else {
      if (_hazardHoldCounter < 2 && _lastMainHazard.isNotEmpty) {
        _hazardHoldCounter++;
        currentMainHazard = _lastMainHazard;
      } else {
        currentRiskLevel = 'safe';
      }
    }

    // 상황 키 생성 (Phase 5.6: 상황 변화 감지용)
    final objectsKey = response.displayObjects.map((o) => '${o.labelKo}:${o.riskLevel}').join(',');
    final currentSituationKey = '${currentRiskLevel}_${response.safeDirection}_$objectsKey';

    bool isUrgent = currentRiskLevel == 'danger' || response.safeDirection == 'stop';

    if (response.guideMessage.isNotEmpty) {
      spokenSentence = response.guideMessage;
    }

    final now = DateTime.now();
    bool shouldProvideFeedback = false;

    // 3. 안내 트리거 조건 (Phase 5.6 개선)
    if (isUrgent && (_lastRiskLevel != 'danger' || _lastSafeDirection != 'stop')) {
      shouldProvideFeedback = true;
    } else if (spokenSentence.isNotEmpty && _lastSpokenMessage != spokenSentence) {
      // 메시지가 바뀌었을 때만 안내 (쿨다운 적용)
      int cooldown = (spokenSentence.contains('안전') || spokenSentence.contains('직진')) ? 8 : 3;
      if (now.difference(_lastFeedbackTime ?? DateTime(0)).inSeconds >= cooldown) {
        shouldProvideFeedback = true;
      }
    }

    if (shouldProvideFeedback && spokenSentence.isNotEmpty) {
      _enqueueSpeech(spokenSentence, currentSituationKey, urgent: isUrgent, interrupt: isUrgent);
      
      // 위험도에 따른 차별화된 햅틱 진동
      if (isUrgent || (currentRiskLevel == 'warning' && _lastRiskLevel != 'warning')) {
         _triggerDynamicHaptic(currentRiskLevel == 'danger' ? 3 : 1);
      }

      _lastRiskLevel = currentRiskLevel;
      _lastSafeDirection = response.safeDirection;
      _lastMainHazard = currentMainHazard;
      _lastSpokenMessage = spokenSentence;
      _lastFeedbackTime = now;
      _lastSituationKey = currentSituationKey;
      debugPrint('Guidance triggered: $spokenSentence');
    }
  }

  void _enqueueSpeech(String message, String situationKey, {bool urgent = false, bool interrupt = false}) {
    if (interrupt) {
      _flutterTts.stop();
      _speechQueue.clear();
      _isSpeaking = false;
    }

    // Phase 5.6: 큐에는 최신 메시지 1개만 유지 (동기화 지연 방지)
    if (_speechQueue.isNotEmpty && !urgent) {
      _speechQueue.clear();
    }

    _speechQueue.add({
      'message': message,
      'timestamp': DateTime.now(),
      'situationKey': situationKey,
      'urgent': urgent,
    });
    
    _queuedMessageTimestamp = DateTime.now();
    _processNextSpeech();
  }

  Future<void> _processNextSpeech() async {
    if (_isSpeaking || _speechQueue.isEmpty) return;

    _isSpeaking = true;
    final item = _speechQueue.removeAt(0);
    final String message = item['message'];
    final DateTime timestamp = item['timestamp'];
    final String msgSituationKey = item['situationKey'];
    final bool urgent = item['urgent'];

    final now = DateTime.now();
    
    // Phase 5.6: 오래된 메시지 폐기 로직
    bool isStale = now.difference(timestamp).inSeconds >= 2;
    bool isSituationChanged = _lastSituationKey != null && _lastSituationKey != msgSituationKey;

    if (!urgent && (isStale || isSituationChanged)) {
      debugPrint('🚫 [TTS Skip] Stale or Situation changed: $message');
      _isSpeaking = false;
      _processNextSpeech();
      return;
    }

    if (mounted) {
      setState(() {
        _currentSpeakingMessage = message;
      });
    }

    await _speakImmediately(message);

    if (mounted) {
      setState(() {
        _currentSpeakingMessage = null;
      });
    }
    
    _isSpeaking = false;
    _processNextSpeech();
  }

  Future<void> _speakImmediately(String message) async {
    // 기존 _speak와 유사하지만 awaitSpeakCompletion을 고려한 직접 호출
    await _flutterTts.speak(message);
  }

  String _getIga(String word) {
    if (word.isEmpty) return '가';
    final lastChar = word.codeUnitAt(word.length - 1);
    if (lastChar < 0xAC00 || lastChar > 0xD7A3) return '가';
    return (lastChar - 0xAC00) % 28 > 0 ? '이' : '가';
  }

  String _getDirectionAction(String direction) {
    switch (direction) {
      case 'left': return '왼쪽으로 이동하세요.';
      case 'right': return '오른쪽으로 이동하세요.';
      case 'stop': return '잠시 멈추세요.';
      case 'forward': return '천천히 직진하세요.';
      default: return '주의하며 이동하세요.';
    }
  }

  Future<void> _pauseGuidanceDueToNetworkError(ApiErrorType errorType) async {
    _captureTimer?.cancel();
    if (_isReconnecting) return;

    if (!_isDisposed && mounted) {
      setState(() {
        _isReconnecting = true;
        _detections = const [];
        _mainHazard = '';
        _riskLevel = 'safe';
        _speechQueue.clear();
        _isSpeaking = false;
        _currentSpeakingMessage = null;
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
      final XFile probeFrame = await controller.takePicture();
      final reconnectResult = await _apiService.predictFromXFilePath(
        probeFrame.path,
        dangerThreshold: _dangerThreshold,
        referenceDepth: _referenceDepth,
      );

      if (reconnectResult == null) {
        _scheduleReconnect();
        return;
      }

      if (!_isDisposed && mounted) {
        setState(() {
          _isReconnecting = false;
          _isGuidanceRunning = true;
          _detections = reconnectResult.displayObjects;
          _mainHazard = reconnectResult.mainHazard;
          _riskLevel = reconnectResult.riskLevel;
          _safeDirection = reconnectResult.safeDirection;
        });
      } else {
        _isReconnecting = false;
        _isGuidanceRunning = true;
      }

      _hasAnnouncedReconnect = false;
      await _speak('네트워크가 복구되어 안내를 재개합니다.');
      
      // 재연결 시에도 방향 스무딩 초기화
      _directionHistory.clear();
      _directionHistory.add(reconnectResult.safeDirection);

      await _handleVoiceGuidance(reconnectResult.displayObjects, reconnectResult);
      _startContinuousCapture();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _triggerDynamicHaptic(int riskLevel) async {
    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) return;

      if (riskLevel == 2) {
        // danger: 강한 진동 3연속
        await Vibration.vibrate(pattern: [0, 150, 50, 150, 50, 150], intensities: [0, 255, 0, 255, 0, 255]);
      } else if (riskLevel == 1) {
        // warning: 짧은 진동 1번
        await Vibration.vibrate(duration: 300, amplitude: 128);
      }
    } catch (e) {
      debugPrint('Haptic error: $e');
    }
  }

  Future<void> _stopCurrentSpeech() async {
    _speechQueue.clear();
    _isSpeaking = false;
    await _flutterTts.stop();
  }

  Future<void> _speak(String message, {bool urgent = false}) async {
    _enqueueSpeech(message, 'system', urgent: urgent, interrupt: urgent);
  }


  @override
  void dispose() {
    debugPrint('[Lifecycle] CameraScreen dispose started');
    _isDisposed = true;
    _isGuidanceRunning = false;
    _captureTimer?.cancel();
    _reconnectTimer?.cancel();
    
    // 종료 시에는 큐를 비우고 즉시 정지만 수행 (새로운 발화 방지)
    _speechQueue.clear();
    _flutterTts.stop();
    debugPrint('[Lifecycle] TTS stopped in dispose');
    
    _apiService.dispose();
    _cameraController?.dispose();
    debugPrint('[Lifecycle] Camera and Service disposed');
    
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
    debugPrint('[Lifecycle] CameraScreen dispose completed');
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
            // 0. 카메라 프리뷰 (배경)
            _buildCameraPreview(),
            
            // 1. 위험 상황 외곽 테두리 (Pulse)
            _buildEdgeAlertBorder(),

            // 2. 상단 상태 배지 및 설정 버튼
            _buildTopBar(),

            // 3. 중앙 대형 방향 안내
            _buildDirectionOverlay(),

            // 4. 하단 가이드 메시지 패널 및 조작 안내
            _buildBottomInfoArea(),

            // 5. 디버그 오버레이 (최상단)
            if (_debugMode) _buildDebugOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상태 배지 및 음성 아이콘
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusBadge(),
                const SizedBox(width: 12),
                _buildVoiceStatusIcon(),
              ],
            ),
            
            // 설정 버튼 (Long press로 디버그 모드 진입)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  if (_cameraController == null || !_cameraController!.value.isInitialized) return;
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
                  if (mounted) await _loadCalibrationData();
                },
                onLongPress: () {
                  setState(() => _debugMode = !_debugMode);
                  _speak(_debugMode ? '디버그 모드를 켭니다.' : '디버그 모드를 끕니다.');
                },
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _debugMode ? Icons.bug_report : Icons.tune,
                    color: _debugMode ? Colors.redAccent : Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color color;
    String label;
    IconData icon;

    if (_riskLevel == 'danger' || _safeDirection == 'stop') {
      color = Colors.red;
      label = '위험';
      icon = Icons.warning;
    } else if (_riskLevel == 'warning') {
      color = Colors.orange;
      label = '주의';
      icon = Icons.priority_high;
    } else {
      color = Colors.green;
      label = '안전';
      icon = Icons.check_circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildEdgeAlertBorder() {
    if (_riskLevel == 'safe' && _safeDirection != 'stop') return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final color = (_riskLevel == 'danger' || _safeDirection == 'stop') ? Colors.red : Colors.orange;
        return Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: color.withOpacity(0.3 + (_pulseController.value * 0.5)),
              width: 15.0 + (_pulseController.value * 10.0),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceStatusIcon() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _isGuidanceRunning ? Icons.volume_up : Icons.volume_off,
        color: _isGuidanceRunning ? Colors.white : Colors.redAccent,
        size: 24,
      ),
    );
  }

  Widget _buildBottomInfoArea() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 가이드 메시지 패널
            _buildGuideMessagePanel(),
            
            // 조작 안내 힌트 (메시지 아래에 작게 표시)
            Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '화면을 두 번 탭하면 음성 안내를 켜거나 끌 수 있습니다.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideMessagePanel() {
    if (!_isGuidanceRunning || _isReconnecting) return const SizedBox.shrink();
    
    final message = _lastResponse?.guideMessage ?? '';
    if (message.isEmpty) return const SizedBox.shrink();

    Color borderColor = Colors.transparent;
    if (_riskLevel == 'danger') borderColor = Colors.red;
    else if (_riskLevel == 'warning') borderColor = Colors.orange;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: 4),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  // _buildBottomControls 제거됨

  Widget _buildDebugOverlay() {
    final response = _lastResponse;
    return Positioned(
      left: 16,
      top: 150,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('[DEBUG INFO]', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white24),
              Text('Source: ${response?.guideSource ?? 'N/A'}', style: const TextStyle(color: Colors.yellow, fontSize: 14)),
              Text('Latency: ${response?.processTime ?? 'N/A'}', style: const TextStyle(color: Colors.white, fontSize: 14)),
              Text('Risk Raw: ${response?.riskLevel ?? 'safe'}', style: const TextStyle(color: Colors.white, fontSize: 14)),
              Text('Dir Raw: ${response?.safeDirection ?? 'forward'}', style: const TextStyle(color: Colors.white, fontSize: 14)),
              Text('Objects: ${_detections.length}', style: const TextStyle(color: Colors.white, fontSize: 14)),
              Text('Status: ${_isReconnecting ? "Reconnecting" : "Stable"}', style: const TextStyle(color: Colors.cyan, fontSize: 14)),
            ],
          ),
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
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirectionOverlay() {
    if (!_isGuidanceRunning || _isReconnecting) return const SizedBox.shrink();

    IconData icon;
    String text;
    Color color;

    switch (_safeDirection) {
      case 'left':
        icon = Icons.arrow_back;
        text = '왼쪽 이동';
        color = Colors.orange;
        break;
      case 'right':
        icon = Icons.arrow_forward;
        text = '오른쪽 이동';
        color = Colors.orange;
        break;
      case 'stop':
        icon = Icons.pan_tool;
        text = '정지';
        color = Colors.redAccent;
        break;
      case 'forward':
      default:
        icon = Icons.arrow_upward;
        text = '직진 가능';
        color = Colors.greenAccent;
        break;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 8),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.3), blurRadius: 20, spreadRadius: 5),
              ],
            ),
            child: Icon(icon, size: 140, color: color),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 42,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
