import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Placeholder Activity screen with dark styling.
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Activity',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    'Today',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.pastelAmber,
                        ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.pastelAmber,
                    size: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Activity rings
            _ActivityRings(),
            const SizedBox(height: 32),
            // Activity goal card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildGoalCard(context),
            ),
            const SizedBox(height: 16),
            // Stats grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildStatsGrid(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: AppColors.pastelAmber, size: 20),
              const SizedBox(width: 8),
              Text(
                'Activity goal',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'MAKING PROGRESS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.pastelAmber,
                  letterSpacing: 1.5,
                ),
          ),
          const SizedBox(height: 20),
          // Progress bar
          Row(
            children: [
              Text(
                '50',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: 40,
                      fontWeight: FontWeight.w300,
                    ),
              ),
              Text(
                '%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        value: 0.5,
                        minHeight: 8,
                        backgroundColor: AppColors.surfaceVariant,
                        valueColor:
                            AlwaysStoppedAnimation(AppColors.pastelAmber),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '5,203',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.pastelAmber,
                                  ),
                        ),
                        Text(
                          '8,800',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.local_fire_department_rounded,
            value: '478',
            unit: 'cal',
            label: 'Activity Burn',
            color: AppColors.pastelCoral,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.directions_walk_rounded,
            value: '8,125',
            unit: 'steps',
            label: 'Steps',
            color: AppColors.pastelAmber,
          ),
        ),
      ],
    );
  }
}

class _ActivityRings extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.pastelAmber.withValues(alpha: 0.1),
                blurRadius: 40,
                spreadRadius: 5,
              ),
            ],
          ),
        ),
        // Outer ring — Move
        SizedBox(
          width: 180,
          height: 180,
          child: CircularProgressIndicator(
            value: 0.91,
            strokeWidth: 10,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation(AppColors.pastelAmber),
          ),
        ),
        // Middle ring — Exercise
        SizedBox(
          width: 145,
          height: 145,
          child: CircularProgressIndicator(
            value: 0.65,
            strokeWidth: 10,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation(AppColors.pastelSage),
          ),
        ),
        // Inner ring — Stand
        SizedBox(
          width: 110,
          height: 110,
          child: CircularProgressIndicator(
            value: 0.78,
            strokeWidth: 10,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation(AppColors.pastelCoral),
          ),
        ),
        // Center score
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '91',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: 36,
                  ),
            ),
            Text(
              'ACTIVITY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.pastelAmber,
                    letterSpacing: 2,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w400,
                    ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
