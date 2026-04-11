import 'dart:async';
import '../models/detection_result.dart';

class MockService {
  static const List<DetectionResult> mockData = [
    DetectionResult(label: '사람', distance: 4.5),
    DetectionResult(label: '자전거', distance: 2.3),
    DetectionResult(label: '자동차', distance: 1.2),
    DetectionResult(label: '볼라드', distance: 0.8),
    DetectionResult(label: '계단', distance: 3.1),
  ];

  int _index = 0;
  Timer? _timer;

  // 상태가 바뀔 때마다 호출되는 콜백
  final void Function(DetectionState state, DetectionResult? result) onUpdate;

  MockService({required this.onUpdate});

  void start() => _next();

  void stop() {
    _timer?.cancel();
    onUpdate(DetectionState.scanning, null);
  }

  void dispose() => _timer?.cancel();

  void _next() {
    // 1. 먼저 "탐지 중" 상태
    onUpdate(DetectionState.scanning, null);

    // 2. 1.2초 후 탐지 결과 표시
    _timer = Timer(const Duration(milliseconds: 1200), () {
      final result = mockData[_index % mockData.length];
      onUpdate(result.state, result);
      _index++;

      // 3. 2.5초 후 다음 순환
      _timer = Timer(const Duration(milliseconds: 2500), _next);
    });
  }
}
