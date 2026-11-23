import 'package:flutter/material.dart';
import '../../services/calendar_service.dart';
import '../../theme/app_colors.dart';
import 'leaderboard_helpers.dart';

/// Banner displaying the active live meeting session (with privacy masking)
/// or quick actions to start a meeting / tag a spike manually.
class MeetingActionBanner extends StatelessWidget {
  final CurrentMeeting? activeMeeting;
  final bool privacyMode;
  final VoidCallback onStartSession;
  final VoidCallback onEndSession;
  final VoidCallback onLogManualSpike;

  const MeetingActionBanner({
    super.key,
    required this.activeMeeting,
    required this.privacyMode,
    required this.onStartSession,
    required this.onEndSession,
    required this.onLogManualSpike,
  });

  @override
  Widget build(BuildContext context) {
    if (activeMeeting != null) {
      final attendeeList = activeMeeting!.attendees
          .map(
            (name) => privacyMode ? getInitials(name) : name,
          )
          .join(', ');

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
                    privacyMode ? 'Active Meeting Session' : activeMeeting!.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Auto-tagging: $attendeeList',
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
            Semantics(
              button: true,
              label: 'End active meeting',
              child: InkWell(
                onTap: onEndSession,
                borderRadius: BorderRadius.circular(10),
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
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Start Meeting',
            child: InkWell(
              onTap: onStartSession,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                    const SizedBox(width: 6),
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
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            button: true,
            label: 'Tag Coworker Spike',
            child: InkWell(
              onTap: onLogManualSpike,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Tag Spike',
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
        ),
      ],
    );
  }
}
