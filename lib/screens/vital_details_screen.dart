import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../providers/ble_providers.dart';
import '../providers/vitals_provider.dart';
import '../services/ble_service.dart';

enum VitalType {
  heartRate,
  hrv,
  bodyTemp,
  respiratoryRate,
  spo2,
}

class VitalDetailsScreen extends ConsumerStatefulWidget {
  final VitalType vitalType;

  const VitalDetailsScreen({
    super.key,
    required this.vitalType,
  });

  @override
  ConsumerState<VitalDetailsScreen> createState() => _VitalDetailsScreenState();
}

class _VitalDetailsScreenState extends ConsumerState<VitalDetailsScreen> with SingleTickerProviderStateMixin {
  bool _isWeekly = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch connection state
    final connectionAsync = ref.watch(bleConnectionStateProvider);
    final connectionState = connectionAsync.valueOrNull ?? BleConnectionState.disconnected;
    final isConnected = connectionState == BleConnectionState.connected;

    // Watch live vitals
    final vitals = ref.watch(liveVitalsProvider);

    // Get config for the selected vital type
    final config = _getVitalConfig(widget.vitalType, vitals);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top Bar ──────────────────────────────────────────
              _buildTopBar(context, config, connectionState),
              const SizedBox(height: 24),

              // ── Hero Vital Value ──────────────────────────────────
              _buildHeroCard(context, config, isConnected),
              const SizedBox(height: 24),

              // ── Timeframe Selector ───────────────────────────────
              _buildTimeframeSelector(),
              const SizedBox(height: 20),

              // ── Visualization Chart ──────────────────────────────
              _buildChartSection(context, config, isConnected),
              const SizedBox(height: 24),

              // ── Key Statistics Grid ──────────────────────────────
              _buildStatsGrid(context, config),
              const SizedBox(height: 24),

