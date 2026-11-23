/// Recovery readiness zones inspired by WHOOP recovery scoring.
enum ReadinessZone {
  /// High recovery (67–100%): primed for high strain & deep work.
  peak('PEAK RECOVERY'),

  /// Moderate recovery (34–66%): balanced load recommended.
  adequate('ADEQUATE'),

  /// Low recovery (0–33%): prioritize rest and stress reduction.
  rest('REST & RECOVER'),

  /// No ring telemetry recorded yet.
  uncalibrated('AWAITING SYNC');

  final String label;
  const ReadinessZone(this.label);
}

/// An individual physiological contributor to the daily Ready Score.
class ReadinessFactor {
  final String label;
  final String displayValue;
  final int? score;
  final double weight;
  final String detail;
  final bool isAvailable;

  const ReadinessFactor({
    required this.label,
    required this.displayValue,
    required this.score,
    required this.weight,
    required this.detail,
    required this.isAvailable,
  });
}

/// Aggregated WHOOP-style daily Ready Score snapshot.
class ReadinessSnapshot {
  final int? score;
  final ReadinessZone zone;
  final String headline;
  final String guidance;
  final List<ReadinessFactor> factors;
  final bool isLive;
  final DateTime? lastSyncedAt;
  final double? dailyAvgReadyScore;

  const ReadinessSnapshot({
    required this.score,
    required this.zone,
    required this.headline,
    required this.guidance,
    required this.factors,
    required this.isLive,
    this.lastSyncedAt,
    this.dailyAvgReadyScore,
  });
}
