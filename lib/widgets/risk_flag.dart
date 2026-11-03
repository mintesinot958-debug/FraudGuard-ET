import 'package:flutter/material.dart';
import '../l10n.dart';

class RiskFlag extends StatelessWidget {
  final int score;

  const RiskFlag({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final (label, color) = score < 30
        ? (L.t('low'), Colors.green)
        : score < 60
            ? (L.t('medium'), Colors.orange)
            : (L.t('high'), Colors.red);

    return Semantics(
      label: '$label risk, $score out of 100',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
