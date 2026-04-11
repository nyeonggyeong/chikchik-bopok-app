import 'package:flutter/material.dart';

class CityscapePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final buildingPaint = Paint()..color = const Color(0xFF1A1A2E);
    final windowPaint = Paint()
      ..color = const Color(0xFFFFD070).withOpacity(0.4);

    // 건물 실루엣
    final buildings = [
      Rect.fromLTWH(
        0,
        size.height * 0.55,
        size.width * 0.12,
        size.height * 0.45,
      ),
      Rect.fromLTWH(
        size.width * 0.10,
        size.height * 0.45,
        size.width * 0.08,
        size.height * 0.55,
      ),
      Rect.fromLTWH(
        size.width * 0.20,
        size.height * 0.50,
        size.width * 0.15,
        size.height * 0.50,
      ),
      Rect.fromLTWH(
        size.width * 0.38,
        size.height * 0.40,
        size.width * 0.10,
        size.height * 0.60,
      ),
      Rect.fromLTWH(
        size.width * 0.50,
        size.height * 0.48,
        size.width * 0.18,
        size.height * 0.52,
      ),
      Rect.fromLTWH(
        size.width * 0.70,
        size.height * 0.42,
        size.width * 0.12,
        size.height * 0.58,
      ),
      Rect.fromLTWH(
        size.width * 0.85,
        size.height * 0.52,
        size.width * 0.15,
        size.height * 0.48,
      ),
    ];
    for (final b in buildings) canvas.drawRect(b, buildingPaint);

    // 창문 불빛
    final windows = [
      Offset(size.width * 0.02, size.height * 0.60),
      Offset(size.width * 0.06, size.height * 0.65),
      Offset(size.width * 0.13, size.height * 0.52),
      Offset(size.width * 0.25, size.height * 0.55),
      Offset(size.width * 0.30, size.height * 0.62),
      Offset(size.width * 0.40, size.height * 0.48),
      Offset(size.width * 0.55, size.height * 0.55),
      Offset(size.width * 0.60, size.height * 0.62),
      Offset(size.width * 0.72, size.height * 0.50),
      Offset(size.width * 0.78, size.height * 0.58),
      Offset(size.width * 0.88, size.height * 0.56),
      Offset(size.width * 0.93, size.height * 0.62),
    ];
    for (final w in windows) {
      canvas.drawRect(
        Rect.fromCenter(center: w, width: 4, height: 5),
        windowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
