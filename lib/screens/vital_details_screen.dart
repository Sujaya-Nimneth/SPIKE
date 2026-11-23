import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_hr_summary.dart';
import '../providers/ble_providers.dart';
import '../providers/health_sync_providers.dart';
import '../providers/stress_providers.dart';
import '../providers/vitals_provider.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_formatter.dart';

enum VitalType {
  heartRate,
}

/// Detailed heart rate view showing live streaming (when connected), last-saved
/// value + last-connected time + 7-day daily averages (when offline), and real
/// persisted weekly trend bars.
class VitalDetailsScreen extends ConsumerStatefulWidget {
  final VitalType vitalType;

  const VitalDetailsScreen({
    super.key,
    this.vitalType = VitalType.heartRate,
  });

  @override
  ConsumerState<VitalDetailsScreen> createState() => _VitalDetailsScreenState();
}

class _VitalDetailsScreenState extends ConsumerState<VitalDetailsScreen>
    with SingleTickerProviderStateMixin {
  bool _isWeekly = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    final initialConn = ref.read(bleConnectionStateProvider).valueOrNull;
    if (initialConn != null) {
      _syncPulseAnimation(initialConn);
    }
  }

  void _syncPulseAnimation(BleConnectionState state) {
    final shouldPulse = state == BleConnectionState.connected ||
        state == BleConnectionState.scanning ||
        state == BleConnectionState.connecting;
    if (shouldPulse && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!shouldPulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<BleConnectionState>>(
      bleConnectionStateProvider,
      (_, next) {
        final state = next.valueOrNull;
        if (state != null) {
          _syncPulseAnimation(state);
        }
      },
    );

    final connectionState =
        ref.watch(bleConnectionStateProvider).valueOrNull ??
            BleConnectionState.disconnected;
    final isConnected = connectionState == BleConnectionState.connected;

    final vitals = ref.watch(liveVitalsProvider);
    final baselineHr = ref.watch(baselineHrProvider).valueOrNull;
    final lastSummary = ref.watch(latestHrSummaryProvider).valueOrNull;
    final recentSummaries =
        ref.watch(recentHrSummariesProvider).valueOrNull ?? const [];
    final dailyAvgs = ref.watch(dailyHrAveragesProvider).valueOrNull;
    final syncStatus = ref.watch(deviceSyncStatusProvider).valueOrNull;

    final int? displayHr = isConnected ? vitals.heartRate : lastSummary?.lastHr;
    final lastTime = syncStatus?.lastConnectedAt ?? lastSummary?.updatedAt;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(context, connectionState),
              const SizedBox(height: 24),
              _buildHeroCard(
                context,
                displayHr: displayHr,
                isConnected: isConnected,
                lastConnectedAt: lastTime,
              ),
              const SizedBox(height: 24),
              _buildTimeframeSelector(),
              const SizedBox(height: 20),
              RepaintBoundary(
                child: _buildChartSection(
                  context,
                  isConnected: isConnected,
                  liveHistory: vitals.heartRateHistory,
                  recentSummaries: recentSummaries,
                ),
              ),
              const SizedBox(height: 24),
              _buildStatsGrid(
                context,
                isConnected: isConnected,
                vitals: vitals,
                baselineHr: baselineHr?.round(),
                lastSummary: lastSummary,
                dailyAvgHr: dailyAvgs?.avgDailyHr?.round(),
              ),
              const SizedBox(height: 24),
              _buildInsightCard(context),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, BleConnectionState connectionState) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder, width: 0.5),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary,
              size: 16,
            ),
          ),
        ),
        const Spacer(),
        Text(
          'Heart Rate',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
        ),
        const Spacer(),
        _buildConnectionBadge(connectionState),
      ],
    );
  }

  Widget _buildConnectionBadge(BleConnectionState state) {
    final (badgeColor, label, pulse) = switch (state) {
      BleConnectionState.connected => (AppColors.pastelSage, 'Live', true),
      BleConnectionState.scanning ||
      BleConnectionState.connecting =>
        (AppColors.pastelAmber, 'Syncing', true),
      _ => (AppColors.textTertiary, 'Offline', false),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulse)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(
                      alpha: 1.0 - _pulseController.value * 0.4,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: badgeColor.withValues(
                          alpha: 0.6 * (1.0 - _pulseController.value),
                        ),
                        blurRadius: 4 + _pulseController.value * 6,
                        spreadRadius: _pulseController.value * 2,
                      ),
                    ],
                  ),
                );
              },
            )
          else
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context, {
    required int? displayHr,
    required bool isConnected,
    required DateTime? lastConnectedAt,
  }) {
    final trendText = isConnected
        ? 'Live optical pulse from R02 ring'
        : (lastConnectedAt != null
            ? 'Last connected ${DateFormatter.formatShortDateTime(lastConnectedAt)}'
            : 'Connect ring to record live heart rate');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.pastelCoral.withValues(alpha: 0.08),
            AppColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.pastelCoral.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (isConnected)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 72 + _pulseController.value * 24,
                      height: 72 + _pulseController.value * 24,
                      decoration: BoxDecoration(
                        color: AppColors.pastelCoral.withValues(
                          alpha: 0.03 * (1.0 - _pulseController.value),
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.pastelCoral.withValues(
                            alpha: 0.15 * (1.0 - _pulseController.value),
                          ),
                          width: 1,
                        ),
                      ),
                    );
                  },
                ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.pastelCoral.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: AppColors.pastelCoral,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      displayHr != null ? '$displayHr' : '--',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontSize: 48,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'bpm',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  trendText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.pastelCoral.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeframeSelector() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isWeekly = false),
              child: Container(
                decoration: BoxDecoration(
                  color: !_isWeekly ? AppColors.surfaceVariant : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Live Session',
                  style: TextStyle(
                    color: !_isWeekly
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: !_isWeekly ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isWeekly = true),
              child: Container(
                decoration: BoxDecoration(
                  color: _isWeekly ? AppColors.surfaceVariant : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Daily Averages',
                  style: TextStyle(
                    color: _isWeekly
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: _isWeekly ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection(
    BuildContext context, {
    required bool isConnected,
    required List<VitalSample> liveHistory,
    required List<DailyHrSummary> recentSummaries,
  }) {
    return Container(
      height: 250,
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
            _isWeekly
                ? '7-Day Daily Average BPM'
                : (isConnected ? 'Real-Time Streaming' : 'Live Stream Offline'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isWeekly
                ? _buildWeeklyChart(context, recentSummaries)
                : _buildLiveChart(context, liveHistory, isConnected),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveChart(
    BuildContext context,
    List<VitalSample> liveHistory,
    bool isConnected,
  ) {
    if (!isConnected) {
      return Center(
        child: Text(
          'Ring is offline. Connect your R02 ring to stream live BPM, or switch to Daily Averages to view saved history.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
        ),
      );
    }

    if (liveHistory.isEmpty) {
      return Center(
        child: Text(
          'Waiting for first heart rate reading…',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      );
    }

    final spots = liveHistory.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.value);
    }).toList();

    final yValues = spots.map((e) => e.y).toList();
    double minY = yValues.reduce(min);
    double maxY = yValues.reduce(max);
    final range = maxY - minY;
    final padding = range > 0 ? range * 0.15 : 6.0;
    minY = (minY - padding).clamp(35.0, 200.0);
    maxY = (maxY + padding).clamp(minY + 4.0, 220.0);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ((maxY - minY) / 4).clamp(2.0, 50.0),
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
            tooltipRoundedRadius: 10,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.round()} bpm',
                  const TextStyle(
                    color: AppColors.pastelCoral,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: spots.length > 2,
            curveSmoothness: 0.25,
            color: AppColors.pastelCoral,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: spots.length == 1),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.pastelCoral.withValues(alpha: 0.2),
                  AppColors.pastelCoral.withValues(alpha: 0.02),
                  AppColors.pastelCoral.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart(
    BuildContext context,
    List<DailyHrSummary> recentSummaries,
  ) {
    if (recentSummaries.isEmpty) {
      return Center(
        child: Text(
          'No daily heart rate averages recorded yet.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      );
    }

    final chronological = recentSummaries.reversed.toList();
    final barGroups = List.generate(chronological.length, (index) {
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: chronological[index].avgHr,
            color: AppColors.pastelCoral,
            width: 16,
            borderRadius: BorderRadius.circular(4),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: 140,
              color: AppColors.surfaceVariant,
            ),
          ),
        ],
      );
    });

    return BarChart(
      BarChartData(
        minY: 40,
        maxY: 140,
        barGroups: barGroups,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (value) => const FlLine(
            color: AppColors.surfaceVariant,
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                final index = value.toInt();
                if (index < 0 || index >= chronological.length) {
                  return const SizedBox();
                }
                final dateStr = chronological[index].date;
                final shortLabel =
                    dateStr.length >= 10 ? dateStr.substring(5) : dateStr;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    shortLabel,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceVariant,
            tooltipRoundedRadius: 10,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.round()} bpm avg',
                const TextStyle(
                  color: AppColors.pastelCoral,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(
    BuildContext context, {
    required bool isConnected,
    required LiveVitalsState vitals,
    required int? baselineHr,
    required DailyHrSummary? lastSummary,
    required int? dailyAvgHr,
  }) {
    final avgVal = isConnected
        ? (vitals.avgHeartRate ?? dailyAvgHr)
        : dailyAvgHr;
    final minVal = isConnected ? vitals.minHeartRate : lastSummary?.minHr;
    final maxVal = isConnected ? vitals.maxHeartRate : lastSummary?.maxHr;
    final baseVal = baselineHr ?? lastSummary?.restingHr;

    final stats = [
      _StatItem(
        isConnected ? 'Session Avg' : '7d Daily Avg',
        avgVal != null ? '$avgVal' : '--',
        'bpm',
      ),
      _StatItem('Min HR', minVal != null ? '$minVal' : '--', 'bpm'),
      _StatItem('Max HR', maxVal != null ? '$maxVal' : '--', 'bpm'),
      _StatItem('Baseline HR', baseVal != null ? '$baseVal' : '--', 'bpm'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: stats.map((stat) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    stat.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        stat.value,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        stat.unit,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildInsightCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.pastelCoral.withValues(alpha: 0.05),
            AppColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.pastelCoral.withValues(alpha: 0.12),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.pastelCoral,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                'Clinical Context',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Your heart rate baseline is computed using a spike-frozen 10-minute rolling median and MAD. Sustained rises above 1.25× baseline or z ≥ 2.5 for 2+ minutes are logged as stress episodes.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatItem {
  final String label;
  final String value;
  final String unit;
  const _StatItem(this.label, this.value, this.unit);
}
