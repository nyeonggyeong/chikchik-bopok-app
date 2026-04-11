import 'dart:math';
import 'package:flutter/material.dart';

class WaveformPainter extends CustomPainter {
  final double progress;

  WaveformPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final midY = h / 2;

    // progress에 따라 색상 펄스
    final paint = Paint()
      ..color = Color.lerp(
        const Color(0xFF3A8FD4),
        const Color(0xFF88CCFF),
        (sin(progress * pi * 2) + 1) / 2,
      )!
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // 하트비트 파형 포인트
    final points = [
      Offset(0, midY),
      Offset(w * 0.15, midY),
      Offset(w * 0.25, midY - h * 0.45),
      Offset(w * 0.35, midY + h * 0.45),
      Offset(w * 0.45, midY - h * 0.20),
      Offset(w * 0.55, midY),
      Offset(w * 0.70, midY),
      Offset(w * 0.80, midY - h * 0.35),
      Offset(w * 0.88, midY + h * 0.35),
      Offset(w * 0.95, midY),
      Offset(w, midY),
    ];

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(WaveformPainter old) => old.progress != progress;
}
