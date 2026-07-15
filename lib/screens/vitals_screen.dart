import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../providers/ble_providers.dart';
import '../providers/vitals_provider.dart';
import '../services/ble_service.dart';
import 'vital_details_screen.dart';

/// Vitals screen displaying real-time smart ring telemetry.
class VitalsScreen extends ConsumerWidget {
  const VitalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch connection state to show a "Live" status dot
    final connectionAsync = ref.watch(bleConnectionStateProvider);
    final connectionState = connectionAsync.valueOrNull ?? BleConnectionState.disconnected;
    final isConnected = connectionState == BleConnectionState.connected;

    // Watch live vitals values
    final vitals = ref.watch(liveVitalsProvider);

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Header with optional connection status text
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
                  if (isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.pastelSage.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.pastelSage.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.pastelSage,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'LIVE',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.pastelSage,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 9,
                                  letterSpacing: 0.5,
                                ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Vital cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.favorite_rounded,
                title: 'Heart Rate',
                value: '${vitals.heartRate} bpm',
                subtitle: 'Resting average',
                color: AppColors.pastelCoral,
                trend: isConnected ? 'Live from ring' : '↓ 3 from yesterday',
                onTap: () => _navigateToDetails(context, VitalType.heartRate),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.show_chart_rounded,
                title: 'HRV',
                value: '${vitals.hrv} ms',
                subtitle: 'Heart rate variability',
                color: AppColors.pastelSage,
                trend: isConnected ? 'Pulsing live telemetry' : '↑ 5 from yesterday',
                onTap: () => _navigateToDetails(context, VitalType.hrv),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.thermostat_rounded,
                title: 'Body Temperature',
                value: '${vitals.bodyTempDeviation >= 0 ? '+' : ''}${vitals.bodyTempDeviation.toStringAsFixed(2)}°',
                subtitle: 'Deviation from baseline',
                color: AppColors.pastelAmber,
                trend: isConnected ? 'Live temperature shift' : 'Within normal range',
                onTap: () => _navigateToDetails(context, VitalType.bodyTemp),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.air_rounded,
                title: 'Respiratory Rate',
                value: vitals.respiratoryRate.toStringAsFixed(1),
                subtitle: 'Breaths per minute',
                color: AppColors.pastelBlue,
                trend: isConnected ? 'Live respiration monitoring' : 'Stable',
                onTap: () => _navigateToDetails(context, VitalType.respiratoryRate),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _VitalTile(
                icon: Icons.water_drop_rounded,
                title: 'SpO2',
                value: '${vitals.spo2}%',
                subtitle: 'Blood oxygen average',
                color: AppColors.pastelLavender,
                trend: isConnected ? 'Active blood oxygen logging' : 'Healthy range',
                onTap: () => _navigateToDetails(context, VitalType.spo2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDetails(BuildContext context, VitalType type) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => VitalDetailsScreen(vitalType: type),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
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
            // Icon
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
            // Text
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
            // Chevron
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
