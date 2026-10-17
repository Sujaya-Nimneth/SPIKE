import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../providers/ble_providers.dart';
import '../providers/stress_providers.dart';
import '../providers/vitals_provider.dart';
import '../services/ble_service.dart';
import '../services/stress/stress_detector.dart';
import '../utils/app_routes.dart';
import 'vital_details_screen.dart';

/// Vitals screen displaying real-time smart ring telemetry.
///
/// Simulated vitals without hardware backing are hidden; displays live
/// Heart Rate, rolling stress baseline, and session heart rate statistics.
class VitalsScreen extends ConsumerWidget {
  const VitalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(bleConnectionStateProvider);
    final connectionState =
        connectionAsync.valueOrNull ?? BleConnectionState.disconnected;
    final isConnected = connectionState == BleConnectionState.connected;

    final heartRate = ref.watch(liveVitalsProvider.select((s) => s.heartRate));
    final minHr = ref.watch(liveVitalsProvider.select((s) => s.minHeartRate));
    final maxHr = ref.watch(liveVitalsProvider.select((s) => s.maxHeartRate));
    final avgHr = ref.watch(liveVitalsProvider.select((s) => s.avgHeartRate));

    final calmScore = ref.watch(calmScoreProvider).valueOrNull ?? 88;
    final phase = ref.watch(stressPhaseProvider).valueOrNull ??
        StressDetectionPhase.warmingUp;
    final baseline = ref.watch(stressAnalyzerProvider).currentBaseline;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Header with connection status badge
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

            // Primary Real-Time Heart Rate Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.favorite_rounded,
                title: 'Heart Rate',
                value: '$heartRate bpm',
                subtitle: 'Real-time optical PPG sensor',
                color: AppColors.pastelCoral,
                trend: isConnected
                    ? 'Streaming live from R02 ring'
                    : 'Tap to view 24h & weekly history',
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
                calmScore: calmScore,
                baselineHr: baseline?.round(),
                phase: phase,
                isConnected: isConnected,
              ),
            ),
            const SizedBox(height: 16),

            // Session Heart Rate Summary Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _SessionStatsCard(
                minHr: minHr,
                maxHr: maxHr,
                avgHr: avgHr,
                baselineHr: baseline?.round(),
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
  final int calmScore;
  final int? baselineHr;
  final StressDetectionPhase phase;
  final bool isConnected;

  const _StressTelemetryCard({
    required this.calmScore,
    required this.baselineHr,
    required this.phase,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final (phaseLabel, phaseColor, phaseIcon) = switch (phase) {
      StressDetectionPhase.warmingUp => (
        isConnected ? 'Calibrating 10-min rolling baseline…' : 'Waiting for ring connection',
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
    };

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
                      'Calm Score $calmScore',
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
  final int? minHr;
  final int? maxHr;
  final int? avgHr;
  final int? baselineHr;

  const _SessionStatsCard({
    required this.minHr,
    required this.maxHr,
    required this.avgHr,
    required this.baselineHr,
  });

  @override
  Widget build(BuildContext context) {
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
          Text(
            'Session Telemetry Summary',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStatBox(
                  label: 'Session Avg',
                  value: avgHr != null ? '$avgHr' : '--',
                  unit: 'bpm',
                  color: AppColors.pastelTeal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStatBox(
                  label: 'Min HR',
                  value: minHr != null ? '$minHr' : '--',
                  unit: 'bpm',
                  color: AppColors.pastelSage,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStatBox(
                  label: 'Max HR',
                  value: maxHr != null ? '$maxHr' : '--',
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
