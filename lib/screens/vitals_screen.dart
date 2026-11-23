import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_providers.dart';
import '../providers/health_sync_providers.dart';
import '../providers/stress_providers.dart';
import '../providers/vitals_provider.dart';
import '../services/ble_service.dart';
import '../services/stress/stress_detector.dart';
import '../theme/app_colors.dart';
import '../utils/app_routes.dart';
import '../utils/date_formatter.dart';
import 'vital_details_screen.dart';

/// Vitals screen displaying real-time smart ring telemetry when connected, and
/// last-recorded values + last-connected timestamp + daily average when offline.
class VitalsScreen extends ConsumerWidget {
  const VitalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState =
        ref.watch(bleConnectionStateProvider).valueOrNull ??
            BleConnectionState.disconnected;
    final isConnected = connectionState == BleConnectionState.connected;

    final liveHr = ref.watch(liveVitalsProvider.select((s) => s.heartRate));
    final minHr = ref.watch(liveVitalsProvider.select((s) => s.minHeartRate));
    final maxHr = ref.watch(liveVitalsProvider.select((s) => s.maxHeartRate));
    final avgHr = ref.watch(liveVitalsProvider.select((s) => s.avgHeartRate));

    final calmScore = ref.watch(calmScoreProvider).valueOrNull ?? 88;
    final phase = ref.watch(stressPhaseProvider).valueOrNull ??
        StressDetectionPhase.warmingUp;
    final baseline = ref.watch(baselineHrProvider).valueOrNull;

    final lastSummary = ref.watch(latestHrSummaryProvider).valueOrNull;
    final dailyAvgs = ref.watch(dailyHrAveragesProvider).valueOrNull;
    final syncStatus = ref.watch(deviceSyncStatusProvider).valueOrNull;

    final int? shownHr = isConnected ? liveHr : lastSummary?.lastHr;
    final lastTime = syncStatus?.lastConnectedAt ?? lastSummary?.updatedAt;

