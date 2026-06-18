import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Placeholder Sleep screen with dark styling.
class SleepScreen extends StatelessWidget {
  const SleepScreen({super.key});

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
                    'Sleep',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    'Today',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.pastelLavender,
                        ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.pastelLavender,
                    size: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // Sleep score
            _SleepScoreRing(),
            const SizedBox(height: 32),
            // Sleep stages
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSleepStagesCard(context),
            ),
            const SizedBox(height: 16),
            // Sleep details
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSleepDetailsCard(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepStagesCard(BuildContext context) {
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
          Text(
            'Sleep Stages',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          _SleepStageRow(
            label: 'Awake',
            duration: '0h 23m',
            fraction: 0.05,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          _SleepStageRow(
            label: 'REM',
            duration: '1h 45m',
            fraction: 0.25,
            color: AppColors.pastelLavender,
          ),
          const SizedBox(height: 12),
          _SleepStageRow(
            label: 'Light',
            duration: '3h 10m',
            fraction: 0.45,
            color: AppColors.pastelBlue,
          ),
          const SizedBox(height: 12),
          _SleepStageRow(
            label: 'Deep',
            duration: '1h 52m',
            fraction: 0.25,
            color: AppColors.pastelTeal,
          ),
        ],
      ),
    );
  }

  Widget _buildSleepDetailsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder, width: 0.5),
      ),
      child: Column(
        children: [
          _DetailRow(label: 'Total Sleep', value: '7h 10m'),
          const Divider(color: AppColors.divider, height: 24),
          _DetailRow(label: 'Time in Bed', value: '7h 33m'),
          const Divider(color: AppColors.divider, height: 24),
          _DetailRow(label: 'Sleep Efficiency', value: '95%'),
          const Divider(color: AppColors.divider, height: 24),
          _DetailRow(label: 'Resting HR', value: '52 bpm'),
          const Divider(color: AppColors.divider, height: 24),
          _DetailRow(label: 'Bedtime', value: '11:12 PM'),
        ],
      ),
    );
  }
}

class _SleepScoreRing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Glow
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pastelLavender.withValues(alpha: 0.12),
                    blurRadius: 40,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 160,
              height: 160,
              child: CircularProgressIndicator(
                value: 0.84,
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation(AppColors.pastelLavender),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '84',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontSize: 48,
                      ),
                ),
                Text(
                  'SLEEP',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.pastelLavender,
                        letterSpacing: 2.5,
                      ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Good',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.pastelLavender,
                fontSize: 15,
              ),
        ),
      ],
    );
  }
}

class _SleepStageRow extends StatelessWidget {
  final String label;
  final String duration;
  final double fraction;
  final Color color;

  const _SleepStageRow({
    required this.label,
    required this.duration,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          duration,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
