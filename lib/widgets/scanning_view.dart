import 'package:flutter/material.dart';
import 'painters/waveform_painter.dart';

class ScanningView extends StatefulWidget {
  const ScanningView({super.key});

  @override
  State<ScanningView> createState() => _ScanningViewState();
}

class _ScanningViewState extends State<ScanningView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 파형 아이콘
        SizedBox(
          width: 80,
          height: 50,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (_, __) => CustomPaint(
              painter: WaveformPainter(progress: _animation.value),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '탐지  중...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }
}
