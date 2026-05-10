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
  /// YOLO 클래스명 등 (예: person, chair)
  final String label;
  /// 미터 거리 숫자 (깊이 맵 또는 distance 문자열에서 파싱)
  final double distanceM;
  final BBox bbox;
  final double? confidence;

  /// 백엔드 `distance` 필드 문자열 원본 (예: "3.5m")
  final String distanceRaw;

  /// "왼쪽" | "중앙" | "오른쪽"
  final String position;

  /// 음성 가이드용 한국어 문장 (`/predict/objects-distance` 전용이면 채워짐)
  final String description;

  /// chair일 때 빈 좌석 여부, 그 외 null
  final bool? seatIsEmpty;

  const DetectionResult({
    required this.label,
    required this.distanceM,
    required this.bbox,
    this.confidence,
    this.distanceRaw = '',
    this.position = '중앙',
    this.description = '',
    this.seatIsEmpty,
  });

  /// 레거시 화면/위젯 호환용
  String get objectClass => label;
  double get distance => distanceM;

  // 영문 클래스명을 한국어로 변환해주는 getter (TTS용)
  String get koreanName {
    const translationMap = {
      'person': '사람',
      'bicycle': '자전거',
      'car': '자동차',
      'motorcycle': '오토바이',
      'airplane': '비행기',
      'bus': '버스',
      'train': '기차',
      'truck': '트럭',
      'boat': '배',
      'traffic light': '신호등',
      'fire hydrant': '소화전',
      'stop sign': '정지 표지판',
      'parking meter': '주차 요금 기계',
      'bench': '벤치',
      'bird': '새',
      'cat': '고양이',
      'dog': '개',
      'horse': '말',
      'sheep': '양',
      'cow': '소',
      'elephant': '코끼리',
      'bear': '곰',
      'zebra': '얼룩말',
      'giraffe': '기린',
      'backpack': '가방',
      'umbrella': '우산',
      'handbag': '핸드백',
      'tie': '넥타이',
      'suitcase': '여행 가방',
      'frisbee': '원반',
      'skis': '스키',
      'snowboard': '스노우보드',
      'sports ball': '공',
      'kite': '연',
      'baseball bat': '야구 배트',
      'baseball glove': '야구 글러브',
      'skateboard': '스케이트보드',
      'surfboard': '서핑보드',
      'tennis racket': '테니스 라켓',
      'bottle': '병',
      'wine glass': '와인 잔',
      'cup': '컵',
      'fork': '포크',
      'knife': '칼',
      'spoon': '숟가락',
      'bowl': '그릇',
      'banana': '바나나',
      'apple': '사과',
      'sandwich': '샌드위치',
      'orange': '오렌지',
      'broccoli': '브로콜리',
      'carrot': '당근',
      'hot dog': '핫도그',
      'pizza': '피자',
      'donut': '도넛',
      'cake': '케이크',
      'chair': '의자',
      'couch': '소파',
      'potted plant': '화분',
      'bed': '침대',
      'dining table': '식탁',
      'toilet': '변기',
      'tv': 'TV',
      'laptop': '노트북',
      'mouse': '마우스',
      'remote': '리모컨',
      'keyboard': '키보드',
      'cell phone': '휴대폰',
      'microwave': '전자레인지',
      'oven': '오븐',
      'toaster': '토스터',
      'sink': '싱크대',
      'refrigerator': '냉장고',
      'book': '책',
      'clock': '시계',
      'vase': '꽃병',
      'scissors': '가위',
      'teddy bear': '곰 인형',
      'hair drier': '헤어드라이어',
      'toothbrush': '칫솔',
    };
    return translationMap[label.toLowerCase()] ?? label;
  }

  static double _distanceMFromJson(Map<String, dynamic> json) {
    final est = json['distance_estimate_m'];
    if (est is num) {
      final v = est.toDouble();
      if (v > 0) return v;
    }

    final raw = json['distance'];
    if (raw is String) {
      final m = RegExp(
        r'([\d.]+)\s*m?',
        caseSensitive: false,
      ).firstMatch(raw.trim());
      if (m != null) {
        final parsed = double.tryParse(m.group(1)!);
        if (parsed != null && parsed >= 0) return parsed;
      }
    }

    return 0.0;
  }

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    var distance = _distanceMFromJson(json);

    if (distance <= 0) {
      if (json['is_dangerous'] == true) {
        distance = 1.0;
      } else if (json['is_over_30_percent'] == true) {
        distance = 1.0;
      } else {
        distance = 3.0;
      }
    }

    String? lbl;
    final rawLbl = json['label'];
    if (rawLbl is String && rawLbl.trim().isNotEmpty) {
      lbl = rawLbl.trim();
    }

    return DetectionResult(
      label:
          lbl ??
          (json['class_name'] as String?) ??
          (json['class'] as String?) ??
          'unknown',
      distanceM: distance,
      bbox: BBox.fromPredictionEnvelope(json),
      confidence: (json['confidence'] as num?)?.toDouble(),
      distanceRaw: (json['distance'] as String?) ?? '',
      position: (json['position'] as String?) ?? '중앙',
      description: (json['description'] as String?) ?? '',
      seatIsEmpty: json['is_empty'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'distance_m': distanceM,
      'bbox': bbox.toJson(),
      if (confidence != null) 'confidence': confidence,
      if (distanceRaw.isNotEmpty) 'distance': distanceRaw,
      if (description.isNotEmpty) 'description': description,
      if (seatIsEmpty != null) 'is_empty': seatIsEmpty,
      'position': position,
    };
  }

  // 거리에 따라 자동으로 상태 반환
  DetectionState get state {
    if (distanceM <= 2.0) return DetectionState.danger;
    return DetectionState.safe;
  }
}
