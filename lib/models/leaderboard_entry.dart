/// A leaderboard entry aggregating stress events by coworker.
class LeaderboardEntry {
  final String name;
  final int spikeCount;
  final double avgPeakHr;
  final DateTime lastSeen;

  const LeaderboardEntry({
    required this.name,
    required this.spikeCount,
    required this.avgPeakHr,
    required this.lastSeen,
  });

  /// Create from a database aggregation row.
  factory LeaderboardEntry.fromMap(Map<String, dynamic> map) {
    return LeaderboardEntry(
      name: map['name'] as String,
      spikeCount: map['spike_count'] as int,
      avgPeakHr: (map['avg_peak_hr'] as num).toDouble(),
      lastSeen: DateTime.parse(map['last_seen'] as String),
    );
  }

  @override
  String toString() =>
      'LeaderboardEntry($name: $spikeCount spikes, avg $avgPeakHr bpm)';
}
