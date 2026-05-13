import 'dart:async';
import '../models/detection_result.dart';

class MockService {
  static const List<DetectionResult> mockData = [
    DetectionResult(
      label: 'person',
      labelKo: '사람',
      estimatedDistanceM: 4.5,
      bbox: BBox(x1: 30, y1: 60, x2: 180, y2: 360),
    ),
    DetectionResult(
      label: 'bicycle',
      labelKo: '자전거',
      estimatedDistanceM: 2.3,
      bbox: BBox(x1: 60, y1: 100, x2: 240, y2: 330),
    ),
    DetectionResult(
      label: 'car',
      labelKo: '자동차',
      estimatedDistanceM: 1.2,
      bbox: BBox(x1: 40, y1: 120, x2: 290, y2: 370),
      riskLevel: 2,
    ),
    DetectionResult(
      label: 'bollard',
      labelKo: '볼라드',
      estimatedDistanceM: 0.8,
      bbox: BBox(x1: 130, y1: 180, x2: 200, y2: 360),
      riskLevel: 2,
    ),
    DetectionResult(
      label: 'stairs',
      labelKo: '계단',
      estimatedDistanceM: 3.1,
      bbox: BBox(x1: 20, y1: 140, x2: 310, y2: 390),
    ),
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
