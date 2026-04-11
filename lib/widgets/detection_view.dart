import 'package:flutter/material.dart';
import '../models/detection_result.dart';

class DetectionView extends StatelessWidget {
  final DetectionResult result;

  const DetectionView({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 객체 이름 (예: "사람")
        Text(
          result.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 64,
            fontWeight: FontWeight.bold,
            height: 1.1,
            shadows: [
              Shadow(
                color: Colors.black54,
                blurRadius: 12,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 거리 (예: "4.5 m")
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              result.distance.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 72,
                fontWeight: FontWeight.bold,
                height: 1.0,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'm',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
