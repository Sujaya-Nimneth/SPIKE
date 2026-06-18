import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/readiness_ring.dart';
import '../widgets/metric_card.dart';
import '../widgets/heart_rate_card.dart';

/// Main dashboard screen — the Readiness home page.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final ringSize = (screenWidth * 0.55).clamp(180.0, 280.0);

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          children: [
            // ── Top Bar ──────────────────────────────────────────
            _buildTopBar(context),
            const SizedBox(height: 8),

            // ── Hero: Readiness Ring ─────────────────────────────
            _buildHeroSection(context, ringSize),
            const SizedBox(height: 32),

            // ── Metric Cards Row ─────────────────────────────────
            _buildMetricsRow(context),
            const SizedBox(height: 24),

            // ── Heart Rate Card ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: const HeartRateCard(),
            ),
            const SizedBox(height: 24),

            // ── Daily Summary Card ───────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildInsightCard(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Logo / brand area
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ŌURA',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 4,
                      fontSize: 11,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'Wednesday, Jun 18',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
          const Spacer(),
          // Action icons
          _TopBarIcon(icon: Icons.share_outlined),
          const SizedBox(width: 8),
          _TopBarIcon(icon: Icons.settings_outlined),
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, double ringSize) {
    return Column(
      children: [
        // Readiness ring
        ReadinessRing(
          score: 88,
          size: ringSize,
          strokeWidth: ringSize * 0.04,
        ),
        const SizedBox(height: 24),
        // Motivational text
        Text(
          'Go get \'em',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontSize: 26,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            'A great night\'s sleep can boost your readiness. '
            'If there are any challenging tasks on your to-do list, '
            'today could be the day to tackle them!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
          ),
        ),
        const SizedBox(height: 16),
        // CTA button
        Container(
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
            'Learn more',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsRow(BuildContext context) {
    return SizedBox(
      height: 160,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: const [
          MetricCard(
            title: 'Readiness',
            score: 88,
            accentColor: AppColors.pastelTeal,
            icon: Icons.bolt_rounded,
          ),
          SizedBox(width: 12),
          MetricCard(
            title: 'Sleep',
            score: 84,
            accentColor: AppColors.pastelLavender,
            icon: Icons.nightlight_round,
          ),
          SizedBox(width: 12),
          MetricCard(
            title: 'Activity',
            score: 91,
            accentColor: AppColors.pastelAmber,
            icon: Icons.local_fire_department_rounded,
          ),
          SizedBox(width: 12),
          MetricCard(
            title: 'Cycle Day',
            score: 6,
            accentColor: AppColors.pastelCoral,
            icon: Icons.calendar_today_rounded,
          ),
        ],
      ),
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
            'Rising heart health, with a dip in stress management',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            'You\'ve done an amazing job supporting your heart health '
            'with activity. Just be mindful to carve out enough time '
            'for rest as you go.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                ),
          ),
          const SizedBox(height: 16),
          // Tags
          Wrap(
            spacing: 8,
            children: [
              _InsightTag(label: 'Heart', color: AppColors.pastelCoral),
              _InsightTag(label: 'Metabolic', color: AppColors.pastelAmber),
              _InsightTag(label: 'Recovery', color: AppColors.pastelSage),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopBarIcon extends StatelessWidget {
  final IconData icon;
  const _TopBarIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
              fontSize: 12,
            ),
      ),
    );
  }
}
