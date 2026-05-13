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
    double x1 =
        (json['x'] as num?)?.toDouble() ??
        (json['x1'] as num?)?.toDouble() ??
        0;
    double y1 =
        (json['y'] as num?)?.toDouble() ??
        (json['y1'] as num?)?.toDouble() ??
        0;
    double w = (json['w'] as num?)?.toDouble() ?? 0;
    double h = (json['h'] as num?)?.toDouble() ?? 0;

    double x2 = json.containsKey('x2')
        ? (json['x2'] as num).toDouble()
        : (x1 + w);
    double y2 = json.containsKey('y2')
        ? (json['y2'] as num).toDouble()
        : (y1 + h);

    return BBox(x1: x1, y1: y1, x2: x2, y2: y2);
  }

  /// `/predict/objects-distance` 응답 전체에서 박스 추출 (픽셀 xyxy 우선).
  factory BBox.fromPredictionEnvelope(Map<String, dynamic> json) {
    // 1. 변수 선언을 가장 먼저 합니다.
    final nested = json['bbox_xyxy_px'];
    final bbox = json['bbox'];

    // 2. [1순위] 루트에 있는 x1, y1, x2, y2 확인 (백엔드에서 보낸 비율 좌표)
    if (json['x1'] is num &&
        json['y1'] is num &&
        json['x2'] is num &&
        json['y2'] is num) {
      return BBox(
        x1: (json['x1'] as num).toDouble(),
        y1: (json['y1'] as num).toDouble(),
        x2: (json['x2'] as num).toDouble(),
        y2: (json['y2'] as num).toDouble(),
      );
    }

    // 3. [2순위] bbox 맵 확인 (비율 좌표 x, y, w, h)
    if (bbox is Map<String, dynamic>) {
      return BBox.fromJson(bbox);
    }

    // 4. [3순위] bbox_xyxy_px 확인 (픽셀 좌표)
    if (nested is Map) {
      return BBox.fromJson(nested.cast<String, dynamic>());
    }

    // 5. 아무것도 없다면 0으로 반환
    return const BBox(x1: 0, y1: 0, x2: 0, y2: 0);
  }

  Map<String, dynamic> toJson() {
    return {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2};
  }
}

class DetectionResult {
  final String label;
  final String labelKo;
  final BBox bbox;
  final double? confidence;
  final String distanceRaw;
  final String distanceText;
  final String position;
  final String positionKo;
  final String description;
  final bool? isEmpty;
  final int riskLevel;
  final String motionState;
  
  // Phase 5.6 추가 필드
  final double estimatedDistanceM;
  final double rawDepthValue;
  final double referenceDepth;
  final String distanceConfidence;

  const DetectionResult({
    required this.label,
    this.labelKo = '',
    required this.bbox,
    this.confidence,
    this.distanceRaw = '',
    this.distanceText = '',
    this.position = 'center',
    this.positionKo = '중앙',
    this.description = '',
    this.isEmpty,
    this.riskLevel = 0,
    this.motionState = 'stable',
    this.estimatedDistanceM = 0.0,
    this.rawDepthValue = 0.0,
    this.referenceDepth = 1.0,
    this.distanceConfidence = 'medium',
  });

  // 레거시 호환용 게터
  double get distanceM => estimatedDistanceM;
  double get distance => estimatedDistanceM;
  String get objectClass => label;
  bool? get seatIsEmpty => isEmpty;
  
  String get koreanName {
    if (labelKo.isNotEmpty) return labelKo;
    return label; // 기본 번역 로직은 생략 가능 (백엔드에서 labelKo를 주기 때문)
  }

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      label: json['label'] ?? 'unknown',
      labelKo: json['label_ko'] ?? '',
      bbox: BBox.fromPredictionEnvelope(json),
      confidence: (json['confidence'] as num?)?.toDouble(),
      distanceRaw: json['distance'] ?? '',
      distanceText: json['distance_text'] ?? '',
      position: json['position'] ?? 'center',
      positionKo: json['position_ko'] ?? '중앙',
      description: json['description'] ?? '',
      isEmpty: json['is_empty'] as bool?,
      riskLevel: (json['risk_level'] as num?)?.toInt() ?? 0,
      motionState: json['motion_state'] ?? 'stable',
      estimatedDistanceM: (json['estimated_distance_m'] as num?)?.toDouble() ?? 0.0,
      rawDepthValue: (json['raw_depth_value'] as num?)?.toDouble() ?? 0.0,
      referenceDepth: (json['reference_depth'] as num?)?.toDouble() ?? 1.0,
      distanceConfidence: json['distance_confidence'] ?? 'medium',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'label_ko': labelKo,
      'confidence': confidence,
      'position': position,
      'position_ko': positionKo,
      'distance': distanceRaw,
      'distance_text': distanceText,
      'is_empty': isEmpty,
      'description': description,
      'bbox': bbox.toJson(),
      'estimated_distance_m': estimatedDistanceM,
      'raw_depth_value': rawDepthValue,
      'reference_depth': referenceDepth,
      'distance_confidence': distanceConfidence,
      'risk_level': riskLevel,
      'motion_state': motionState,
    };
  }

  DetectionState get state {
    if (estimatedDistanceM <= 1.5 || riskLevel == 2) return DetectionState.danger;
    return DetectionState.safe;
  }
}

class PredictionResponse {
  final String riskLevel;
  final String mainHazard;
  final String safeDirection;
  final String guideMessage;
  final String guideSource;
  final String processTime;
  final List<DetectionResult> displayObjects;
  final List<DetectionResult> objects;

  const PredictionResponse({
    required this.riskLevel,
    required this.mainHazard,
    required this.safeDirection,
    this.guideMessage = '',
    this.guideSource = 'none',
    this.processTime = '0s',
    required this.displayObjects,
    required this.objects,
  });

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    final displayList = (json['display_objects'] as List?) ?? [];
    final objectsList = (json['objects'] as List?) ?? [];

    return PredictionResponse(
      riskLevel: json['risk_level'] as String? ?? 'safe',
      mainHazard: json['main_hazard'] as String? ?? '감지된 위험 요소 없음',
      safeDirection: json['safe_direction'] as String? ?? 'forward',
      guideMessage: json['guide_message'] as String? ?? '',
      guideSource: json['guide_source'] as String? ?? 'none',
      processTime: json['process_time'] as String? ?? '0s',
      displayObjects: displayList
          .whereType<Map>()
          .map((item) => DetectionResult.fromJson(item.cast<String, dynamic>()))
          .toList(),
      objects: objectsList
          .whereType<Map>()
          .map((item) => DetectionResult.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}
