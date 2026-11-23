import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A small metric card with a mini circular indicator, score, and label.
///
/// Used in the horizontal metric row on the home dashboard.
class MetricCard extends StatelessWidget {
  final String title;
  final int? score;
  final Color accentColor;
  final IconData icon;
  final String? statusOverride;
  final VoidCallback? onTap;

  const MetricCard({
    super.key,
    required this.title,
    required this.score,
    required this.accentColor,
    required this.icon,
    this.statusOverride,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final valueText = score != null ? '$score' : '--';
    final progressFactor = score != null ? (score! / 100.0) : 0.0;
    final statusText = statusOverride ??
        (score != null ? _getStatusText(score!) : 'NO DATA');

    return Semantics(
      button: onTap != null,
      label: '$title: $valueText, $statusText',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 145,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.15),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: accentColor, size: 18),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      valueText,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w300,
                            fontSize: 32,
                          ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: _MiniProgressBar(
                        value: progressFactor,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: score != null
                            ? accentColor
                            : AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getStatusText(int score) {
    if (score >= 85) return 'OPTIMAL';
    if (score >= 70) return 'GOOD';
    if (score >= 50) return 'FAIR';
    return 'NEEDS CARE';
  }
}

/// A tiny horizontal progress bar for metric cards.
class _MiniProgressBar extends StatelessWidget {
  final double value;
  final Color color;

  const _MiniProgressBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Stack(
          children: [
            Container(color: AppColors.surfaceVariant),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.6), color],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
