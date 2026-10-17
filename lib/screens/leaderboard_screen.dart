import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/leaderboard_entry.dart';
import '../models/stress_event.dart';
import '../providers/ble_providers.dart';
import '../providers/stress_providers.dart';
import '../services/calendar_service.dart';
import '../theme/app_colors.dart';
import '../utils/date_formatter.dart';

/// A leaderboard screen ranking coworkers by how many HR stress spikes
/// they are associated with during meetings.
///
/// Supports manual coworker tagging, live meeting sessions, timeframe
/// filtering (7d / 30d / All Time), office-safe privacy mode, and
/// per-coworker spike history inspection.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboardAsync = ref.watch(leaderboardProvider);
    final eventCountAsync = ref.watch(stressEventCountProvider);
    final untaggedAsync = ref.watch(untaggedStressEventsProvider);
    final activeMeeting = ref.watch(activeMeetingProvider);
    final selectedPeriod = ref.watch(leaderboardPeriodProvider);
    final privacyMode = ref.watch(leaderboardPrivacyModeProvider);

    return SafeArea(
      bottom: false,
      child: leaderboardAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.pastelCoral),
        ),
        error: (_, __) => _buildErrorState(context),
        data: (entries) {
          final totalEvents = eventCountAsync.valueOrNull ?? 0;
          final untaggedEvents = untaggedAsync.valueOrNull ?? const [];

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row + Office-safe privacy toggle + Log button
                      _buildHeader(
                        context,
                        ref,
                        totalEvents: totalEvents,
                        privacyMode: privacyMode,
                      ),
                      const SizedBox(height: 16),

                      // Active Meeting Session / Manual Tagging Controls
                      _MeetingActionBanner(
                        activeMeeting: activeMeeting,
                        onStartSession: () =>
                            _showStartMeetingSheet(context, ref),
                        onEndSession: () => ref
                            .read(activeMeetingProvider.notifier)
                            .endSession(),
                        onLogManualSpike: () =>
                            _showTagOrLogSpikeSheet(context, ref),
                      ),
                      const SizedBox(height: 14),

                      // Untagged stress events prompt (if any)
                      if (untaggedEvents.isNotEmpty) ...[
                        _UntaggedSpikesBanner(
                          untaggedEvents: untaggedEvents,
                          onTagEvent: (event) => _showTagOrLogSpikeSheet(
                            context,
                            ref,
                            existingEvent: event,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Period filter chips (7 Days / 30 Days / All Time)
                      _PeriodFilterRow(
                        selectedPeriod: selectedPeriod,
                        onChanged: (period) {
                          ref.read(leaderboardPeriodProvider.notifier).state =
                              period;
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              if (entries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(
                    context,
                    onStartMeeting: () => _showStartMeetingSheet(context, ref),
                    onLogSpike: () => _showTagOrLogSpikeSheet(context, ref),
                  ),
                )
              else ...[
                // Podium (top 3)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _PodiumSection(
                      entries: entries.take(3).toList(),
                      privacyMode: privacyMode,
                      onTapEntry: (entry) => _showCoworkerDetailSheet(
                        context,
                        ref,
                        entry,
                        privacyMode: privacyMode,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),

                // Full ranked list header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'ALL COWORKERS',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: 2,
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ),
                ),

                // Lazy SliverList of ranked coworkers
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                  sliver: SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _RankedCard(
                        rank: index + 1,
                        entry: entry,
                        privacyMode: privacyMode,
                        onTap: () => _showCoworkerDetailSheet(
                          context,
                          ref,
                          entry,
                          privacyMode: privacyMode,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref, {
    required int totalEvents,
    required bool privacyMode,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Stress',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Leaderboard',
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                fontSize: 28,
                                fontWeight: FontWeight.w300,
                                color: AppColors.pastelCoral,
                              ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$totalEvents stress events recorded',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        // Office-safe privacy mode toggle
        Tooltip(
          message: privacyMode
              ? 'Show full coworker names'
              : 'Office-safe mode (initials only)',
          child: GestureDetector(
            onTap: () {
              ref.read(leaderboardPrivacyModeProvider.notifier).state =
                  !privacyMode;
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: privacyMode
                    ? AppColors.pastelTeal.withValues(alpha: 0.14)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: privacyMode
                      ? AppColors.pastelTeal.withValues(alpha: 0.4)
                      : AppColors.cardBorder,
                  width: 0.5,
                ),
              ),
              child: Icon(
                privacyMode
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: privacyMode
                    ? AppColors.pastelTeal
                    : AppColors.textSecondary,
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Empty State ─────────────────────────────────────────────

  Widget _buildEmptyState(
    BuildContext context, {
    required VoidCallback onStartMeeting,
    required VoidCallback onLogSpike,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 110),
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
              'for 2+ minutes during a meeting, tag the coworkers in '
              'the room and the culprits will rank here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.5,
                  ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                GestureDetector(
                  onTap: onStartMeeting,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.pastelTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.pastelTeal.withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.groups_rounded,
                          color: AppColors.pastelTeal,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Start Meeting',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.pastelTeal,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onLogSpike,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.cardBorder,
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: AppColors.pastelCoral,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Tag a Spike',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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

  // ── Sheets & Modals ─────────────────────────────────────────

  void _showStartMeetingSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _StartMeetingSheet(),
    );
  }

  void _showTagOrLogSpikeSheet(
    BuildContext context,
    WidgetRef ref, {
    StressEvent? existingEvent,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TagSpikeSheet(existingEvent: existingEvent),
    );
  }

  void _showCoworkerDetailSheet(
    BuildContext context,
    WidgetRef ref,
    LeaderboardEntry entry, {
    required bool privacyMode,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _CoworkerDetailSheet(
        entry: entry,
        privacyMode: privacyMode,
      ),
    );
  }
}

// ── Active Meeting & Manual Tagging Banner ──────────────────────

class _MeetingActionBanner extends StatelessWidget {
  final CurrentMeeting? activeMeeting;
  final VoidCallback onStartSession;
  final VoidCallback onEndSession;
  final VoidCallback onLogManualSpike;

  const _MeetingActionBanner({
    required this.activeMeeting,
    required this.onStartSession,
    required this.onEndSession,
    required this.onLogManualSpike,
  });

  @override
  Widget build(BuildContext context) {
    if (activeMeeting != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.pastelTeal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.pastelTeal.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.pastelTeal.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.record_voice_over_rounded,
                color: AppColors.pastelTeal,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activeMeeting!.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Auto-tagging: ${activeMeeting!.attendees.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.pastelTeal,
                          fontSize: 11,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onEndSession,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.pastelCoral.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'End',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.pastelCoral,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onStartSession,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.pastelTeal.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.groups_rounded,
                    color: AppColors.pastelTeal,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Start Meeting',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.pastelTeal,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: onLogManualSpike,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.pastelCoral.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: AppColors.pastelCoral,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Tag a Spike',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppColors.pastelCoral,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Untagged Spikes Prompt Banner ───────────────────────────────

class _UntaggedSpikesBanner extends StatelessWidget {
  final List<StressEvent> untaggedEvents;
  final ValueChanged<StressEvent> onTagEvent;

  const _UntaggedSpikesBanner({
    required this.untaggedEvents,
    required this.onTagEvent,
  });

  @override
  Widget build(BuildContext context) {
    final latest = untaggedEvents.first;
    final count = untaggedEvents.length;

    return GestureDetector(
      onTap: () => onTagEvent(latest),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.pastelAmber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.pastelAmber.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.pastelAmber.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.label_important_outline_rounded,
                color: AppColors.pastelAmber,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count == 1
                        ? '1 untagged stress spike (${latest.peakHr} bpm)'
                        : '$count untagged stress spikes (latest ${latest.peakHr} bpm)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.pastelAmber,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to tag which coworkers were in the room',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.pastelAmber,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Period Filter Row ───────────────────────────────────────────

class _PeriodFilterRow extends StatelessWidget {
  final LeaderboardPeriod selectedPeriod;
  final ValueChanged<LeaderboardPeriod> onChanged;

  const _PeriodFilterRow({
    required this.selectedPeriod,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: LeaderboardPeriod.values.map((period) {
        final isSelected = period == selectedPeriod;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(period),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.pastelCoral.withValues(alpha: 0.15)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? AppColors.pastelCoral.withValues(alpha: 0.4)
                      : AppColors.cardBorder,
                  width: 0.5,
                ),
              ),
              child: Text(
                period.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected
                          ? AppColors.pastelCoral
                          : AppColors.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 12,
                    ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Podium Section ──────────────────────────────────────────────

class _PodiumSection extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final bool privacyMode;
  final ValueChanged<LeaderboardEntry> onTapEntry;

  const _PodiumSection({
    required this.entries,
    required this.privacyMode,
    required this.onTapEntry,
  });

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
            _PodiumPlace(
              entry: entries[1],
              rank: 2,
              privacyMode: privacyMode,
              onTap: () => onTapEntry(entries[1]),
            )
          else
            const SizedBox(width: 80),

          // 1st place
          _PodiumPlace(
            entry: entries[0],
            rank: 1,
            privacyMode: privacyMode,
            onTap: () => onTapEntry(entries[0]),
          ),

          // 3rd place (if exists)
          if (entries.length > 2)
            _PodiumPlace(
              entry: entries[2],
              rank: 3,
              privacyMode: privacyMode,
              onTap: () => onTapEntry(entries[2]),
            )
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
  final bool privacyMode;
  final VoidCallback onTap;

  const _PodiumPlace({
    required this.entry,
    required this.rank,
    required this.privacyMode,
    required this.onTap,
  });

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

    final initials = _getInitials(entry.name);
    final displayName = privacyMode ? initials : _truncateName(entry.name);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
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
              displayName,
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
            // Primary headline metric: Raw Spike Count
            Text(
              '${entry.spikeCount}',
              style: TextStyle(
                color: accentColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              entry.spikeCount == 1 ? 'spike' : 'spikes',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ranked Card ─────────────────────────────────────────────────

class _RankedCard extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;
  final bool privacyMode;
  final VoidCallback onTap;

  const _RankedCard({
    required this.rank,
    required this.entry,
    required this.privacyMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = switch (rank) {
      1 => AppColors.pastelCoral,
      2 => AppColors.pastelAmber,
      3 => AppColors.pastelSage,
      _ => AppColors.pastelLavender,
    };

    final initials = _getInitials(entry.name);
    final displayName = privacyMode ? 'Coworker $initials' : entry.name;

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            // Name & peak HR / relative timestamp
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Avg peak ${entry.avgPeakHr.round()} bpm · ${DateFormatter.formatRelative(entry.lastSeen)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: AppColors.textTertiary,
                        ),
                  ),
                ],
              ),
            ),
            // Spike count badge (primary metric)
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
      ),
    );
  }
}

// ── Start Meeting Session Bottom Sheet ──────────────────────────

class _StartMeetingSheet extends ConsumerStatefulWidget {
  const _StartMeetingSheet();

  @override
  ConsumerState<_StartMeetingSheet> createState() => _StartMeetingSheetState();
}

class _StartMeetingSheetState extends ConsumerState<_StartMeetingSheet> {
  final _titleController = TextEditingController();
  final _nameController = TextEditingController();
  final Set<String> _selectedCoworkers = {};

  @override
  void dispose() {
    _titleController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _addTypedName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _selectedCoworkers.add(trimmed);
      _nameController.clear();
    });
    ref.read(databaseServiceProvider).addCoworker(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final savedNamesAsync = ref.watch(coworkerNamesProvider);
    final savedNames = savedNamesAsync.valueOrNull ?? const [];
    final allChips = {...savedNames, ..._selectedCoworkers}.toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start Live Meeting Session',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Select who is in the room. Any heart rate stress spike detected '
            'while the session is active will automatically tag them.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Meeting title (optional, e.g. Sprint Review)',
              hintStyle: const TextStyle(color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  onSubmitted: (_) => _addTypedName(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add coworker name…',
                    hintStyle: const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _addTypedName,
                style: IconButton.styleFrom(
                  backgroundColor:
                      AppColors.pastelTeal.withValues(alpha: 0.15),
                ),
                icon: const Icon(Icons.add_rounded, color: AppColors.pastelTeal),
              ),
            ],
          ),
          if (allChips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allChips.map((name) {
                final selected = _selectedCoworkers.contains(name);
                return FilterChip(
                  label: Text(name),
                  selected: selected,
                  selectedColor: AppColors.pastelTeal.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.pastelTeal,
                  backgroundColor: AppColors.surfaceVariant,
                  labelStyle: TextStyle(
                    color: selected
                        ? AppColors.pastelTeal
                        : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedCoworkers.add(name);
                      } else {
                        _selectedCoworkers.remove(name);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.pastelTeal,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _selectedCoworkers.isEmpty
                  ? null
                  : () {
                      ref.read(activeMeetingProvider.notifier).startSession(
                            attendees: _selectedCoworkers.toList(),
                            title: _titleController.text,
                          );
                      Navigator.of(context).pop();
                    },
              child: const Text(
                'Start Monitoring Meeting',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tag Existing or Log New Stress Spike Sheet ──────────────────

class _TagSpikeSheet extends ConsumerStatefulWidget {
  final StressEvent? existingEvent;

  const _TagSpikeSheet({this.existingEvent});

  @override
  ConsumerState<_TagSpikeSheet> createState() => _TagSpikeSheetState();
}

class _TagSpikeSheetState extends ConsumerState<_TagSpikeSheet> {
  late final TextEditingController _titleController;
  final _nameController = TextEditingController();
  late final Set<String> _selectedCoworkers;
  double _peakHr = 110;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingEvent;
    _titleController = TextEditingController(text: existing?.meetingTitle ?? '');
    _selectedCoworkers = {...?existing?.attendees};
    if (existing != null) {
      _peakHr = existing.peakHr.toDouble().clamp(85, 190);
    } else {
      final liveHr = ref.read(latestHeartRateProvider);
      if (liveHr != null && liveHr >= 85) {
        _peakHr = liveHr.toDouble().clamp(85, 190);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _addTypedName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _selectedCoworkers.add(trimmed);
      _nameController.clear();
    });
    ref.read(databaseServiceProvider).addCoworker(trimmed);
  }

  Future<void> _save() async {
    if (_selectedCoworkers.isEmpty) return;
    final db = ref.read(databaseServiceProvider);
    final existing = widget.existingEvent;

    if (existing != null && existing.id != null) {
      await db.updateEventAttendees(
        existing.id!,
        _selectedCoworkers.toList(),
        meetingTitle: _titleController.text,
      );
    } else {
      final baseline =
          ref.read(stressAnalyzerProvider).currentBaseline?.round() ?? 72;
      final event = StressEvent(
        timestamp: DateTime.now(),
        peakHr: _peakHr.round(),
        baselineHr: baseline,
        meetingTitle: _titleController.text.trim().isEmpty
            ? 'Tagged Meeting'
            : _titleController.text.trim(),
        attendees: _selectedCoworkers.toList(),
        durationSeconds: 180,
        label: StressEventLabel.confirmed,
      );
      await db.insertStressEvent(event);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _dismissFalsePositive() async {
    final existing = widget.existingEvent;
    if (existing?.id == null) return;
    await ref
        .read(databaseServiceProvider)
        .updateEventLabel(existing!.id!, StressEventLabel.dismissed);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedNames = ref.watch(coworkerNamesProvider).valueOrNull ?? const [];
    final allChips = {...savedNames, ..._selectedCoworkers}.toList();
    final existing = widget.existingEvent;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                existing != null
                    ? 'Tag Stress Spike (${existing.peakHr} bpm)'
                    : 'Tag Coworker Stress Spike',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (existing?.id != null)
                TextButton(
                  onPressed: _dismissFalsePositive,
                  child: const Text(
                    'Not Stress',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            existing != null
                ? 'Recorded ${DateFormatter.formatShortDateTime(existing.timestamp)} · Baseline ${existing.baselineHr} bpm'
                : 'Tag the coworker(s) who triggered this heart rate spike.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          if (existing == null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Peak Heart Rate',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${_peakHr.round()} bpm',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.pastelCoral,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            Slider(
              value: _peakHr,
              min: 85,
              max: 190,
              divisions: 105,
              activeColor: AppColors.pastelCoral,
              onChanged: (v) => setState(() => _peakHr = v),
            ),
          ],
          TextField(
            controller: _titleController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Meeting context (e.g. Architecture Review)',
              hintStyle: const TextStyle(color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  onSubmitted: (_) => _addTypedName(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add coworker name…',
                    hintStyle: const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _addTypedName,
                style: IconButton.styleFrom(
                  backgroundColor:
                      AppColors.pastelCoral.withValues(alpha: 0.15),
                ),
                icon: const Icon(Icons.add_rounded, color: AppColors.pastelCoral),
              ),
            ],
          ),
          if (allChips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allChips.map((name) {
                final selected = _selectedCoworkers.contains(name);
                return FilterChip(
                  label: Text(name),
                  selected: selected,
                  selectedColor: AppColors.pastelCoral.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.pastelCoral,
                  backgroundColor: AppColors.surfaceVariant,
                  labelStyle: TextStyle(
                    color: selected
                        ? AppColors.pastelCoral
                        : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedCoworkers.add(name);
                      } else {
                        _selectedCoworkers.remove(name);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.pastelCoral,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _selectedCoworkers.isEmpty ? null : _save,
              child: const Text(
                'Save Coworker Tag',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Coworker Detail Sheet ───────────────────────────────────────

class _CoworkerDetailSheet extends ConsumerWidget {
  final LeaderboardEntry entry;
  final bool privacyMode;

  const _CoworkerDetailSheet({
    required this.entry,
    required this.privacyMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(coworkerEventsProvider(entry.name));
    final displayName =
        privacyMode ? 'Coworker ${_getInitials(entry.name)}' : entry.name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.pastelCoral.withValues(alpha: 0.14),
                ),
                child: Center(
                  child: Text(
                    _getInitials(entry.name),
                    style: const TextStyle(
                      color: AppColors.pastelCoral,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      '${entry.spikeCount} spikes · Avg peak ${entry.avgPeakHr.round()} bpm (+${entry.avgElevationBpm} bpm)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Hide from leaderboard',
                onPressed: () async {
                  await ref
                      .read(databaseServiceProvider)
                      .setCoworkerHidden(entry.name, hidden: true);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(
                  Icons.visibility_off_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 8),
          Text(
            'RECORDED SPIKES',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.5,
                  color: AppColors.textTertiary,
                ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: eventsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.pastelCoral),
              ),
              error: (_, __) => const Text('Could not load events'),
              data: (events) {
                if (events.isEmpty) {
                  return const Text('No events found');
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final ev = events[index];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ev.meetingTitle ?? 'Meeting Spike',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: AppColors.textPrimary,
                                        fontSize: 13,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${DateFormatter.formatShortDateTime(ev.timestamp)} · ${(ev.durationSeconds / 60).ceil()} min',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontSize: 11,
                                        color: AppColors.textTertiary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${ev.peakHr} bpm',
                            style: const TextStyle(
                              color: AppColors.pastelCoral,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Safe Name Helpers ───────────────────────────────────────────

/// Safely extract initials from a full name or email (e.g. "John Doe" → "JD").
///
/// Guards against empty or whitespace-only strings to prevent [RangeError].
String _getInitials(String name) {
  final cleaned = name.trim();
  if (cleaned.isEmpty) return '?';

  // If it looks like an email address, use the local part before '@'
  final target =
      cleaned.contains('@') ? cleaned.split('@').first.trim() : cleaned;
  if (target.isEmpty) return '?';

  final parts = target
      .split(RegExp(r'[\s._-]+'))
      .where((part) => part.isNotEmpty)
      .toList();

  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  final firstChar = parts.first.substring(0, 1);
  final lastChar = parts.last.substring(0, 1);
  return '$firstChar$lastChar'.toUpperCase();
}

/// Truncate a name to first name only for podium display.
String _truncateName(String name) {
  final cleaned = name.trim();
  if (cleaned.isEmpty) return 'Unknown';
  final parts =
      cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return cleaned;
  return parts.first;
}
