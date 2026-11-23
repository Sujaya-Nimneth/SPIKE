import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/leaderboard_entry.dart';
import '../models/stress_event.dart';
import '../providers/stress_providers.dart';
import '../theme/app_colors.dart';
import '../widgets/leaderboard/coworker_detail_sheet.dart';
import '../widgets/leaderboard/meeting_action_banner.dart';
import '../widgets/leaderboard/podium_section.dart';
import '../widgets/leaderboard/ranked_coworker_card.dart';
import '../widgets/leaderboard/start_meeting_sheet.dart';
import '../widgets/leaderboard/tag_spike_sheet.dart';
import '../widgets/leaderboard/untagged_spikes_banner.dart';

/// A leaderboard screen ranking coworkers by how many HR stress spikes
/// they are associated with during meetings.
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

    final totalEvents = eventCountAsync.valueOrNull ?? 0;
    final untaggedEvents = untaggedAsync.valueOrNull ?? const <StressEvent>[];

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(
                    context,
                    ref,
                    totalEvents: totalEvents,
                    privacyMode: privacyMode,
                  ),
                  const SizedBox(height: 16),
                  MeetingActionBanner(
                    activeMeeting: activeMeeting,
                    privacyMode: privacyMode,
                    onStartSession: () => _showStartMeetingSheet(context),
                    onEndSession: () =>
                        ref.read(activeMeetingProvider.notifier).endSession(),
                    onLogManualSpike: () => _showTagOrLogSpikeSheet(context),
                  ),
                  const SizedBox(height: 14),
                  if (untaggedEvents.isNotEmpty) ...[
                    UntaggedSpikesBanner(
                      untaggedEvents: untaggedEvents,
                      onTagEvent: (event) => _showTagOrLogSpikeSheet(
                        context,
                        existingEvent: event,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _PeriodFilterRow(
                    selectedPeriod: selectedPeriod,
                    onChanged: (period) {
                      ref.read(leaderboardPeriodProvider.notifier).state = period;
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          ...leaderboardAsync.when(
            skipLoadingOnReload: true,
            loading: () => const [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.pastelCoral,
                  ),
                ),
              ),
            ],
            error: (_, __) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildErrorState(context),
              ),
            ],
            data: (entries) {
              if (entries.isEmpty) {
                return [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(
                      context,
                      onStartMeeting: () => _showStartMeetingSheet(context),
                      onLogSpike: () => _showTagOrLogSpikeSheet(context),
                    ),
                  ),
                ];
              }
              return [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: PodiumSection(
                      entries: entries.take(3).toList(),
                      privacyMode: privacyMode,
                      onTapEntry: (entry) => _showCoworkerDetailSheet(
                        context,
                        entry,
                        privacyMode: privacyMode,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                  sliver: SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return RankedCoworkerCard(
                        rank: index + 1,
                        entry: entry,
                        privacyMode: privacyMode,
                        onTap: () => _showCoworkerDetailSheet(
                          context,
                          entry,
                          privacyMode: privacyMode,
                        ),
                      );
                    },
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref, {
    required int totalEvents,
    required bool privacyMode,
  }) {
    final eventWord = totalEvents == 1 ? 'event' : 'events';

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
                '$totalEvents stress $eventWord recorded',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: privacyMode
              ? 'Disable office-safe privacy mode'
              : 'Enable office-safe privacy mode',
          child: Tooltip(
            message: privacyMode
                ? 'Show full coworker names'
                : 'Office-safe mode (initials only)',
            child: InkWell(
              onTap: () {
                ref.read(leaderboardPrivacyModeProvider.notifier).state =
                    !privacyMode;
              },
              borderRadius: BorderRadius.circular(12),
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
        ),
      ],
    );
  }

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
                InkWell(
                  onTap: onStartMeeting,
                  borderRadius: BorderRadius.circular(20),
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
                InkWell(
                  onTap: onLogSpike,
                  borderRadius: BorderRadius.circular(20),
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

  void _showStartMeetingSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const StartMeetingSheet(),
    );
  }

  void _showTagOrLogSpikeSheet(
    BuildContext context, {
    StressEvent? existingEvent,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => TagSpikeSheet(existingEvent: existingEvent),
    );
  }

  void _showCoworkerDetailSheet(
    BuildContext context,
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
      builder: (ctx) => CoworkerDetailSheet(
        entry: entry,
        privacyMode: privacyMode,
      ),
    );
  }
}

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
          child: InkWell(
            onTap: () => onChanged(period),
            borderRadius: BorderRadius.circular(16),
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
