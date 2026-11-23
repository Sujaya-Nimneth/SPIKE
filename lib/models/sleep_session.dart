import 'dart:math' as math;

/// Sleep stage classifications reported by the Colmi R02 BigData sleep protocol.
enum SleepStageType {
  noData(0),
  error(1),
  light(2),
  deep(3),
  rem(4),
  awake(5);

  final int code;
  const SleepStageType(this.code);

  static SleepStageType fromCode(int code) {
    for (final stage in SleepStageType.values) {
      if (stage.code == code) return stage;
    }
    return SleepStageType.noData;
  }
}

/// A contiguous sleep stage segment from the ring's BigData stream.
class SleepStageSegment {
  final SleepStageType type;
  final int durationMinutes;

  const SleepStageSegment({
    required this.type,
    required this.durationMinutes,
  });
}

/// Persisted nightly sleep session synced from the Colmi R02 ring.
class SleepSessionRecord {
  final String date; // YYYY-MM-DD (wake-up date)
  final DateTime? bedtime;
  final DateTime? wakeTime;
  final int totalSleepMinutes;
  final int timeInBedMinutes;
  final int awakeMinutes;
  final int lightMinutes;
  final int deepMinutes;
  final int remMinutes;
  final int efficiencyPercent;
  final int sleepScore;
  final int? restingHr;
  final DateTime syncedAt;

  const SleepSessionRecord({
    required this.date,
    this.bedtime,
    this.wakeTime,
    required this.totalSleepMinutes,
    required this.timeInBedMinutes,
    required this.awakeMinutes,
    required this.lightMinutes,
    required this.deepMinutes,
    required this.remMinutes,
    required this.efficiencyPercent,
    required this.sleepScore,
    this.restingHr,
    required this.syncedAt,
  });

  /// Compute a deterministic 0–100 Sleep Score from duration, efficiency, and
  /// restorative stages (Deep + REM).
  static int computeSleepScore({
    required int totalSleepMinutes,
    required int efficiencyPercent,
    required int deepMinutes,
    required int remMinutes,
  }) {
    if (totalSleepMinutes <= 0) return 0;

    // 1. Duration component (target 480m = 8h, worth up to 50 pts)
    final durationRatio = (totalSleepMinutes / 480.0).clamp(0.0, 1.05);
    final durationScore = (durationRatio * 50.0).clamp(0.0, 50.0);

    // 2. Sleep efficiency component (worth up to 25 pts; 95%+ -> full 25)
    final efficiencyScore =
        (((efficiencyPercent - 50).clamp(0, 48)) / 48.0) * 25.0;

    // 3. Restorative stages (Deep + REM target ~40% of total sleep, worth 25 pts)
    final restorativeRatio =
        ((deepMinutes + remMinutes) / math.max(1, totalSleepMinutes))
            .clamp(0.0, 0.5);
    final restorativeScore = (restorativeRatio / 0.40).clamp(0.0, 1.0) * 25.0;

    return (durationScore + efficiencyScore + restorativeScore)
        .round()
        .clamp(0, 100);
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'bedtime': bedtime?.toUtc().toIso8601String(),
      'wake_time': wakeTime?.toUtc().toIso8601String(),
      'total_sleep_minutes': totalSleepMinutes,
      'time_in_bed_minutes': timeInBedMinutes,
      'awake_minutes': awakeMinutes,
      'light_minutes': lightMinutes,
      'deep_minutes': deepMinutes,
      'rem_minutes': remMinutes,
      'efficiency_percent': efficiencyPercent,
      'sleep_score': sleepScore,
      'resting_hr': restingHr,
      'synced_at': syncedAt.toUtc().toIso8601String(),
    };
  }

  factory SleepSessionRecord.fromMap(Map<String, dynamic> map) {
    return SleepSessionRecord(
      date: map['date'] as String,
      bedtime: map['bedtime'] != null
          ? DateTime.parse(map['bedtime'] as String).toUtc()
          : null,
      wakeTime: map['wake_time'] != null
          ? DateTime.parse(map['wake_time'] as String).toUtc()
          : null,
      totalSleepMinutes: (map['total_sleep_minutes'] as num?)?.toInt() ?? 0,
      timeInBedMinutes: (map['time_in_bed_minutes'] as num?)?.toInt() ?? 0,
      awakeMinutes: (map['awake_minutes'] as num?)?.toInt() ?? 0,
      lightMinutes: (map['light_minutes'] as num?)?.toInt() ?? 0,
      deepMinutes: (map['deep_minutes'] as num?)?.toInt() ?? 0,
      remMinutes: (map['rem_minutes'] as num?)?.toInt() ?? 0,
      efficiencyPercent: (map['efficiency_percent'] as num?)?.toInt() ?? 0,
      sleepScore: (map['sleep_score'] as num?)?.toInt() ?? 0,
      restingHr: (map['resting_hr'] as num?)?.toInt(),
      syncedAt: DateTime.parse(map['synced_at'] as String).toUtc(),
    );
  }

  @override
  String toString() =>
      'SleepSessionRecord($date: ${totalSleepMinutes}m, score $sleepScore, $efficiencyPercent%)';
}

/// Multi-night rolling averages for sleep telemetry.
class SleepAverages {
  final double avgTotalSleepMinutes;
  final double avgEfficiencyPercent;
  final double avgSleepScore;
  final double avgDeepMinutes;
  final double avgRemMinutes;
  final int nightsCount;

  const SleepAverages({
    required this.avgTotalSleepMinutes,
    required this.avgEfficiencyPercent,
    required this.avgSleepScore,
    required this.avgDeepMinutes,
    required this.avgRemMinutes,
    required this.nightsCount,
  });

  static const empty = SleepAverages(
    avgTotalSleepMinutes: 0,
    avgEfficiencyPercent: 0,
    avgSleepScore: 0,
    avgDeepMinutes: 0,
    avgRemMinutes: 0,
    nightsCount: 0,
  );
}
