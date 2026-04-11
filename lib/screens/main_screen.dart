import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../models/detection_result.dart';
import '../services/mock_service.dart';
import '../services/camera_service.dart';
import '../widgets/status_badge.dart';
import '../widgets/scanning_view.dart';
import '../widgets/detection_view.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  DetectionState _state = DetectionState.scanning;
  DetectionResult? _result;
  bool _isRunning = false;

  late AnimationController _animController;
  late Animation<double> _overlayAnim;
  late Animation<double> _textFadeAnim;

  late MockService _mockService;
  final CameraService _cameraService = CameraService();

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _overlayAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _textFadeAnim = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0, 0.3)),
    );

    _mockService = MockService(onUpdate: _onDetectionUpdate);

    // 카메라 초기화
    _initCamera();
  }

  Future<void> _initCamera() async {
    await _cameraService.initialize();
    if (mounted) setState(() {}); // 카메라 준비되면 화면 갱신
  }

  @override
  void dispose() {
    _animController.dispose();
    _mockService.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  Future<void> _onDetectionUpdate(
    DetectionState state,
    DetectionResult? result,
  ) async {
    await _animController.forward();
    if (!mounted) return;
    setState(() {
      _state = state;
      _result = result;
    });
    await _animController.reverse();
  }

  void _onTap() {
    setState(() => _isRunning = !_isRunning);
    _isRunning ? _mockService.start() : _mockService.stop();
  }

  Color get _overlayColor {
    if (_state != DetectionState.danger || _result == null) {
      return Colors.transparent;
    }
    return _result!.distance <= 1.0
        ? const Color(0xFFCC4400).withOpacity(0.55)
        : const Color(0xFFB05A00).withOpacity(0.45);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. 카메라 배경 ──────────────────────────────
            _buildCameraBackground(),

            // ── 2. 위험 오버레이 ───────────────────────────
            AnimatedBuilder(
              animation: _overlayAnim,
              builder: (_, __) => Container(
                color: _overlayColor.withOpacity(
                  _overlayColor.opacity * _overlayAnim.value,
                ),
              ),
            ),

            // ── 3. SYSTEM ACTIVE ───────────────────────────
            Positioned(top: topPad + 16, left: 20, child: const StatusBadge()),

            // ── 4. 중앙 콘텐츠 ─────────────────────────────
            Center(
              child: FadeTransition(
                opacity: _textFadeAnim,
                child: _state == DetectionState.scanning || _result == null
                    ? const ScanningView()
                    : DetectionView(result: _result!),
              ),
            ),

            // ── 5. 하단 힌트 ───────────────────────────────
            Positioned(
              bottom: bottomPad + 20,
              left: 0,
              right: 0,
              child: Text(
                '어디든 화면을 터치하세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 카메라 준비되면 프리뷰, 아직이면 검정 배경
  Widget _buildCameraBackground() {
    if (_cameraService.isInitialized && _cameraService.controller != null) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraService.controller!.value.previewSize!.height,
            height: _cameraService.controller!.value.previewSize!.width,
            child: CameraPreview(_cameraService.controller!),
          ),
        ),
      );
    }

    // 카메라 로딩 중 → 검정 배경
    return Container(color: Colors.black);
  }
}
