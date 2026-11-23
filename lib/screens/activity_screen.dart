import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_activity.dart';
import '../providers/ble_providers.dart';
import '../providers/health_sync_providers.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_formatter.dart';

/// Activity tracking screen backed by Colmi R02 Sports Detail (`0x43`) sync.
///
/// Shows live sync controls when connected, and falls back to the last saved
/// daily activity + last-connected timestamp + 7-day daily averages when offline.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  String _formatNumber(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(bleConnectionStateProvider).valueOrNull ??
        BleConnectionState.disconnected;
    final isConnected = connState == BleConnectionState.connected;

    final latestActivity = ref.watch(latestActivityProvider).valueOrNull;
    final activityAverages = ref.watch(activityAveragesProvider).valueOrNull ??
        ActivityAverages.empty;
    final syncStatus = ref.watch(deviceSyncStatusProvider).valueOrNull;

    final lastTime = syncStatus?.lastConnectedAt ?? latestActivity?.syncedAt;

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
                  if (isConnected)
                    GestureDetector(
                      onTap: () {
                        unawaited(
                          ref.read(bleServiceProvider).syncActivity(daysBack: 7),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                const Text('Syncing step & calorie history…'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.surfaceLight,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.pastelAmber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.pastelAmber.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.sync_rounded,
                              color: AppColors.pastelAmber,
                              size: 15,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Sync Steps',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.pastelAmber,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.cardBorder,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        lastTime != null
                            ? 'Last sync ${DateFormatter.formatRelative(lastTime)}'
                            : 'Offline',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            if (latestActivity == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _EmptyActivityCard(isConnected: isConnected),
              )
            else ...[
              _ActivityRings(record: latestActivity),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildGoalCard(context, latestActivity),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildStatsGrid(context, latestActivity),
              ),
              if (activityAverages.daysCount > 0) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildDailyAverageCard(context, activityAverages),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGoalCard(BuildContext context, DailyActivityRecord record) {
    final pct = record.goalPercent;
    final status = pct >= 100
        ? 'GOAL ACHIEVED'
        : pct >= 60
            ? 'MAKING PROGRESS'
            : 'WARMING UP';

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
              const Icon(
                Icons.flag_rounded,
                color: AppColors.pastelAmber,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Activity goal · ${record.date}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.pastelAmber,
                  letterSpacing: 1.5,
                ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                '$pct',
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
                      child: LinearProgressIndicator(
                        value: record.goalProgress,
                        minHeight: 8,
                        backgroundColor: AppColors.surfaceVariant,
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.pastelAmber,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatNumber(record.steps),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.pastelAmber,
                                  ),
                        ),
                        Text(
                          _formatNumber(record.stepGoal),
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

  Widget _buildStatsGrid(BuildContext context, DailyActivityRecord record) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.local_fire_department_rounded,
            value: _formatNumber(record.calories),
            unit: 'cal',
            label: 'Activity Burn',
            color: AppColors.pastelCoral,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.directions_walk_rounded,
            value: _formatNumber(record.steps),
            unit: 'steps',
            label: '${record.distanceKm.toStringAsFixed(2)} km',
            color: AppColors.pastelAmber,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyAverageCard(BuildContext context, ActivityAverages avg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.pastelAmber.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Average (${avg.daysCount} ${avg.daysCount == 1 ? 'day' : 'days'})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.pastelAmber,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _AvgStatCell(
                  label: 'Avg Steps',
                  value: _formatNumber(avg.avgSteps.round()),
                ),
              ),
              Expanded(
                child: _AvgStatCell(
                  label: 'Avg Burn',
                  value: '${avg.avgCalories.round()} cal',
                ),
              ),
              Expanded(
                child: _AvgStatCell(
                  label: 'Avg Active',
                  value: '${avg.avgActiveMinutes.round()}m',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityRings extends StatelessWidget {
  final DailyActivityRecord record;
  const _ActivityRings({required this.record});

  @override
  Widget build(BuildContext context) {
    final stepProgress = record.goalProgress;
    final activeProgress = (record.activeMinutes / 60.0).clamp(0.0, 1.0);
    final calorieProgress = (record.calories / 500.0).clamp(0.0, 1.0);

    return Stack(
      alignment: Alignment.center,
      children: [
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
        SizedBox(
          width: 180,
          height: 180,
          child: CircularProgressIndicator(
            value: stepProgress,
            strokeWidth: 10,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation(AppColors.pastelAmber),
          ),
        ),
        SizedBox(
          width: 145,
          height: 145,
          child: CircularProgressIndicator(
            value: activeProgress,
            strokeWidth: 10,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation(AppColors.pastelSage),
          ),
        ),
        SizedBox(
          width: 110,
          height: 110,
          child: CircularProgressIndicator(
            value: calorieProgress,
            strokeWidth: 10,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation(AppColors.pastelCoral),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${record.goalPercent}',
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

class _AvgStatCell extends StatelessWidget {
  final String label;
  final String value;
  const _AvgStatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _EmptyActivityCard extends StatelessWidget {
  final bool isConnected;
  const _EmptyActivityCard({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder, width: 0.5),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.pastelAmber.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_walk_rounded,
              color: AppColors.pastelAmber,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isConnected
                ? 'No activity synced yet'
                : 'Ring Offline · No Activity History',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            isConnected
                ? 'Tap Sync Steps above to fetch steps, calories, and distance from your Colmi R02 ring.'
                : 'Connect your Colmi R02 smart ring to sync daily steps, active burn, and 7-day averages.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}
