import 'dart:ui';

class ObjectDetection {
  const ObjectDetection({
    required this.label,
    required this.boundingBox,
    this.confidence,
  });

  final String label;
  final Rect boundingBox;
  final double? confidence;

  factory ObjectDetection.fromMap(Map<String, dynamic> map) {
    final left = (map['left'] as num?)?.toDouble() ?? 0;
    final top = (map['top'] as num?)?.toDouble() ?? 0;
    final width = (map['width'] as num?)?.toDouble() ?? 0;
    final height = (map['height'] as num?)?.toDouble() ?? 0;

    return ObjectDetection(
      label: (map['label'] as String?) ?? 'unknown',
      confidence: (map['confidence'] as num?)?.toDouble(),
      boundingBox: Rect.fromLTWH(left, top, width, height),
    );
  }
}