              // ── Educational Insight ──────────────────────────────
              _buildInsightCard(context, config),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, _VitalConfig config, BleConnectionState connectionState) {
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
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 16),
          ),
        ),
        const Spacer(),
        Text(
          config.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
        ),
        const Spacer(),
        // Pulse indicator
        _buildConnectionBadge(connectionState),
      ],
    );
  }

  Widget _buildConnectionBadge(BleConnectionState state) {
    Color badgeColor;
    String label;
    bool pulse = false;

    switch (state) {
      case BleConnectionState.connected:
        badgeColor = AppColors.pastelSage;
        label = 'Live';
        pulse = true;
        break;
      case BleConnectionState.scanning:
      case BleConnectionState.connecting:
        badgeColor = AppColors.pastelAmber;
        label = 'Syncing';
        pulse = true;
        break;
      default:
        badgeColor = AppColors.textTertiary;
        label = 'Offline';
    }

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
                    color: badgeColor.withValues(alpha: 1.0 - _pulseController.value * 0.4),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: badgeColor.withValues(alpha: 0.6 * (1.0 - _pulseController.value)),
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

  Widget _buildHeroCard(BuildContext context, _VitalConfig config, bool isConnected) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            config.color.withValues(alpha: 0.08),
            AppColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: config.color.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Row(
        children: [
          // Icon with live pulse ring
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
                        color: config.color.withValues(alpha: 0.03 * (1.0 - _pulseController.value)),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: config.color.withValues(alpha: 0.15 * (1.0 - _pulseController.value)),
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
                  color: config.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(config.icon, color: config.color, size: 28),
              ),
            ],
          ),
          const SizedBox(width: 24),
          // Value & trend
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      config.valueString,
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontSize: 48,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      config.unit,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  config.trendText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: config.color.withValues(alpha: 0.8),
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
                  'Live / Today',
                  style: TextStyle(
                    color: !_isWeekly ? AppColors.textPrimary : AppColors.textSecondary,
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
                  'Weekly Trends',
                  style: TextStyle(
                    color: _isWeekly ? AppColors.textPrimary : AppColors.textSecondary,
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

  Widget _buildChartSection(BuildContext context, _VitalConfig config, bool isConnected) {
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
            _isWeekly ? 'Weekly Averages' : (isConnected ? 'Real-Time Streaming' : 'Today\'s Activity'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _isWeekly ? _buildWeeklyChart(config) : _buildLiveChart(config, isConnected),
          ),
          if (!_isWeekly && !isConnected) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['12 AM', '6 AM', '12 PM', '6 PM', '12 AM']
                  .map(
                    (t) => Text(
                      t,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                    ),
                  )
                  .toList(),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildLiveChart(_VitalConfig config, bool isConnected) {
    final List<FlSpot> spots;
    if (isConnected) {
      if (config.liveHistory.isEmpty) {
        return const Center(child: Text('No data recorded yet'));
      }
      spots = config.liveHistory.asMap().entries.map((entry) {
        return FlSpot(entry.key.toDouble(), entry.value.value);
      }).toList();
    } else {
      spots = config.todayCurve;
    }

    // Auto-scale X and Y axes
    final yValues = spots.map((e) => e.y).toList();
    double minY = yValues.reduce(min);
    double maxY = yValues.reduce(max);
    final range = maxY - minY;
    
    // Add padded boundary spacing
    final padding = range > 0 ? range * 0.15 : 4.0;
    minY = (minY - padding).clamp(config.hardMinY, config.hardMaxY);
    maxY = (maxY + padding).clamp(config.hardMinY, config.hardMaxY);

    if (maxY - minY < 2.0) {
      minY -= 1.0;
      maxY += 1.0;
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ((maxY - minY) / 4).clamp(1.0, 50.0),
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.surfaceVariant,
            strokeWidth: 0.5,
          ),
        ),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (spots.length - 1).toDouble().clamp(1.0, 23.0),
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
                  '${spot.y.toStringAsFixed(config.decimalDigits)} ${config.unit}',
                  TextStyle(
                    color: config.color,
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
            isCurved: true,
            curveSmoothness: 0.25,
            color: config.color,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  config.color.withValues(alpha: 0.2),
                  config.color.withValues(alpha: 0.02),
                  config.color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart(_VitalConfig config) {
    final values = config.weeklyAverages;
    final barGroups = List.generate(values.length, (index) {
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: values[index],
            color: config.color,
            width: 14,
            borderRadius: BorderRadius.circular(4),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: config.hardMaxY,
              color: AppColors.surfaceVariant,
            ),
          ),
        ],
      );
    });

    final days = ['Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed'];

    return BarChart(
      BarChartData(
        barGroups: barGroups,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ((config.hardMaxY - config.hardMinY) / 4).clamp(1.0, 50.0),
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.surfaceVariant,
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                final int index = value.toInt();
                if (index < 0 || index >= days.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    days[index],
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
                '${rod.toY.toStringAsFixed(config.decimalDigits)} ${config.unit}',
                TextStyle(
                  color: config.color,
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

  Widget _buildStatsGrid(BuildContext context, _VitalConfig config) {
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
          children: config.stats.map((stat) {
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

  Widget _buildInsightCard(BuildContext context, _VitalConfig config) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            config.color.withValues(alpha: 0.05),
            AppColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: config.color.withValues(alpha: 0.12), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: config.color, size: 20),
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
            config.description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  _VitalConfig _getVitalConfig(VitalType type, LiveVitalsState vitals) {
    switch (type) {
      case VitalType.heartRate:
        return _VitalConfig(
          title: 'Heart Rate',
          valueString: '${vitals.heartRate}',
          unit: 'bpm',
          color: AppColors.pastelCoral,
          icon: Icons.favorite_rounded,
          trendText: 'Live resting pulse from ring',
          liveHistory: vitals.heartRateHistory,
          todayCurve: const [
            FlSpot(0, 62), FlSpot(1, 58), FlSpot(2, 55), FlSpot(3, 54), FlSpot(4, 56), FlSpot(5, 52),
            FlSpot(6, 58), FlSpot(7, 65), FlSpot(8, 72), FlSpot(9, 78), FlSpot(10, 82), FlSpot(11, 76),
            FlSpot(12, 80), FlSpot(13, 85), FlSpot(14, 78), FlSpot(15, 74), FlSpot(16, 70), FlSpot(17, 76),
            FlSpot(18, 82), FlSpot(19, 79), FlSpot(20, 75), FlSpot(21, 70), FlSpot(22, 65), FlSpot(23, 62),
          ],
          weeklyAverages: [71, 73, 70, 72, 74, 71, 72],
          hardMinY: 40,
          hardMaxY: 120,
          decimalDigits: 0,
          description: 'Your heart rate measures the number of times your heart beats per minute. A lower resting heart rate typically indicates better cardiovascular efficiency and physical conditioning.',
          stats: [
            _StatItem('Daily Avg', '${vitals.heartRate}', 'bpm'),
            _StatItem('Min HR', '58', 'bpm'),
            _StatItem('Max HR', '112', 'bpm'),
            _StatItem('Resting HR', '62', 'bpm'),
          ],
        );
      case VitalType.hrv:
        return _VitalConfig(
          title: 'HRV',
          valueString: '${vitals.hrv}',
          unit: 'ms',
          color: AppColors.pastelSage,
          icon: Icons.show_chart_rounded,
          trendText: 'Heart rate variability telemetry',
          liveHistory: vitals.hrvHistory,
          todayCurve: const [
            FlSpot(0, 42), FlSpot(1, 45), FlSpot(2, 48), FlSpot(3, 46), FlSpot(4, 44), FlSpot(5, 45),
            FlSpot(6, 42), FlSpot(7, 40), FlSpot(8, 43), FlSpot(9, 45), FlSpot(10, 46), FlSpot(11, 45),
            FlSpot(12, 44), FlSpot(13, 42), FlSpot(14, 45), FlSpot(15, 47), FlSpot(16, 46), FlSpot(17, 45),
            FlSpot(18, 44), FlSpot(19, 43), FlSpot(20, 45), FlSpot(21, 46), FlSpot(22, 44), FlSpot(23, 45),
          ],
          weeklyAverages: [44, 46, 43, 45, 47, 45, 46],
          hardMinY: 20,
          hardMaxY: 80,
          decimalDigits: 0,
          description: 'Heart Rate Variability (HRV) is the variation in milliseconds between consecutive heartbeats. Higher HRV is typically associated with better recovery, lower stress, and a well-rested state.',
          stats: [
            _StatItem('Avg HRV', '${vitals.hrv}', 'ms'),
            _StatItem('Max HRV', '74', 'ms'),
            _StatItem('Resting baseline', '44', 'ms'),
            _StatItem('Recovery Status', 'Optimal', ''),
          ],
        );
      case VitalType.bodyTemp:
        return _VitalConfig(
          title: 'Body Temperature',
          valueString: '${vitals.bodyTempDeviation >= 0 ? '+' : ''}${vitals.bodyTempDeviation.toStringAsFixed(2)}',
          unit: '°C',
          color: AppColors.pastelAmber,
          icon: Icons.thermostat_rounded,
          trendText: 'Deviation from baseline threshold',
          liveHistory: vitals.bodyTempHistory,
          todayCurve: const [
            FlSpot(0, 0.15), FlSpot(1, 0.18), FlSpot(2, 0.22), FlSpot(3, 0.25), FlSpot(4, 0.20), FlSpot(5, 0.15),
            FlSpot(6, 0.10), FlSpot(7, 0.12), FlSpot(8, 0.18), FlSpot(9, 0.25), FlSpot(10, 0.28), FlSpot(11, 0.24),
            FlSpot(12, 0.20), FlSpot(13, 0.18), FlSpot(14, 0.22), FlSpot(15, 0.25), FlSpot(16, 0.24), FlSpot(17, 0.20),
            FlSpot(18, 0.18), FlSpot(19, 0.15), FlSpot(20, 0.16), FlSpot(21, 0.20), FlSpot(22, 0.18), FlSpot(23, 0.20),
          ],
          weeklyAverages: [0.1, 0.2, 0.15, 0.3, 0.2, 0.18, 0.22],
          hardMinY: -1.0,
          hardMaxY: 1.0,
          decimalDigits: 2,
          description: 'Body temperature deviation tracks fluctuations relative to your baseline sleeping temperature. Slight deviations can indicate recovery cycles, training fatigue, or changes in sleep environment.',
          stats: [
            _StatItem('Sleep Deviation', '${vitals.bodyTempDeviation >= 0 ? '+' : ''}${vitals.bodyTempDeviation.toStringAsFixed(2)}', '°C'),
            _StatItem('Baseline Temp', '36.5', '°C'),
            _StatItem('Max Deviation', '+0.32', '°C'),
            _StatItem('Temperature Status', 'Normal', ''),
          ],
        );
      case VitalType.respiratoryRate:
        return _VitalConfig(
          title: 'Respiratory Rate',
          valueString: vitals.respiratoryRate.toStringAsFixed(1),
          unit: 'Br/Min',
          color: AppColors.pastelBlue,
          icon: Icons.air_rounded,
          trendText: 'Breaths per minute sleeping avg',
          liveHistory: vitals.respiratoryRateHistory,
          todayCurve: const [
            FlSpot(0, 15.0), FlSpot(1, 15.2), FlSpot(2, 15.4), FlSpot(3, 15.1), FlSpot(4, 14.9), FlSpot(5, 15.0),
            FlSpot(6, 15.2), FlSpot(7, 15.5), FlSpot(8, 15.3), FlSpot(9, 15.1), FlSpot(10, 15.0), FlSpot(11, 15.2),
            FlSpot(12, 15.4), FlSpot(13, 15.3), FlSpot(14, 15.1), FlSpot(15, 14.8), FlSpot(16, 15.0), FlSpot(17, 15.2),
            FlSpot(18, 15.4), FlSpot(19, 15.2), FlSpot(20, 15.1), FlSpot(21, 15.3), FlSpot(22, 15.1), FlSpot(23, 15.2),
          ],
          weeklyAverages: [15.1, 15.3, 15.0, 15.2, 15.4, 15.1, 15.2],
          hardMinY: 10,
          hardMaxY: 20,
          decimalDigits: 1,
          description: 'Respiratory rate tracks your breaths per minute during periods of rest and sleep. It is typically very stable; increases can point to physical exertion, environmental allergens, or initial signs of illness.',
          stats: [
            _StatItem('Avg Respiration', vitals.respiratoryRate.toStringAsFixed(1), 'Br/Min'),
            _StatItem('Sleep Min', '13.8', 'Br/Min'),
            _StatItem('Sleep Max', '17.2', 'Br/Min'),
            _StatItem('Stability Index', 'High', ''),
          ],
        );
      case VitalType.spo2:
        return _VitalConfig(
          title: 'SpO2',
          valueString: '${vitals.spo2}',
          unit: '%',
          color: AppColors.pastelLavender,
          icon: Icons.water_drop_rounded,
          trendText: 'Blood oxygen saturation range',
          liveHistory: vitals.spo2History,
          todayCurve: const [
            FlSpot(0, 97), FlSpot(1, 97), FlSpot(2, 96), FlSpot(3, 97), FlSpot(4, 98), FlSpot(5, 97),
            FlSpot(6, 97), FlSpot(7, 96), FlSpot(8, 97), FlSpot(9, 97), FlSpot(10, 98), FlSpot(11, 97),
            FlSpot(12, 97), FlSpot(13, 96), FlSpot(14, 97), FlSpot(15, 97), FlSpot(16, 98), FlSpot(17, 97),
            FlSpot(18, 97), FlSpot(19, 97), FlSpot(20, 96), FlSpot(21, 97), FlSpot(22, 98), FlSpot(23, 97),
          ],
          weeklyAverages: [97, 97, 96.8, 97.4, 97.1, 97.2, 97.3],
          hardMinY: 90,
          hardMaxY: 100,
          decimalDigits: 0,
          description: 'SpO2 represents the percentage of oxygen-saturated hemoglobin in your blood. Readings between 95% and 100% are indicative of healthy arterial blood oxygenation levels.',
          stats: [
            _StatItem('Oxygen Level', '${vitals.spo2}', '%'),
            _StatItem('Sleep Low SpO2', '94', '%'),
            _StatItem('Sleep Avg SpO2', '97.2', '%'),
            _StatItem('Status', 'Healthy', ''),
          ],
        );
    }
  }
}

class _StatItem {
  final String label;
  final String value;
  final String unit;
  _StatItem(this.label, this.value, this.unit);
}

class _VitalConfig {
  final String title;
  final String valueString;
  final String unit;
  final Color color;
  final IconData icon;
  final String trendText;
  final List<VitalSample> liveHistory;
  final List<FlSpot> todayCurve;
  final List<double> weeklyAverages;
  final double hardMinY;
  final double hardMaxY;
  final int decimalDigits;
  final String description;
  final List<_StatItem> stats;

  _VitalConfig({
    required this.title,
    required this.valueString,
    required this.unit,
    required this.color,
    required this.icon,
    required this.trendText,
    required this.liveHistory,
    required this.todayCurve,
    required this.weeklyAverages,
    required this.hardMinY,
    required this.hardMaxY,
    required this.decimalDigits,
    required this.description,
    required this.stats,
  });
}
