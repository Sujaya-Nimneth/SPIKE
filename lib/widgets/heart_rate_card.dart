import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ble_providers.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';

/// A dark-themed heart rate chart card using fl_chart.
///
/// Displays a gradient-filled area chart with pastel coral styling.
/// The BPM badge shows live data from the connected ring via Riverpod.
class HeartRateCard extends ConsumerWidget {
  const HeartRateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the latest heart rate value from the ring
    final latestHr = ref.watch(latestHeartRateProvider);

    // Watch connection state for the status indicator
    final connectionAsync = ref.watch(bleConnectionStateProvider);
    final connectionState = connectionAsync.valueOrNull ??
        BleConnectionState.disconnected;

    // Display value: live HR if available, otherwise fallback to static
    final displayHr = latestHr ?? 72;

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
          // Header row
          Row(
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
                        // Connection status dot
                        _ConnectionDot(state: connectionState),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      latestHr != null ? 'Live from R02' : 'Last 24 hours',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: latestHr != null
                                ? AppColors.pastelSage
                                : AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              // BPM badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.pastelCoral.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: latestHr != null
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
                      '$displayHr',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
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
          ),
          const SizedBox(height: 24),
          // Chart
          SizedBox(
            height: 160,
            child: _buildChart(),
          ),
          const SizedBox(height: 12),
          // Time labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['12 AM', '6 AM', '12 PM', '6 PM', 'Now']
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
        ],
      ),
    );
  }

  Widget _buildChart() {
    // Static heart-rate-like data points (chart data stays static for now)
    final spots = <FlSpot>[
      const FlSpot(0, 62),
      const FlSpot(1, 58),
      const FlSpot(2, 55),
      const FlSpot(3, 54),
      const FlSpot(4, 56),
      const FlSpot(5, 52),
      const FlSpot(6, 58),
      const FlSpot(7, 65),
      const FlSpot(8, 72),
      const FlSpot(9, 78),
      const FlSpot(10, 82),
      const FlSpot(11, 76),
      const FlSpot(12, 80),
      const FlSpot(13, 85),
      const FlSpot(14, 78),
      const FlSpot(15, 74),
      const FlSpot(16, 70),
      const FlSpot(17, 76),
      const FlSpot(18, 82),
      const FlSpot(19, 79),
      const FlSpot(20, 75),
      const FlSpot(21, 70),
      const FlSpot(22, 65),
      const FlSpot(23, 62),
    ];

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.surfaceVariant,
            strokeWidth: 0.5,
          ),
        ),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: 23,
        minY: 40,
        maxY: 100,
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
          getTouchedSpotIndicator: (barData, spotIndexes) {
            return spotIndexes.map((index) {
              return TouchedSpotIndicatorData(
                FlLine(
                  color: AppColors.pastelCoral.withValues(alpha: 0.3),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
                FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 5,
                      color: AppColors.pastelCoral,
                      strokeWidth: 2,
                      strokeColor: AppColors.background,
                    );
                  },
                ),
              );
            }).toList();
          },
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

/// A small colored dot indicating the BLE connection status.
class _ConnectionDot extends StatelessWidget {
  final BleConnectionState state;
  const _ConnectionDot({required this.state});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String tooltip;

    switch (state) {
      case BleConnectionState.connected:
        color = AppColors.pastelSage;
        tooltip = 'Connected';
      case BleConnectionState.scanning:
        color = AppColors.pastelAmber;
        tooltip = 'Scanning...';
      case BleConnectionState.connecting:
        color = AppColors.pastelAmber;
        tooltip = 'Connecting...';
      case BleConnectionState.error:
        color = AppColors.pastelCoral;
        tooltip = 'Error';
      case BleConnectionState.disconnected:
        color = AppColors.textTertiary;
        tooltip = 'Disconnected';
    }

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
