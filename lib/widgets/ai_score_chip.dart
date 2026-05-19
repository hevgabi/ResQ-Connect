import 'package:flutter/material.dart';

/// Displays a colored confidence chip based on an AI-computed score.
///
/// Score thresholds:
///   >= 75  → Purple  ("X% Confidence")
///   40–74  → Orange  ("X% Moderate")
///    < 40  → Red     ("X% Low")
class AiScoreChip extends StatelessWidget {
  final double score;
  final bool showLabel;
  final double fontSize;

  const AiScoreChip({
    super.key,
    required this.score,
    this.showLabel = true,
    this.fontSize = 12,
  });

  _ChipStyle get _style {
    if (score >= 75) {
      return _ChipStyle(
        background: const Color(0xFF6A1B9A),
        foreground: Colors.white,
        label: 'Confidence',
        icon: Icons.verified_outlined,
      );
    } else if (score >= 40) {
      return _ChipStyle(
        background: const Color(0xFFFF6B00),
        foreground: Colors.white,
        label: 'Moderate',
        icon: Icons.info_outline,
      );
    } else {
      return _ChipStyle(
        background: const Color(0xFFD7263D),
        foreground: Colors.white,
        label: 'Low',
        icon: Icons.warning_amber_outlined,
      );
    }
  }

  String get _scoreText => '${score.toStringAsFixed(0)}%';

  @override
  Widget build(BuildContext context) {
    final style = _style;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: style.background.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.foreground, size: fontSize + 2),
          const SizedBox(width: 4),
          Text(
            showLabel ? '$_scoreText ${style.label}' : _scoreText,
            style: TextStyle(
              color: style.foreground,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipStyle {
  final Color background;
  final Color foreground;
  final String label;
  final IconData icon;

  const _ChipStyle({
    required this.background,
    required this.foreground,
    required this.label,
    required this.icon,
  });
}
