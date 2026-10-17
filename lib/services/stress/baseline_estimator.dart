import 'dart:collection';
import 'dart:math' as math;
import 'hr_signal_filter.dart';

/// Snapshot of the user's current heart rate baseline and variability.
class BaselineSnapshot {
  /// Robust rolling median heart rate (BPM).
  final double medianHr;

  /// Median Absolute Deviation (BPM).
  final double mad;

  /// Normal-consistent standard deviation estimate (`max(1.4826 * mad, 3.0)`).
  final double robustSigma;

  /// Number of samples currently in the baseline window.
  final int sampleCount;

  const BaselineSnapshot({
    required this.medianHr,
    required this.mad,
    required this.robustSigma,
    required this.sampleCount,
  });
}

/// Time-windowed, spike-resistant heart rate baseline estimator.
///
/// Key improvements over the v1 mean buffer:
/// 1. Uses **rolling median + MAD** instead of arithmetic mean so outliers
///    do not skew the baseline.
/// 2. **Freezes updates** while the user's HR is elevated (`isElevated = true`),
///    preventing an active stress spike from contaminating the baseline and
///    cancelling itself mid-meeting.
/// 3. Uses time-based windowing (`10 minutes`) and preserves the baseline
///    across short BLE connection drops (`<= 10 minutes`).
class BaselineEstimator {
  final Duration windowDuration;
  final int minSamplesToReady;
  final Duration maxGapBeforeFlush;

  BaselineEstimator({
    this.windowDuration = const Duration(minutes: 10),
    this.minSamplesToReady = 20,
    this.maxGapBeforeFlush = const Duration(minutes: 10),
  });

  final Queue<CleanHrSample> _samples = Queue();
  DateTime? _lastSeenTimestamp;
  BaselineSnapshot? _cachedSnapshot;

  /// Whether enough baseline data has been collected to evaluate stress spikes.
  bool get isReady => _samples.length >= minSamplesToReady;

  /// Current number of baseline samples in the window.
  int get sampleCount => _samples.length;

  /// Current baseline snapshot, or `null` if empty.
  BaselineSnapshot? get current {
    if (_samples.isEmpty) return null;
    return _cachedSnapshot ??= _computeSnapshot();
  }

  /// Record a new sample.
  ///
  /// When [isElevated] is `true`, the sample is NOT added to the baseline
  /// buffer so active stress episodes cannot inflate the baseline.
  void addSample(CleanHrSample sample, {bool isElevated = false}) {
    final now = sample.timestamp;

    // Flush only if the gap exceeds maxGapBeforeFlush (default 10 minutes)
    if (_lastSeenTimestamp != null &&
        now.difference(_lastSeenTimestamp!) > maxGapBeforeFlush) {
      _samples.clear();
      _cachedSnapshot = null;
    }
    _lastSeenTimestamp = now;

    if (!isElevated) {
      _samples.add(sample);
      final cutoff = now.subtract(windowDuration);
      while (_samples.isNotEmpty && _samples.first.timestamp.isBefore(cutoff)) {
        _samples.removeFirst();
      }
      _cachedSnapshot = null;
    }
  }

  BaselineSnapshot _computeSnapshot() {
    final values = _samples.map((s) => s.smoothedHr).toList()..sort();
    final median = _percentile(values, 0.50);

    final deviations = values.map((v) => (v - median).abs()).toList()..sort();
    final mad = _percentile(deviations, 0.50);

    // 1.4826 scales MAD to equivalent Gaussian standard deviation.
    // Floor at 3.0 BPM so very steady resting HR doesn't trigger on +3 BPM noise.
    final robustSigma = math.max(1.4826 * mad, 3.0);

    return BaselineSnapshot(
      medianHr: median,
      mad: mad,
      robustSigma: robustSigma,
      sampleCount: values.length,
    );
  }

  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first;
    final pos = p * (sorted.length - 1);
    final lower = pos.floor();
    final upper = pos.ceil();
    if (lower == upper) return sorted[lower];
    final weight = pos - lower;
    return sorted[lower] * (1 - weight) + sorted[upper] * weight;
  }

  /// Clear all stored baseline samples.
  void reset() {
    _samples.clear();
    _lastSeenTimestamp = null;
    _cachedSnapshot = null;
  }
}
