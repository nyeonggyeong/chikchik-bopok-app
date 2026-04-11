enum DetectionState { scanning, safe, danger }

class DetectionResult {
  final String label;
  final double distance;

  const DetectionResult({required this.label, required this.distance});

  // 거리에 따라 자동으로 상태 반환
  DetectionState get state {
    if (distance <= 2.0) return DetectionState.danger;
    return DetectionState.safe;
  }
}
