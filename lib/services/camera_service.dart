import 'package:camera/camera.dart';

class CameraService {
  CameraController? controller;
  bool isInitialized = false;

  // 후면 카메라 초기화
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    // 후면 카메라 선택
    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    controller = CameraController(
      backCamera,
      ResolutionPreset.medium, // 성능 위해 medium 사용
      enableAudio: false,
    );

    await controller!.initialize();
    isInitialized = true;
  }

  void dispose() {
    controller?.dispose();
    isInitialized = false;
  }
}