    final String hrSubtitle;
    final String hrTrend;
    if (isConnected) {
      hrSubtitle = 'Real-time optical PPG sensor';
      hrTrend = liveHr != null
          ? 'Streaming live from R02 ring'
          : 'Connected — waiting for first pulse lock';
    } else if (lastTime != null) {
      hrSubtitle = 'Last recorded heart rate';
      hrTrend =
          'Last connected ${DateFormatter.formatRelative(lastTime)} · Tap for trends';
    } else {
      hrSubtitle = 'Real-time optical PPG sensor';
      hrTrend = 'Connect ring to start heart rate streaming';
    }

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Vitals',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  _ConnectionStatusPill(state: connectionState),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Primary Heart Rate Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.favorite_rounded,
                title: 'Heart Rate',
                value: shownHr != null ? '$shownHr bpm' : '-- bpm',
                subtitle: hrSubtitle,
                color: AppColors.pastelCoral,
                trend: hrTrend,
                onTap: () => Navigator.of(context).push(
                  AppRoutes.fadeSlideUp(
                    const VitalDetailsScreen(vitalType: VitalType.heartRate),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stress & Rolling Baseline Telemetry Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _StressTelemetryCard(
                calmScore: isConnected ? calmScore : null,
                baselineHr:
                    baseline?.round() ?? lastSummary?.restingHr,
                phase: phase,
                isConnected: isConnected,
                lastConnectedAt: lastTime,
              ),
            ),
            const SizedBox(height: 16),

            // Session / Offline Daily Average Stats Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SessionStatsCard(
                isConnected: isConnected,
                sessionMinHr: minHr,
                sessionMaxHr: maxHr,
                sessionAvgHr: avgHr,
                baselineHr: baseline?.round(),
                lastSavedMinHr: lastSummary?.minHr,
                lastSavedMaxHr: lastSummary?.maxHr,
                dailyAvgHr: dailyAvgs?.avgDailyHr?.round(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatusPill extends StatelessWidget {
  final BleConnectionState state;
  const _ConnectionStatusPill({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      BleConnectionState.connected => ('LIVE', AppColors.pastelSage),
      BleConnectionState.scanning => ('SCANNING', AppColors.pastelAmber),
      BleConnectionState.connecting => ('CONNECTING', AppColors.pastelAmber),
      BleConnectionState.error => ('ERROR', AppColors.pastelCoral),
      BleConnectionState.disconnected => ('OFFLINE', AppColors.textTertiary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _StressTelemetryCard extends StatelessWidget {
  final int? calmScore;
  final int? baselineHr;
  final StressDetectionPhase phase;
  final bool isConnected;
  final DateTime? lastConnectedAt;

  const _StressTelemetryCard({
    required this.calmScore,
    required this.baselineHr,
    required this.phase,
    required this.isConnected,
    required this.lastConnectedAt,
  });

  @override
  Widget build(BuildContext context) {
    final (phaseLabel, phaseColor, phaseIcon) = isConnected
        ? switch (phase) {
            StressDetectionPhase.warmingUp => (
                'Calibrating 10-min rolling baseline…',
                AppColors.pastelTeal,
                Icons.timelapse_rounded,
              ),
            StressDetectionPhase.calm => (
                'Calm — within normal baseline variability',
                AppColors.pastelSage,
                Icons.self_improvement_rounded,
              ),
            StressDetectionPhase.elevated => (
                'Elevated HR — monitoring sustained spike',
                AppColors.pastelAmber,
                Icons.trending_up_rounded,
              ),
            StressDetectionPhase.stressed => (
                'Stress Episode Active (≥25% / z≥2.5)',
                AppColors.pastelCoral,
                Icons.whatshot_rounded,
              ),
            StressDetectionPhase.recovering => (
                'Recovering — returning to baseline',
                AppColors.pastelLavender,
                Icons.favorite_border_rounded,
              ),
          }
        : (
            lastConnectedAt != null
                ? 'Ring offline · Last synced ${DateFormatter.formatRelative(lastConnectedAt!)}'
                : 'Waiting for ring connection',
            AppColors.textSecondary,
            Icons.bluetooth_disabled_rounded,
          );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: phaseColor.withValues(alpha: 0.18),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: phaseColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(phaseIcon, color: phaseColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stress & Baseline Engine',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      calmScore != null
                          ? 'Calm Score $calmScore'
                          : 'Calm Score --',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                              ),
                    ),
                  ],
                ),
              ),
              if (baselineHr != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Baseline $baselineHr bpm',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            phaseLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: phaseColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _SessionStatsCard extends StatelessWidget {
  final bool isConnected;
  final int? sessionMinHr;
  final int? sessionMaxHr;
  final int? sessionAvgHr;
  final int? baselineHr;
  final int? lastSavedMinHr;
  final int? lastSavedMaxHr;
  final int? dailyAvgHr;

  const _SessionStatsCard({
    required this.isConnected,
    required this.sessionMinHr,
    required this.sessionMaxHr,
    required this.sessionAvgHr,
    required this.baselineHr,
    required this.lastSavedMinHr,
    required this.lastSavedMaxHr,
    required this.dailyAvgHr,
  });

  @override
  Widget build(BuildContext context) {
    final avgDisplay = isConnected ? sessionAvgHr : dailyAvgHr;
    final minDisplay = isConnected ? sessionMinHr : lastSavedMinHr;
    final maxDisplay = isConnected ? sessionMaxHr : lastSavedMaxHr;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.cardBorder,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isConnected
                    ? 'Live Session Summary'
                    : 'Saved Daily Telemetry',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
              ),
              if (dailyAvgHr != null && isConnected)
                Text(
                  '7d Avg $dailyAvgHr bpm',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                )
              else if (baselineHr != null)
                Text(
                  'Baseline $baselineHr bpm',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStatBox(
                  label: isConnected ? 'Session Avg' : 'Daily Avg',
                  value: avgDisplay != null ? '$avgDisplay' : '--',
                  unit: 'bpm',
                  color: AppColors.pastelTeal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStatBox(
                  label: 'Min HR',
                  value: minDisplay != null ? '$minDisplay' : '--',
                  unit: 'bpm',
                  color: AppColors.pastelSage,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStatBox(
                  label: 'Max HR',
                  value: maxDisplay != null ? '$maxDisplay' : '--',
                  unit: 'bpm',
                  color: AppColors.pastelCoral,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStatBox extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _MiniStatBox({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 3),
              Text(
                unit,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ),
        ],
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
  final VoidCallback? onTap;

  const _VitalTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.trend,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$title · $subtitle',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trend,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
