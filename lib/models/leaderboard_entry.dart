/// Timeframe filter for the coworker stress leaderboard.
enum LeaderboardPeriod {
  days7('7 Days', Duration(days: 7)),
  days30('30 Days', Duration(days: 30)),
  allTime('All Time', null);

  final String label;
  final Duration? window;
  const LeaderboardPeriod(this.label, this.window);
}

/// A leaderboard entry aggregating stress events by coworker.
///
/// Ranked primarily by [spikeCount] descending, with [avgPeakHr] as tie-breaker.
class LeaderboardEntry {
  final String name;
  final int spikeCount;
  final double avgPeakHr;
  final int maxPeakHr;
  final double avgBaselineHr;
  final int totalDurationSeconds;
  final DateTime lastSeen;

  const LeaderboardEntry({
    required this.name,
    required this.spikeCount,
    required this.avgPeakHr,
    int? maxPeakHr,
    double? avgBaselineHr,
    this.totalDurationSeconds = 0,
    required this.lastSeen,
  })  : maxPeakHr = maxPeakHr ?? 0,
        avgBaselineHr = avgBaselineHr ?? 70.0;

  /// Average BPM elevation above baseline during spikes with this coworker.
  int get avgElevationBpm => (avgPeakHr - avgBaselineHr).round().clamp(0, 150);

  /// Create from a database aggregation row.
  factory LeaderboardEntry.fromMap(Map<String, dynamic> map) {
    final avgPeak = (map['avg_peak_hr'] as num).toDouble();
    return LeaderboardEntry(
      name: map['name'] as String,
      spikeCount: map['spike_count'] as int,
      avgPeakHr: avgPeak,
      maxPeakHr: (map['max_peak_hr'] as int?) ?? avgPeak.round(),
      avgBaselineHr: (map['avg_baseline_hr'] as num?)?.toDouble() ?? 70.0,
      totalDurationSeconds: (map['total_duration_seconds'] as int?) ?? 0,
      lastSeen: DateTime.parse(map['last_seen'] as String),
    );
  }

  @override
  String toString() =>
      'LeaderboardEntry($name: $spikeCount spikes, avg ${avgPeakHr.toStringAsFixed(1)} bpm)';
}
