import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

class CalibrationScreen extends StatefulWidget {
  final CameraController cameraController;
  
  const CalibrationScreen({super.key, required this.cameraController});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  final ApiService _apiService = ApiService();
  bool _isCameraReady = false;
  bool _isCalibrating = false;
  String _statusMessage = '1m 앞의 장애물을 중앙에 두고 아래 버튼을 누르세요.';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _calibrate() async {
    final controller = widget.cameraController;
    if (controller.value.isTakingPicture) return;

    setState(() {
      _isCalibrating = true;
      _statusMessage = '거리를 측정 중입니다...';
    });

    try {
      final frame = await controller.takePicture();
      final response = await _apiService.predictFromXFilePath(frame.path, dangerThreshold: 100.0);

      if (!mounted) return;

      if (response == null || response.objects.isEmpty) {
        setState(() {
          _statusMessage = '인식된 물체가 없습니다. 다시 시도해 주세요.';
        });
        return;
      }

      // 가장 가까운 물체의 distanceM(상대 깊이 스코어)를 추출
      final nearest = response.objects.reduce((a, b) => a.distanceM <= b.distanceM ? a : b);
      
      final newThreshold = nearest.distanceM;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('dangerThreshold', newThreshold);

      setState(() {
        _statusMessage = '보정 완료! 위험 기준값: ${newThreshold.toStringAsFixed(2)}\n이제 이전 화면으로 돌아가세요.';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '오류 발생: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCalibrating = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('거리 보정 (캘리브레이션)'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black,
            child: Center(
              child: Builder(
                builder: (context) {
                  var cameraRatio = widget.cameraController.value.aspectRatio;
                  if (cameraRatio > 1) {
                    cameraRatio = 1 / cameraRatio;
                  }
                  return AspectRatio(
                    aspectRatio: cameraRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(widget.cameraController),
                        // 중앙 가이드선
                        Center(
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.greenAccent, width: 2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: _isCalibrating ? null : _calibrate,
                      child: Text(
                        _isCalibrating ? '측정 중...' : '1m 위험 거리로 설정',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
