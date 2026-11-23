/// Aggregated daily heart rate summary persisted in SQLite.
class DailyHrSummary {
  final String date; // YYYY-MM-DD (local calendar date)
  final int lastHr;
  final int minHr;
  final int maxHr;
  final int hrSum;
  final int sampleCount;
  final int? restingHr;
  final DateTime updatedAt;

  const DailyHrSummary({
    required this.date,
    required this.lastHr,
    required this.minHr,
    required this.maxHr,
    required this.hrSum,
    required this.sampleCount,
    this.restingHr,
    required this.updatedAt,
  });

  double get avgHr => sampleCount > 0 ? hrSum / sampleCount : lastHr.toDouble();

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'last_hr': lastHr,
      'min_hr': minHr,
      'max_hr': maxHr,
      'hr_sum': hrSum,
      'sample_count': sampleCount,
      'resting_hr': restingHr,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory DailyHrSummary.fromMap(Map<String, dynamic> map) {
    return DailyHrSummary(
      date: map['date'] as String,
      lastHr: (map['last_hr'] as num).toInt(),
      minHr: (map['min_hr'] as num).toInt(),
      maxHr: (map['max_hr'] as num).toInt(),
      hrSum: (map['hr_sum'] as num).toInt(),
      sampleCount: (map['sample_count'] as num).toInt(),
      restingHr: (map['resting_hr'] as num?)?.toInt(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
    );
  }
}
