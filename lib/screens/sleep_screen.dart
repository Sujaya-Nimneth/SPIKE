import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sleep_session.dart';
import '../providers/ble_providers.dart';
import '../providers/health_sync_providers.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_formatter.dart';

/// Sleep tracking screen backed by Colmi R02 BigData (`0xBC` / `0x27`) sync.
///
/// Shows live sync controls when connected, and falls back to the last saved
/// sleep session + last-connected timestamp + 7-day daily averages when offline.
class SleepScreen extends ConsumerWidget {
  const SleepScreen({super.key});

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m';
  }

  String _qualityLabel(int score) {
    if (score >= 85) return 'Optimal';
    if (score >= 70) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Needs Rest';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(bleConnectionStateProvider).valueOrNull ??
        BleConnectionState.disconnected;
    final isConnected = connState == BleConnectionState.connected;

    final latestSleep = ref.watch(latestSleepProvider).valueOrNull;
    final sleepAverages =
        ref.watch(sleepAveragesProvider).valueOrNull ?? SleepAverages.empty;
    final syncStatus = ref.watch(deviceSyncStatusProvider).valueOrNull;

    final lastTime = syncStatus?.lastConnectedAt ?? latestSleep?.syncedAt;

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
                  if (isConnected)
                    _SyncActionChip(
                      color: AppColors.pastelLavender,
                      label: 'Sync Sleep',
                      onTap: () {
                        unawaited(ref.read(bleServiceProvider).syncSleep());
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Syncing sleep data from R02…'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppColors.surfaceLight,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    )
                  else
                    _OfflineSyncBadge(lastConnectedAt: lastTime),
                ],
              ),
            ),
            const SizedBox(height: 28),

            if (latestSleep == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _EmptyTelemetryCard(
                  icon: Icons.nightlight_round,
                  color: AppColors.pastelLavender,
                  title: isConnected
                      ? 'No sleep data synced yet'
                      : 'Ring Offline · No Sleep History',
                  subtitle: isConnected
                      ? 'Wear your Colmi R02 ring overnight and tap Sync Sleep to import sleep stages.'
                      : 'Connect your Colmi R02 smart ring to sync nightly sleep duration, efficiency, and stages.',
                ),
              )
            else ...[
              _SleepScoreRing(
                score: latestSleep.sleepScore,
                quality: _qualityLabel(latestSleep.sleepScore),
                dateLabel: latestSleep.date,
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSleepStagesCard(context, latestSleep),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSleepDetailsCard(context, latestSleep),
              ),
              if (sleepAverages.nightsCount > 0) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildDailyAverageCard(context, sleepAverages),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSleepStagesCard(
    BuildContext context,
    SleepSessionRecord session,
  ) {
    final totalTib = session.timeInBedMinutes > 0
        ? session.timeInBedMinutes
        : (session.awakeMinutes +
            session.remMinutes +
            session.lightMinutes +
            session.deepMinutes);
    double frac(int mins) =>
        totalTib > 0 ? (mins / totalTib).clamp(0.0, 1.0) : 0.0;

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
            duration: _formatDuration(session.awakeMinutes),
            fraction: frac(session.awakeMinutes),
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          _SleepStageRow(
            label: 'REM',
            duration: _formatDuration(session.remMinutes),
            fraction: frac(session.remMinutes),
            color: AppColors.pastelLavender,
          ),
          const SizedBox(height: 12),
          _SleepStageRow(
            label: 'Light',
            duration: _formatDuration(session.lightMinutes),
            fraction: frac(session.lightMinutes),
            color: AppColors.pastelBlue,
          ),
          const SizedBox(height: 12),
          _SleepStageRow(
            label: 'Deep',
            duration: _formatDuration(session.deepMinutes),
            fraction: frac(session.deepMinutes),
            color: AppColors.pastelTeal,
          ),
        ],
      ),
    );
  }

  Widget _buildSleepDetailsCard(
    BuildContext context,
    SleepSessionRecord session,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder, width: 0.5),
      ),
      child: Column(
        children: [
          _DetailRow(
            label: 'Total Sleep',
            value: _formatDuration(session.totalSleepMinutes),
          ),
          const Divider(color: AppColors.divider, height: 24),
          _DetailRow(
            label: 'Time in Bed',
            value: _formatDuration(session.timeInBedMinutes),
          ),
          const Divider(color: AppColors.divider, height: 24),
          _DetailRow(
            label: 'Sleep Efficiency',
            value: '${session.efficiencyPercent}%',
          ),
          const Divider(color: AppColors.divider, height: 24),
          _DetailRow(
            label: 'Resting HR',
            value:
                session.restingHr != null ? '${session.restingHr} bpm' : '--',
          ),
          const Divider(color: AppColors.divider, height: 24),
          _DetailRow(
            label: 'Bedtime',
            value: session.bedtime != null
                ? DateFormatter.formatClockTime(session.bedtime!)
                : '--',
          ),
        ],
      ),
    );
  }

  Widget _buildDailyAverageCard(BuildContext context, SleepAverages avg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.pastelLavender.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Average (${avg.nightsCount} ${avg.nightsCount == 1 ? 'night' : 'nights'})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.pastelLavender,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _AvgStatCell(
                  label: 'Avg Sleep',
                  value: _formatDuration(avg.avgTotalSleepMinutes.round()),
                ),
              ),
              Expanded(
                child: _AvgStatCell(
                  label: 'Avg Score',
                  value: '${avg.avgSleepScore.round()}',
                ),
              ),
              Expanded(
                child: _AvgStatCell(
                  label: 'Avg Eff.',
                  value: '${avg.avgEfficiencyPercent.round()}%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SleepScoreRing extends StatelessWidget {
  final int score;
  final String quality;
  final String dateLabel;

  const _SleepScoreRing({
    required this.score,
    required this.quality,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
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
                value: (score / 100.0).clamp(0.0, 1.0),
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: AppColors.surfaceVariant,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.pastelLavender),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$score',
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
        const SizedBox(height: 14),
        Text(
          '$quality · $dateLabel',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.pastelLavender,
                fontSize: 13,
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

class _SyncActionChip extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _SyncActionChip({
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_rounded, color: color, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineSyncBadge extends StatelessWidget {
  final DateTime? lastConnectedAt;
  const _OfflineSyncBadge({required this.lastConnectedAt});

  @override
  Widget build(BuildContext context) {
    final label = lastConnectedAt != null
        ? 'Last sync ${DateFormatter.formatRelative(lastConnectedAt!)}'
        : 'Offline';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder, width: 0.5),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
      ),
    );
  }
}

class _EmptyTelemetryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _EmptyTelemetryCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

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
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
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
