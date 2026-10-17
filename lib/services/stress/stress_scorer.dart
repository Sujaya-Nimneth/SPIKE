import 'dart:math' as math;
import 'baseline_estimator.dart';

/// Instantaneous stress evaluation for a single heart rate sample.
class StressSampleScore {
  final double zScore;
  final double ratio;
  final double instantStressScore;
  final int calmScore;
  final bool isAboveEntryThreshold;
  final bool isAboveExitThreshold;

  const StressSampleScore({
    required this.zScore,
    required this.ratio,
    required this.instantStressScore,
    required this.calmScore,
    required this.isAboveEntryThreshold,
    required this.isAboveExitThreshold,
  });
}

/// Computes z-scores, baseline ratios, instantaneous stress (0–100),
/// and an exponentially smoothed Calm Score (0–100).
class StressScorer {
  /// Entry threshold: HR must reach either `z >= 2.5` or `>= 1.25x` baseline.
  final double entryZThreshold;
  final double entryRatioThreshold;

  /// Hysteresis exit threshold: once elevated, stays active while
  /// `z >= 1.5` or `>= 1.15x` baseline.
  final double exitZThreshold;
  final double exitRatioThreshold;

  /// Exponential moving average smoothing factor for the live Calm Score.
  final double emaAlpha;

  double _emaStress = 12.0; // Corresponds to default Calm Score = 88

  StressScorer({
    this.entryZThreshold = 2.5,
    this.entryRatioThreshold = 1.25,
    this.exitZThreshold = 1.5,
    this.exitRatioThreshold = 1.15,
    this.emaAlpha = 0.15,
  });

  /// Current smoothed Calm Score (0–100). Defaults to 88 at rest.
  int get calmScore => (100.0 - _emaStress).round().clamp(0, 100);

  /// Evaluate a smoothed heart rate against the current [baseline].
  StressSampleScore evaluate(double smoothedHr, BaselineSnapshot baseline) {
    final delta = smoothedHr - baseline.medianHr;
    final zScore = delta / baseline.robustSigma;
    final ratio = baseline.medianHr > 0 ? smoothedHr / baseline.medianHr : 1.0;

    final aboveEntry =
        zScore >= entryZThreshold || ratio >= entryRatioThreshold;
    final aboveExit = zScore >= exitZThreshold || ratio >= exitRatioThreshold;

    // Map z-score to 0..100 stress score via logistic curve centered at z = 2.0
    // At z = 0 -> ~12 (Calm 88); at z = 2.5 -> ~73 (Calm 27); at z = 4 -> ~95
    final rawLogistic = 100.0 / (1.0 + math.exp(-1.0 * (zScore - 2.0)));
    final instantStress = rawLogistic.clamp(0.0, 100.0);

    _emaStress = (emaAlpha * instantStress) + ((1.0 - emaAlpha) * _emaStress);

    return StressSampleScore(
      zScore: zScore,
      ratio: ratio,
      instantStressScore: instantStress,
      calmScore: calmScore,
      isAboveEntryThreshold: aboveEntry,
      isAboveExitThreshold: aboveExit,
    );
  }

  /// Reset EMA state to resting default (Calm Score 88).
  void reset() {
    _emaStress = 12.0;
  }
}
