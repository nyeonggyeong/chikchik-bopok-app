enum DetectionState { scanning, safe, danger }

class BBox {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const BBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  factory BBox.fromJson(Map<String, dynamic> json) {
    return BBox(
      x1: (json['x1'] as num?)?.toDouble() ?? 0,
      y1: (json['y1'] as num?)?.toDouble() ?? 0,
      x2: (json['x2'] as num?)?.toDouble() ?? 0,
      y2: (json['y2'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x1': x1,
      'y1': y1,
      'x2': x2,
      'y2': y2,
    };
  }
}

class DetectionResult {
  final String objectClass;
  final double distanceM;
  final BBox bbox;
  final double? confidence;

  const DetectionResult({
    required this.objectClass,
    required this.distanceM,
    required this.bbox,
    this.confidence,
  });

  // 기존 코드 호환용 alias
  String get label => objectClass;
  double get distance => distanceM;

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      objectClass: (json['class'] as String?) ?? 'unknown',
      distanceM: (json['distance_m'] as num?)?.toDouble() ?? 0,
      bbox: BBox.fromJson((json['bbox'] as Map?)?.cast<String, dynamic>() ?? {}),
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'class': objectClass,
      'distance_m': distanceM,
      'bbox': bbox.toJson(),
      if (confidence != null) 'confidence': confidence,
    };
  }

  // 거리에 따라 자동으로 상태 반환
  DetectionState get state {
    if (distanceM <= 2.0) return DetectionState.danger;
    return DetectionState.safe;
  }
}
