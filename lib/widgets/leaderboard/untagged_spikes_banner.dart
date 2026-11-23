import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/stress_event.dart';
import '../../providers/stress_providers.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_formatter.dart';

/// Prompt banner highlighting untagged stress episodes.
///
/// Opens the tagging sheet directly when there is 1 untagged spike, or a
/// selector sheet listing all untagged spikes when multiple exist.
class UntaggedSpikesBanner extends StatelessWidget {
  final List<StressEvent> untaggedEvents;
  final ValueChanged<StressEvent> onTagEvent;

  const UntaggedSpikesBanner({
    super.key,
    required this.untaggedEvents,
    required this.onTagEvent,
  });

  @override
  Widget build(BuildContext context) {
    final latest = untaggedEvents.first;
    final count = untaggedEvents.length;

    return InkWell(
      onTap: () {
        if (count == 1) {
          onTagEvent(latest);
        } else {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (ctx) => _UntaggedSpikesListSheet(
              onSelectEvent: (event) {
                Navigator.of(ctx).pop();
                onTagEvent(event);
              },
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(16),
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
                    count == 1
                        ? 'Tap to tag which coworkers were in the room'
                        : 'Tap to review and tag any pending spike',
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

class _UntaggedSpikesListSheet extends ConsumerWidget {
  final ValueChanged<StressEvent> onSelectEvent;

  const _UntaggedSpikesListSheet({required this.onSelectEvent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final untaggedAsync = ref.watch(untaggedStressEventsProvider);
    final events = untaggedAsync.valueOrNull ?? const [];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Untagged Stress Spikes',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Select a spike to attribute coworkers or dismiss false positives.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('All stress spikes are tagged!')),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: events.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final ev = events[index];
                    return InkWell(
                      onTap: () => onSelectEvent(ev),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${ev.peakHr} bpm peak (+${ev.elevationBpm} bpm)',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${DateFormatter.formatShortDateTime(ev.timestamp)} · ${(ev.durationSeconds / 60).ceil()} min',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppColors.textTertiary,
                                          fontSize: 11,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            if (ev.id != null)
                              IconButton(
                                tooltip: 'Dismiss (Not Stress)',
                                onPressed: () async {
                                  await ref
                                      .read(databaseServiceProvider)
                                      .updateEventLabel(
                                        ev.id!,
                                        StressEventLabel.dismissed,
                                      );
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: AppColors.textTertiary,
                                  size: 18,
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
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
