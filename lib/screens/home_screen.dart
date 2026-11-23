import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/readiness_snapshot.dart';
import '../providers/ble_providers.dart';
import '../providers/health_sync_providers.dart';
import '../providers/stress_providers.dart';
import '../services/ble_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_routes.dart';
import '../utils/date_formatter.dart';
import '../widgets/heart_rate_card.dart';
import '../widgets/metric_card.dart';
import '../widgets/readiness_ring.dart';
import 'settings_screen.dart';

/// Main dashboard screen — the WHOOP-style Ready Score & daily overview.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenWidth = MediaQuery.of(context).size.width;
    final ringSize = (screenWidth * 0.55).clamp(180.0, 280.0);

    final readiness = ref.watch(readinessProvider);
    final connState = ref.watch(bleConnectionStateProvider).valueOrNull ??
        BleConnectionState.disconnected;
    final baselineHr = ref.watch(baselineHrProvider).valueOrNull;
    final liveCalm = ref.watch(calmScoreProvider).valueOrNull;
    final latestSleep = ref.watch(latestSleepProvider).valueOrNull;
    final latestActivity = ref.watch(latestActivityProvider).valueOrNull;
    final todaySpikes = ref.watch(todayStressCountProvider).valueOrNull ?? 0;

    final int? displayCalm =
        (connState == BleConnectionState.connected && baselineHr != null)
            ? liveCalm
            : null;

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          children: [
            _buildTopBar(context, ref, connState),
            const SizedBox(height: 8),

            // ── Hero: WHOOP-style Ready Score Ring ───────────────
            _buildHeroSection(
              context,
              ref,
              ringSize: ringSize,
              readiness: readiness,
              connState: connState,
            ),
            const SizedBox(height: 28),

            // ── Metric Cards Row (switches MainShell tabs) ──────
            _buildMetricsRow(
              context,
              ref,
              calmScore: displayCalm,
              sleepScore: latestSleep?.sleepScore,
              activityPercent: latestActivity?.goalPercent,
              todaySpikes: todaySpikes,
            ),
            const SizedBox(height: 24),

            // ── Heart Rate Card ──────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: HeartRateCard(),
            ),
            const SizedBox(height: 24),

            // ── Daily Insight Card ───────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildInsightCard(
                context,
                ref,
                readiness: readiness,
                baselineHr: baselineHr?.round(),
                todaySpikes: todaySpikes,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    WidgetRef ref,
    BleConnectionState connState,
  ) {
    final todayText = DateFormatter.formatHeaderDate(DateTime.now());
    final isConnected = connState == BleConnectionState.connected;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SPIKE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 4,
                      fontSize: 11,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                todayText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
          const Spacer(),
          if (isConnected) ...[
            _TopBarIcon(
              icon: Icons.sync_rounded,
              tooltip: 'Sync ring telemetry',
              onTap: () {
                unawaited(ref.read(bleServiceProvider).syncAllTelemetry());
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Syncing ring activity & sleep…'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.surfaceLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
          _TopBarIcon(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: () {
              Navigator.of(context).push(
                AppRoutes.slide(const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(
    BuildContext context,
    WidgetRef ref, {
    required double ringSize,
    required ReadinessSnapshot readiness,
    required BleConnectionState connState,
  }) {
    final (primaryColor, secondaryColor) = switch (readiness.zone) {
      ReadinessZone.peak => (AppColors.pastelSage, AppColors.pastelTeal),
      ReadinessZone.adequate => (AppColors.pastelAmber, AppColors.pastelTeal),
      ReadinessZone.rest => (AppColors.pastelCoral, AppColors.pastelAmber),
      ReadinessZone.uncalibrated => (
          AppColors.textTertiary,
          AppColors.surfaceLight,
        ),
    };

    return Column(
      children: [
        RepaintBoundary(
          child: CalmRing(
            score: readiness.score,
            size: ringSize,
            strokeWidth: ringSize * 0.04,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            label: 'READY',
            unitSuffix: readiness.score != null ? '%' : null,
          ),
        ),
        const SizedBox(height: 16),

        // Zone & sync status pill
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Text(
                readiness.zone.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: primaryColor,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
              ),
            ),
            if (connState == BleConnectionState.connected)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.pastelSage.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.pastelSage.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  'LIVE RING',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.pastelSage,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                ),
              )
            else if (readiness.lastSyncedAt != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder, width: 0.5),
                ),
                child: Text(
                  'Last synced ${DateFormatter.formatRelative(readiness.lastSyncedAt!)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),

        Text(
          readiness.headline,
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            readiness.guidance,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
          ),
        ),
        const SizedBox(height: 18),

        // Factor breakdown row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: readiness.factors.map((factor) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _FactorTile(
                    factor: factor,
                    accentColor: primaryColor,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // CTA button -> switch to Vitals tab
        Semantics(
          button: true,
          label: 'View Vitals',
          child: GestureDetector(
            onTap: () {
              ref.read(selectedTabProvider.notifier).state = 1;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.cardBorder,
                  width: 0.5,
                ),
              ),
              child: Text(
                'View Vitals',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsRow(
    BuildContext context,
    WidgetRef ref, {
    required int? calmScore,
    required int? sleepScore,
    required int? activityPercent,
    required int todaySpikes,
  }) {
    return SizedBox(
      height: 160,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          MetricCard(
            title: 'Calm',
            score: calmScore,
            accentColor: AppColors.pastelTeal,
            icon: Icons.favorite_rounded,
            onTap: () {
              ref.read(selectedTabProvider.notifier).state = 1;
            },
          ),
          const SizedBox(width: 12),
          MetricCard(
            title: 'Sleep',
            score: sleepScore,
            accentColor: AppColors.pastelLavender,
            icon: Icons.nightlight_round,
            onTap: () {
              ref.read(selectedTabProvider.notifier).state = 2;
            },
          ),
          const SizedBox(width: 12),
          MetricCard(
            title: 'Activity',
            score: activityPercent,
            accentColor: AppColors.pastelAmber,
            icon: Icons.local_fire_department_rounded,
            onTap: () {
              ref.read(selectedTabProvider.notifier).state = 3;
            },
          ),
          const SizedBox(width: 12),
          MetricCard(
            title: 'Spikes',
            score: todaySpikes,
            statusOverride: todaySpikes == 0
                ? 'CALM DAY'
                : todaySpikes == 1
                    ? '1 SPIKE'
                    : '$todaySpikes SPIKES',
            accentColor: AppColors.pastelCoral,
            icon: Icons.whatshot_rounded,
            onTap: () {
              ref.read(selectedTabProvider.notifier).state = 4;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard(
    BuildContext context,
    WidgetRef ref, {
    required ReadinessSnapshot readiness,
    required int? baselineHr,
    required int todaySpikes,
  }) {
    final String insightTitle;
    final String insightBody;

    if (readiness.score == null) {
      insightTitle = 'Connect your Colmi R02 to start tracking';
      insightBody =
          'Once connected, Spike monitors your resting baseline, detects meeting stress spikes, and syncs sleep & daily activity.';
    } else if (todaySpikes > 0) {
      insightTitle =
          '$todaySpikes ${todaySpikes == 1 ? 'stress spike' : 'stress spikes'} logged today';
      insightBody =
          'Tag the meeting or coworkers on the Stress tab to track who drives your highest heart rate elevations.';
    } else if (readiness.zone == ReadinessZone.peak) {
      insightTitle = 'Strong recovery and steady cardiovascular baseline';
      insightBody = baselineHr != null
          ? 'Your resting baseline is holding around $baselineHr bpm with zero confirmed stress episodes today.'
          : 'Your synced recovery metrics look strong today. Keep pacing hydration and breaks between meetings.';
    } else {
      insightTitle = 'Recovery signals suggest lighter pacing';
      insightBody =
          'Consider shorter focus blocks and mindful recovery between back-to-back calls to bring your readiness back into the green zone.';
    }

    return GestureDetector(
      onTap: () {
        ref.read(selectedTabProvider.notifier).state =
            todaySpikes > 0 ? 4 : 1;
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.pastelTeal.withValues(alpha: 0.08),
              AppColors.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.pastelTeal.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.pastelSage.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: AppColors.pastelSage,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Daily Insight',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              insightTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              insightBody,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (baselineHr != null)
                  _InsightTag(
                    label: 'Baseline $baselineHr bpm',
                    color: AppColors.pastelCoral,
                  ),
                _InsightTag(
                  label: readiness.zone.label,
                  color: AppColors.pastelSage,
                ),
                if (readiness.dailyAvgReadyScore != null)
                  _InsightTag(
                    label:
                        '7d Avg ${readiness.dailyAvgReadyScore!.round()}%',
                    color: AppColors.pastelLavender,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FactorTile extends StatelessWidget {
  final ReadinessFactor factor;
  final Color accentColor;

  const _FactorTile({required this.factor, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: factor.isAvailable
              ? accentColor.withValues(alpha: 0.2)
              : AppColors.cardBorder,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            factor.label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: AppColors.textTertiary,
                  letterSpacing: 1.0,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            factor.displayValue,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: factor.isAvailable
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            factor.detail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TopBarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _TopBarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.cardBorder,
                width: 0.5,
              ),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 20),
          ),
        ),
      ),
    );
  }
}

class _InsightTag extends StatelessWidget {
  final String label;
  final Color color;
  const _InsightTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
      ),
    );
  }
}
