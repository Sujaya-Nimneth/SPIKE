import 'package:flutter/material.dart';
import '../../models/leaderboard_entry.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_formatter.dart';
import 'leaderboard_helpers.dart';

/// Ranked coworker card row in the stress leaderboard list.
class RankedCoworkerCard extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;
  final bool privacyMode;
  final VoidCallback onTap;

  const RankedCoworkerCard({
    super.key,
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

    final initials = getInitials(entry.name);
    final displayName =
        formatCoworkerName(entry.name, privacyMode: privacyMode);

    return Semantics(
      button: true,
      label: 'Rank $rank, $displayName, ${entry.spikeCount} spikes',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  SizedBox(
                    width: 28,
                    child: Text(
                      '#$rank',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: rank <= 3
                                ? accentColor
                                : AppColors.textTertiary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Avg peak ${entry.avgPeakHr.round()} bpm · ${DateFormatter.formatRelative(entry.lastSeen)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: AppColors.textTertiary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          ),
        ),
      ),
    );
  }
}
