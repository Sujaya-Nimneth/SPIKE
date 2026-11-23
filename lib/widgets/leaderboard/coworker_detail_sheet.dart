import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/leaderboard_entry.dart';
import '../../providers/stress_providers.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_formatter.dart';
import 'leaderboard_helpers.dart';

/// Detail modal sheet displaying a coworker's period-filtered spike history,
/// rename/merge controls, spike deletion, and hide toggle.
class CoworkerDetailSheet extends ConsumerWidget {
  final LeaderboardEntry entry;
  final bool privacyMode;

  const CoworkerDetailSheet({
    super.key,
    required this.entry,
    required this.privacyMode,
  });

  Future<void> _renameCoworker(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: entry.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
        title: Text(
          'Rename or Merge Coworker',
          style: Theme.of(ctx).textTheme.headlineSmall,
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'New name',
            hintStyle: const TextStyle(color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(
                color: AppColors.pastelTeal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName != null && newName.isNotEmpty && newName != entry.name) {
      await ref
          .read(databaseServiceProvider)
          .renameCoworker(entry.name, newName);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _confirmHide(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
        title: Text(
          'Hide from Leaderboard?',
          style: Theme.of(ctx).textTheme.headlineSmall,
        ),
        content: Text(
          'Recorded events remain saved. You can unhide coworkers anytime in Settings.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Hide',
              style: TextStyle(
                color: AppColors.pastelCoral,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(databaseServiceProvider)
          .setCoworkerHidden(entry.name, hidden: true);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(coworkerEventsProvider(entry.name));
    final period = ref.watch(leaderboardPeriodProvider);
    final displayName =
        formatCoworkerName(entry.name, privacyMode: privacyMode);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
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
                      getInitials(entry.name),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${entry.spikeCount} ${entry.spikeCount == 1 ? 'spike' : 'spikes'} (${period.label}) · Avg peak ${entry.avgPeakHr.round()} bpm (+${entry.avgElevationBpm} bpm)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                if (!privacyMode)
                  IconButton(
                    tooltip: 'Rename or merge coworker',
                    onPressed: () => _renameCoworker(context, ref),
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.textTertiary,
                      size: 19,
                    ),
                  ),
                IconButton(
                  tooltip: 'Hide from leaderboard',
                  onPressed: () => _confirmHide(context, ref),
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
              'RECORDED SPIKES (${period.label.toUpperCase()})',
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
                    return const Text('No events found for this timeframe');
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
                            if (ev.id != null) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: 'Delete spike',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () async {
                                  await ref
                                      .read(databaseServiceProvider)
                                      .deleteStressEvent(ev.id!);
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppColors.textTertiary,
                                  size: 16,
                                ),
                              ),
                            ],
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
      ),
    );
  }
}
