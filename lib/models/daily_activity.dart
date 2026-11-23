/// Persisted daily physical activity summary synced from the Colmi R02 ring.
class DailyActivityRecord {
  final String date; // YYYY-MM-DD (local calendar date)
  final int steps;
  final int calories; // kcal
  final int distanceMeters;
  final int activeMinutes;
  final int stepGoal;
  final DateTime syncedAt;

  const DailyActivityRecord({
    required this.date,
    required this.steps,
    required this.calories,
    required this.distanceMeters,
    required this.activeMinutes,
    this.stepGoal = 8000,
    required this.syncedAt,
  });

  double get goalProgress =>
      stepGoal > 0 ? (steps / stepGoal).clamp(0.0, 1.0) : 0.0;

  int get goalPercent =>
      stepGoal > 0 ? ((steps / stepGoal) * 100).round().clamp(0, 100) : 0;

  double get distanceKm => distanceMeters / 1000.0;

  DailyActivityRecord copyWith({
    String? date,
    int? steps,
    int? calories,
    int? distanceMeters,
    int? activeMinutes,
    int? stepGoal,
    DateTime? syncedAt,
  }) {
    return DailyActivityRecord(
      date: date ?? this.date,
      steps: steps ?? this.steps,
      calories: calories ?? this.calories,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      activeMinutes: activeMinutes ?? this.activeMinutes,
      stepGoal: stepGoal ?? this.stepGoal,
      syncedAt: syncedAt ?? this.syncedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'steps': steps,
      'calories': calories,
      'distance_meters': distanceMeters,
      'active_minutes': activeMinutes,
      'step_goal': stepGoal,
      'synced_at': syncedAt.toUtc().toIso8601String(),
    };
  }

  factory DailyActivityRecord.fromMap(Map<String, dynamic> map) {
    return DailyActivityRecord(
      date: map['date'] as String,
      steps: (map['steps'] as num?)?.toInt() ?? 0,
      calories: (map['calories'] as num?)?.toInt() ?? 0,
      distanceMeters: (map['distance_meters'] as num?)?.toInt() ?? 0,
      activeMinutes: (map['active_minutes'] as num?)?.toInt() ?? 0,
      stepGoal: (map['step_goal'] as num?)?.toInt() ?? 8000,
      syncedAt: DateTime.parse(map['synced_at'] as String).toUtc(),
    );
  }

  @override
  String toString() =>
      'DailyActivityRecord($date: $steps steps, $calories cal, ${distanceMeters}m)';
}

/// Multi-day rolling averages for physical activity.
class ActivityAverages {
  final double avgSteps;
  final double avgCalories;
  final double avgDistanceMeters;
  final double avgActiveMinutes;
  final int daysCount;

  const ActivityAverages({
    required this.avgSteps,
    required this.avgCalories,
    required this.avgDistanceMeters,
    required this.avgActiveMinutes,
    required this.daysCount,
  });

  static const empty = ActivityAverages(
    avgSteps: 0,
    avgCalories: 0,
    avgDistanceMeters: 0,
    avgActiveMinutes: 0,
    daysCount: 0,
  );
}
