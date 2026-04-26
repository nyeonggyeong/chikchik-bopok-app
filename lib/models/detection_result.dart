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

  Map<String, dynamic> toJson() {
    return {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2};
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
    return translationMap[objectClass.toLowerCase()] ?? objectClass;
  }

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    // 백엔드 Lite-Mono 모델이 계산한 거리(m) 사용
    double distance = (json['distance_estimate_m'] as num?)?.toDouble() ?? 0;

    // 만약 깊이 추정이 실패했거나 없는 경우 백엔드의 is_dangerous 속성을 참고하여 안전/위험 거리 임시 할당
    if (distance == 0) {
      if (json['is_dangerous'] == true) {
        distance = 1.0;
      } else if (json['is_over_30_percent'] == true) {
        distance = 1.0;
      } else {
        distance = 3.0;
      }
    }

    return DetectionResult(
      objectClass:
          (json['class_name'] as String?) ??
          (json['class'] as String?) ??
          'unknown',
      distanceM: distance,
      bbox: BBox.fromJson(
        (json['bbox'] as Map?)?.cast<String, dynamic>() ?? {},
      ),
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
