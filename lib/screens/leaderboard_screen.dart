import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/leaderboard_entry.dart';
import '../providers/stress_providers.dart';
import '../theme/app_colors.dart';

/// A leaderboard screen ranking coworkers by how many HR stress spikes
/// they are associated with during meetings.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboardAsync = ref.watch(leaderboardProvider);
    final eventCountAsync = ref.watch(stressEventCountProvider);

    return SafeArea(
      bottom: false,
      child: leaderboardAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.pastelCoral),
        ),
        error: (_, __) => _buildErrorState(context),
        data: (entries) {
          if (entries.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildLeaderboard(context, entries, eventCountAsync);
        },
      ),
    );
  }

  // ── Leaderboard Content ─────────────────────────────────────

  Widget _buildLeaderboard(
    BuildContext context,
    List<LeaderboardEntry> entries,
    AsyncValue<int> eventCountAsync,
  ) {
    final totalEvents = eventCountAsync.valueOrNull ?? 0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Stress',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Leaderboard',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w300,
                        color: AppColors.pastelCoral,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '$totalEvents stress events recorded',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 24),

          // Podium (top 3)
          if (entries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _PodiumSection(
                entries: entries.take(3).toList(),
              ),
            ),
          const SizedBox(height: 24),

          // Full ranked list
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'ALL COWORKERS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 2,
                    color: AppColors.textTertiary,
                  ),
            ),
          ),
          const SizedBox(height: 12),

          ...List.generate(entries.length, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _RankedCard(
                rank: index + 1,
                entry: entries[index],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Empty State ─────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.pastelSage.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.sentiment_satisfied_alt_rounded,
                color: AppColors.pastelSage,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No stress events yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'When your heart rate spikes 25% above your baseline '
              'for 2+ minutes during a meeting, the culprits will '
              'show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    color: AppColors.pastelCoral,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Keep calm and carry on',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error State ─────────────────────────────────────────────

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.pastelCoral,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load leaderboard',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

// ── Podium Section ──────────────────────────────────────────────

class _PodiumSection extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  const _PodiumSection({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.pastelCoral.withValues(alpha: 0.08),
            AppColors.surface,
            AppColors.pastelAmber.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.pastelCoral.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd place (if exists)
          if (entries.length > 1)
            _PodiumPlace(entry: entries[1], rank: 2)
          else
            const SizedBox(width: 80),

          // 1st place
          _PodiumPlace(entry: entries[0], rank: 1),

          // 3rd place (if exists)
          if (entries.length > 2)
            _PodiumPlace(entry: entries[2], rank: 3)
          else
            const SizedBox(width: 80),
        ],
      ),
    );
  }
}

class _PodiumPlace extends StatelessWidget {
  final LeaderboardEntry entry;
  final int rank;

  const _PodiumPlace({required this.entry, required this.rank});

  @override
  Widget build(BuildContext context) {
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '$rank',
    };

    final avatarSize = rank == 1 ? 56.0 : 44.0;
    final fontSize = rank == 1 ? 26.0 : 20.0;

    final accentColor = switch (rank) {
      1 => AppColors.pastelCoral,
      2 => AppColors.pastelAmber,
      _ => AppColors.pastelSage,
    };

    // Extract initials from name
    final initials = _getInitials(entry.name);

    return SizedBox(
      width: 90,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Medal
          Text(medal, style: TextStyle(fontSize: rank == 1 ? 28 : 22)),
          const SizedBox(height: 8),
          // Avatar circle
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accentColor.withValues(alpha: 0.3),
                  accentColor.withValues(alpha: 0.1),
                ],
              ),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.2),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: accentColor,
                  fontSize: avatarSize * 0.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Name
          Text(
            _truncateName(entry.name),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 11,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Spike count
          Text(
            '${entry.spikeCount}',
            style: TextStyle(
              color: accentColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'spikes',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
          ),
        ],
      ),
    );
  }
}

// ── Ranked Card ─────────────────────────────────────────────────

class _RankedCard extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;

  const _RankedCard({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context) {
    final accentColor = switch (rank) {
      1 => AppColors.pastelCoral,
      2 => AppColors.pastelAmber,
      3 => AppColors.pastelSage,
      _ => AppColors.pastelLavender,
    };

    final initials = _getInitials(entry.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: rank <= 3
              ? accentColor.withValues(alpha: 0.15)
              : AppColors.cardBorder,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: rank <= 3 ? accentColor : AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.1),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name & last seen
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Avg peak ${entry.avgPeakHr.round()} bpm',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
          // Spike count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.whatshot_rounded,
                  color: accentColor,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  '${entry.spikeCount}',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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

// ── Helpers ─────────────────────────────────────────────────────

/// Extract initials from a full name (e.g. "John Doe" → "JD").
String _getInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
}

/// Truncate a name to first name only for podium display.
String _truncateName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return name;
  return parts[0];
}
