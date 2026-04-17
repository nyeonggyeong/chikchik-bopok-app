import 'package:flutter/material.dart';
import '../../models/detection_result.dart';

class DetectionOverlayPainter extends CustomPainter {
  const DetectionOverlayPainter({
    required this.detections,
    required this.strokeColor,
  });

  final List<DetectionResult> detections;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rectPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = strokeColor;

    for (final detection in detections) {
      final x1 = detection.bbox.x1;
      final y1 = detection.bbox.y1;
      final x2 = detection.bbox.x2;
      final y2 = detection.bbox.y2;

      // 서버가 정규화 좌표(0~1) 혹은 절대 픽셀 좌표를 보낼 수 있으므로 둘 다 대응
      final isNormalized = x2 <= 1.0 && y2 <= 1.0;
      final rect = isNormalized
          ? Rect.fromLTRB(
              x1 * size.width,
              y1 * size.height,
              x2 * size.width,
              y2 * size.height,
            )
          : Rect.fromLTRB(x1, y1, x2, y2);

      canvas.drawRect(rect, rectPaint);

      final textSpan = TextSpan(
        text: '${detection.objectClass} ${detection.distanceM.toStringAsFixed(1)}m',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);

      final badgePadding = 6.0;
      final badgeHeight = textPainter.height + badgePadding * 2;
      final badgeWidth = textPainter.width + badgePadding * 2;
      final badgeTop = (rect.top - badgeHeight).clamp(0, size.height);
      final badgeRect = Rect.fromLTWH(rect.left, badgeTop.toDouble(), badgeWidth.toDouble(), badgeHeight.toDouble());

      canvas.drawRect(
        badgeRect,
        Paint()..color = Colors.black.withOpacity(0.72),
      );
      textPainter.paint(
        canvas,
        Offset(
          badgeRect.left + badgePadding,
          badgeRect.top + badgePadding,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.strokeColor != strokeColor;
  }
}
