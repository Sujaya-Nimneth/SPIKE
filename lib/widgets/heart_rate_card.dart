import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_providers.dart';
import '../providers/health_sync_providers.dart';
import '../providers/vitals_provider.dart';
import '../screens/vital_details_screen.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_routes.dart';
import '../utils/date_formatter.dart';

/// A dark-themed heart rate chart card using fl_chart.
///
/// Shows live scrolling BPM samples when connected, and falls back to the last
/// saved heart rate + last-connected time + 7-day daily average when offline.
class HeartRateCard extends ConsumerWidget {
  const HeartRateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState =
        ref.watch(bleConnectionStateProvider).valueOrNull ??
            BleConnectionState.disconnected;
    final isConnected = connectionState == BleConnectionState.connected;
    final history =
        ref.watch(liveVitalsProvider.select((s) => s.heartRateHistory));

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          AppRoutes.fadeSlideUp(
            const VitalDetailsScreen(vitalType: VitalType.heartRate),
          ),
        );
      },
      child: Container(
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
            const _HeartRateHeaderRow(),
            const SizedBox(height: 20),
            if (isConnected) ...[
              RepaintBoundary(
                child: SizedBox(
                  height: 150,
                  child: _LiveHeartRateChart(history: history),
                ),
              ),
              if (history.length >= 2) ...[
                const SizedBox(height: 12),
                _LiveTimeAxisLabels(history: history),
              ],
            ] else
              const _OfflineHeartRateSummary(),
          ],
        ),
      ),
    );
  }
}

class _HeartRateHeaderRow extends ConsumerWidget {
  const _HeartRateHeaderRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestHr = ref.watch(latestHeartRateProvider);
    final connectionState =
        ref.watch(bleConnectionStateProvider).valueOrNull ??
            BleConnectionState.disconnected;
    final isConnected = connectionState == BleConnectionState.connected;
    final lastSummary = ref.watch(latestHrSummaryProvider).valueOrNull;
    final syncStatus = ref.watch(deviceSyncStatusProvider).valueOrNull;

    final int? displayHr = isConnected ? latestHr : lastSummary?.lastHr;
    final lastTime = syncStatus?.lastConnectedAt ?? lastSummary?.updatedAt;

    final String subtitleText;
    final Color subtitleColor;
    if (isConnected) {
      subtitleText =
          latestHr != null ? 'Live from R02' : 'Connected · Waiting for PPG';
      subtitleColor =
          latestHr != null ? AppColors.pastelSage : AppColors.pastelAmber;
    } else if (lastTime != null) {
      subtitleText = 'Last connected ${DateFormatter.formatRelative(lastTime)}';
      subtitleColor = AppColors.textSecondary;
    } else {
      subtitleText = 'No ring data yet';
      subtitleColor = AppColors.textTertiary;
    }

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.pastelCoral.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(
            Icons.favorite_rounded,
            color: AppColors.pastelCoral,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Heart Rate',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(width: 8),
                  _ConnectionDot(state: connectionState),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitleText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: subtitleColor,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.pastelCoral.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: displayHr != null
                ? Border.all(
                    color: AppColors.pastelCoral.withValues(alpha: 0.3),
                    width: 0.5,
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayHr != null ? '$displayHr' : '--',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.pastelCoral,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 4),
              Text(
                'bpm',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.pastelCoral.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveHeartRateChart extends StatelessWidget {
  final List<VitalSample> history;
  const _LiveHeartRateChart({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) {
      return Center(
        child: Text(
          history.isEmpty
              ? 'Waiting for optical PPG lock…'
              : 'Collecting samples (${history.first.value.round()} bpm)…',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      );
    }

    final spots = List<FlSpot>.generate(history.length, (i) {
      return FlSpot(i.toDouble(), history[i].value);
    });
    final ys = history.map((e) => e.value);
    final lo = ys.reduce(min);
    final hi = ys.reduce(max);
    final minY = (lo - 10).clamp(35.0, 140.0);
    final maxY = (hi + 10).clamp(minY + 20.0, 220.0);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (value) => const FlLine(
            color: AppColors.surfaceVariant,
            strokeWidth: 0.5,
          ),
        ),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: max(1.0, (spots.length - 1).toDouble()),
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceVariant,
            tooltipRoundedRadius: 12,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toInt()} bpm',
                  const TextStyle(
                    color: AppColors.pastelCoral,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                );
              }).toList();
            },
          ),
          handleBuiltInTouches: true,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: AppColors.pastelCoral,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.pastelCoral.withValues(alpha: 0.25),
                  AppColors.pastelCoral.withValues(alpha: 0.05),
                  AppColors.pastelCoral.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveTimeAxisLabels extends StatelessWidget {
  final List<VitalSample> history;
  const _LiveTimeAxisLabels({required this.history});

  @override
  Widget build(BuildContext context) {
    final start = DateFormatter.formatClockTime(history.first.timestamp);
    final mid = DateFormatter.formatClockTime(
      history[history.length ~/ 2].timestamp,
    );
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 10,
          color: AppColors.textTertiary,
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(start, style: style),
        Text(mid, style: style),
        Text('Now', style: style),
      ],
    );
  }
}

class _OfflineHeartRateSummary extends ConsumerWidget {
  const _OfflineHeartRateSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastSummary = ref.watch(latestHrSummaryProvider).valueOrNull;
    final avgs = ref.watch(dailyHrAveragesProvider).valueOrNull;

    if (lastSummary == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'Connect your Colmi R02 ring in Settings to stream live heart rate and build your daily average.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
        ),
      );
    }

    final dailyAvg = avgs?.avgDailyHr?.round();

    return Row(
      children: [
        Expanded(
          child: _OfflineStatChip(
            label: 'Last Saved',
            value: '${lastSummary.lastHr} bpm',
            color: AppColors.pastelCoral,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _OfflineStatChip(
            label: 'Daily Avg',
            value: dailyAvg != null ? '$dailyAvg bpm' : '--',
            color: AppColors.pastelTeal,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _OfflineStatChip(
            label: 'Day Range',
            value: '${lastSummary.minHr}–${lastSummary.maxHr}',
            color: AppColors.pastelSage,
          ),
        ),
      ],
    );
  }
}

class _OfflineStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _OfflineStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  final BleConnectionState state;
  const _ConnectionDot({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, tooltip) = switch (state) {
      BleConnectionState.connected => (AppColors.pastelSage, 'Connected'),
      BleConnectionState.scanning => (AppColors.pastelAmber, 'Scanning...'),
      BleConnectionState.connecting => (AppColors.pastelAmber, 'Connecting...'),
      BleConnectionState.error => (AppColors.pastelCoral, 'Error'),
      BleConnectionState.disconnected => (AppColors.textTertiary, 'Offline'),
    };

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            if (state == BleConnectionState.connected ||
                state == BleConnectionState.scanning)
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
          ],
        ),
      ),
    );
  }
}
