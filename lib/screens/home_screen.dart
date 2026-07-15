import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/readiness_ring.dart';
import '../widgets/metric_card.dart';
import '../widgets/heart_rate_card.dart';
import 'settings_screen.dart';
import 'vitals_screen.dart';
import 'sleep_screen.dart';
import 'activity_screen.dart';

/// Main dashboard screen — the Calm Score home page.
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

            // ── Hero: Calm Ring ──────────────────────────────────
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
                'SPIKE',
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
          _TopBarIcon(icon: Icons.share_outlined, tooltip: 'Share'),
          const SizedBox(width: 8),
          _TopBarIcon(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: () {
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const SettingsScreen(),
                  transitionDuration: const Duration(milliseconds: 300),
                  reverseTransitionDuration: const Duration(milliseconds: 250),
                  transitionsBuilder: (_, animation, __, child) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(1.0, 0.0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      )),
                      child: child,
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, double ringSize) {
    return Column(
      children: [
        // Calm ring
        CalmRing(
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
            'A great night\'s sleep can boost your calm score. '
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
        GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Feature coming soon'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.surfaceLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
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
              'Learn more',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ),
      ],
    );
  }

  void _pushFullScreen(BuildContext context, Widget screen, String title) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(title),
            centerTitle: true,
          ),
          body: screen,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildMetricsRow(BuildContext context) {
    return SizedBox(
      height: 160,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          MetricCard(
            title: 'Calm',
            score: 88,
            accentColor: AppColors.pastelTeal,
            icon: Icons.bolt_rounded,
            onTap: () {
              _pushFullScreen(
                context,
                const VitalsScreen(),
                'Vitals',
              );
            },
          ),
          const SizedBox(width: 12),
          MetricCard(
            title: 'Sleep',
            score: 84,
            accentColor: AppColors.pastelLavender,
            icon: Icons.nightlight_round,
            onTap: () {
              _pushFullScreen(
                context,
                const SleepScreen(),
                'Sleep',
              );
            },
          ),
          const SizedBox(width: 12),
          MetricCard(
            title: 'Activity',
            score: 91,
            accentColor: AppColors.pastelAmber,
            icon: Icons.local_fire_department_rounded,
            onTap: () {
              _pushFullScreen(
                context,
                const ActivityScreen(),
                'Activity',
              );
            },
          ),
          const SizedBox(width: 12),
          MetricCard(
            title: 'Cycle Day',
            score: 6,
            accentColor: AppColors.pastelCoral,
            icon: Icons.calendar_today_rounded,
            onTap: () {
              _pushFullScreen(
                context,
                const _CycleDayPlaceholder(),
                'Cycle Tracking',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Feature coming soon'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surfaceLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
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
      ),
    );
  }
}

class _TopBarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _TopBarIcon({required this.icon, this.tooltip = '', this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Feature coming soon'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.surfaceLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
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

class _CycleDayPlaceholder extends StatelessWidget {
  const _CycleDayPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cardBorder, width: 0.5),
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
                        color: AppColors.pastelCoral.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.calendar_today_rounded, color: AppColors.pastelCoral, size: 22),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cycle Track',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Day 6',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Follicular Phase',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.pastelCoral,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your body temperature and resting heart rate are within optimal baseline ranges, indicating strong recovery status.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
