import 'package:flutter/material.dart';
import '../../models/leaderboard_entry.dart';
import '../../theme/app_colors.dart';
import 'leaderboard_helpers.dart';

/// Top-3 podium widget for the coworker stress leaderboard.
class PodiumSection extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final bool privacyMode;
  final ValueChanged<LeaderboardEntry> onTapEntry;

  const PodiumSection({
    super.key,
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
          Expanded(
            child: entries.length > 1
                ? _PodiumPlace(
                    entry: entries[1],
                    rank: 2,
                    privacyMode: privacyMode,
                    onTap: () => onTapEntry(entries[1]),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: _PodiumPlace(
              entry: entries[0],
              rank: 1,
              privacyMode: privacyMode,
              onTap: () => onTapEntry(entries[0]),
            ),
          ),
          Expanded(
            child: entries.length > 2
                ? _PodiumPlace(
                    entry: entries[2],
                    rank: 3,
                    privacyMode: privacyMode,
                    onTap: () => onTapEntry(entries[2]),
                  )
                : const SizedBox.shrink(),
          ),
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

    final initials = getInitials(entry.name);
    final displayName = privacyMode ? initials : truncateName(entry.name);

    return Semantics(
      button: true,
      label: 'Rank $rank, $displayName, ${entry.spikeCount} spikes',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(medal, style: TextStyle(fontSize: rank == 1 ? 28 : 22)),
              const SizedBox(height: 8),
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
      ),
    );
  }
}
