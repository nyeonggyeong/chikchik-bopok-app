import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 초록 점 (글로우 효과 포함)
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF4ADE80),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4ADE80).withOpacity(0.6),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'SYSTEM ACTIVE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}
