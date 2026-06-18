import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Placeholder Vitals screen with dark styling.
class VitalsScreen extends StatelessWidget {
  const VitalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Vitals',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 24),
            // Vital cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.favorite_rounded,
                title: 'Heart Rate',
                value: '72 bpm',
                subtitle: 'Resting average',
                color: AppColors.pastelCoral,
                trend: '↓ 3 from yesterday',
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.show_chart_rounded,
                title: 'HRV',
                value: '45 ms',
                subtitle: 'Heart rate variability',
                color: AppColors.pastelSage,
                trend: '↑ 5 from yesterday',
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.thermostat_rounded,
                title: 'Body Temperature',
                value: '+0.2°',
                subtitle: 'Deviation from baseline',
                color: AppColors.pastelAmber,
                trend: 'Within normal range',
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.air_rounded,
                title: 'Respiratory Rate',
                value: '15.2',
                subtitle: 'Breaths per minute',
                color: AppColors.pastelBlue,
                trend: 'Stable',
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.water_drop_rounded,
                title: 'SpO2',
                value: '97%',
                subtitle: 'Blood oxygen average',
                color: AppColors.pastelLavender,
                trend: 'Healthy range',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VitalTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final String trend;

  const _VitalTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  trend,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
          // Chevron
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
            size: 24,
          ),
        ],
      ),
    );
  }
}
