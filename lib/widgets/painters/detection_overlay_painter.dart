import 'package:flutter/material.dart';
import '../../models/detection_result.dart';

class DetectionOverlayPainter extends CustomPainter {
  const DetectionOverlayPainter({
    required this.detections,
  });

  final List<DetectionResult> detections;

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    try {
      for (final detection in detections) {
        // 위험도에 따른 색상 설정
        Color riskColor;
        String riskText;
        if (detection.riskLevel == 2) {
          riskColor = Colors.red;
          riskText = '위험';
        } else if (detection.riskLevel == 1) {
          riskColor = Colors.orange;
          riskText = '주의';
        } else {
          riskColor = Colors.green;
          riskText = '안전';
        }

        final rectPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0 // 더 굵게 변경
          ..color = riskColor;

        final x1 = detection.bbox.x1;
        final y1 = detection.bbox.y1;
        final x2 = detection.bbox.x2;
        final y2 = detection.bbox.y2;

        final isNormalized = x2 <= 1.0 && y2 <= 1.0;
        final rect = isNormalized
            ? Rect.fromLTRB(
                x1 * size.width,
                y1 * size.height,
                x2 * size.width,
                y2 * size.height,
              )
            : Rect.fromLTRB(x1, y1, x2, y2);

        // 너무 작은 박스는 그리지 않음 (가독성 방해)
        if (rect.width < 10 || rect.height < 10) continue;

        canvas.drawRect(rect, rectPaint);

        // 라벨 생성: [이름] / [거리] / [위험도]
        final distStr = detection.distanceText.isNotEmpty ? ' / ${detection.distanceText}' : '';
        final labelText = '${detection.koreanName}$distStr / $riskText';
        
        final textSpan = TextSpan(
          text: labelText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18, // 글자 크기 확대
            fontWeight: FontWeight.bold,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width > 0 ? size.width : 100);

        const badgePadding = 8.0;
        final badgeHeight = textPainter.height + badgePadding;
        final badgeWidth = textPainter.width + badgePadding * 2;
        
        double safeTop = rect.top - badgeHeight;
        if (safeTop < 0) safeTop = rect.top; // 박스 안쪽에 표시

        final badgeRect = Rect.fromLTWH(rect.left, safeTop, badgeWidth, badgeHeight);

        // 고대비 배경
        canvas.drawRect(
          badgeRect,
          Paint()..color = riskColor.withOpacity(0.85),
        );
        
        textPainter.paint(
          canvas,
          Offset(
            badgeRect.left + badgePadding,
            badgeRect.top + badgePadding / 2,
          ),
        );
      }
    } catch (e) {
      debugPrint('Painting error: $e');
    }
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
