import 'dart:collection';
import 'dart:math' as math;
import 'baseline_estimator.dart';
import 'hr_signal_filter.dart';
import 'stress_scorer.dart';

/// Phases of the v2 stress detection state machine.
enum StressDetectionPhase {
  /// Collecting initial baseline samples.
  warmingUp,

  /// Normal resting/calm state.
  calm,

  /// HR has crossed the entry threshold; confirming sustained elevation.
  elevated,

  /// Sustained stress episode confirmed (>= 2 minutes with >= 80% duty cycle).
  stressed,

  /// HR has dipped below hysteresis exit; waiting to confirm full recovery.
  recovering,
}

/// Summary of a detected stress episode.
class DetectedStressEpisode {
  final DateTime startTime;
  final DateTime timestamp;
  final int peakHr;
  final int meanHr;
  final int baselineHr;
  final int durationSeconds;
  final double stressLoad;

  const DetectedStressEpisode({
    required this.startTime,
    required this.timestamp,
    required this.peakHr,
    required this.meanHr,
    required this.baselineHr,
    required this.durationSeconds,
    required this.stressLoad,
  });
}

/// Deterministic, pure-Dart state machine that connects [HrSignalFilter],
/// [BaselineEstimator], and [StressScorer] to detect sustained stress episodes.
class StressDetector {
  final HrSignalFilter signalFilter;
  final BaselineEstimator baselineEstimator;
  final StressScorer scorer;

  /// Required duration of sustained elevation before confirming an episode.
  final Duration spikeDuration;

  /// Minimum fraction of samples during [spikeDuration] that must stay above
  /// the hysteresis exit threshold (tolerates brief 1-2 sample dips).
  final double minConfirmationDutyCycle;

  /// Cooldown between consecutive stress event triggers.
  final Duration cooldownDuration;

  /// Maximum gap before an active elevation is reset (baseline is still kept
  /// unless gap exceeds [BaselineEstimator.maxGapBeforeFlush]).
  final Duration maxActiveSpikeGap;

  /// Duration HR must stay below exit threshold to close an active episode.
  final Duration recoveryWindow;

  StressDetector({
    HrSignalFilter? signalFilter,
    BaselineEstimator? baselineEstimator,
    StressScorer? scorer,
    this.spikeDuration = const Duration(minutes: 2),
    this.minConfirmationDutyCycle = 0.80,
    this.cooldownDuration = const Duration(minutes: 5),
    this.maxActiveSpikeGap = const Duration(seconds: 30),
    this.recoveryWindow = const Duration(seconds: 45),
  })  : signalFilter = signalFilter ?? HrSignalFilter(),
        baselineEstimator = baselineEstimator ?? BaselineEstimator(),
        scorer = scorer ?? StressScorer();

  StressDetectionPhase _phase = StressDetectionPhase.warmingUp;
  DateTime? _lastSampleTime;
  DateTime? _episodeStartTime;
  DateTime? _recoveryStartTime;
  DateTime? _lastTriggeredAt;

  int _episodePeakHr = 0;
  double _episodeHrSum = 0;
  int _episodeSampleCount = 0;
  double _episodeStressLoad = 0;
  bool _episodeAlreadyEmitted = false;

  /// Tracks recent samples during an active elevation to compute duty cycle.
  final Queue<({DateTime timestamp, bool aboveExit})> _elevationSamples =
      Queue();

  // ── Getters ─────────────────────────────────────────────────

  StressDetectionPhase get phase => _phase;

  double? get currentBaseline => baselineEstimator.current?.medianHr;

  int get calmScore => scorer.calmScore;

  bool get isSpiking =>
      _phase == StressDetectionPhase.elevated ||
      _phase == StressDetectionPhase.stressed ||
      _phase == StressDetectionPhase.recovering;

  /// Process a single heart rate reading at [timestamp].
  ///
  /// Returns a [DetectedStressEpisode] at the moment a new episode is confirmed,
  /// or `null` otherwise.
  DetectedStressEpisode? processSample(int rawHr, {DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();

    // Check for connection gap that invalidates an in-progress spike timer
    if (_lastSampleTime != null &&
        now.difference(_lastSampleTime!) > maxActiveSpikeGap) {
      _resetEpisodeTracking();
      if (!baselineEstimator.isReady) {
        _phase = StressDetectionPhase.warmingUp;
      } else {
        _phase = StressDetectionPhase.calm;
      }
    }
    _lastSampleTime = now;

    // 1. Filter optical glitches and smooth with 5-sample median
    final clean = signalFilter.process(rawHr, timestamp: now);
    if (clean == null) return null;

    // 2. If baseline is not yet ready, accumulate warm-up samples
    if (!baselineEstimator.isReady) {
      baselineEstimator.addSample(clean, isElevated: false);
      if (baselineEstimator.isReady) {
        _phase = StressDetectionPhase.calm;
      }
      return null;
    }

    // 3. Score against the current frozen/unfrozen baseline
    final baseline = baselineEstimator.current!;
    final score = scorer.evaluate(clean.smoothedHr, baseline);

    // Freeze baseline updates whenever HR is above the exit threshold or in an episode
    final freezeBaseline = isSpiking || score.isAboveExitThreshold;
    baselineEstimator.addSample(clean, isElevated: freezeBaseline);

    // 4. Advance episode state machine
    switch (_phase) {
      case StressDetectionPhase.warmingUp:
        _phase = StressDetectionPhase.calm;
        return null;

      case StressDetectionPhase.calm:
        if (score.isAboveEntryThreshold) {
          _startEpisode(now, rawHr, score.zScore);
          _phase = StressDetectionPhase.elevated;
        }
        return null;

      case StressDetectionPhase.elevated:
        _accumulateEpisodeSample(now, rawHr, score);

        // Evaluate duty cycle in the confirmation window
        final dutyCycle = _currentDutyCycle();
        final elapsed = now.difference(_episodeStartTime!);

        // If HR dropped well below exit threshold and duty cycle fell below minimum
        if (!score.isAboveExitThreshold &&
            elapsed >= const Duration(seconds: 15) &&
            dutyCycle < minConfirmationDutyCycle) {
          _resetEpisodeTracking();
          _phase = StressDetectionPhase.calm;
          return null;
        }

        // Check if spike has been sustained for >= spikeDuration with >= 80% duty cycle
        if (elapsed >= spikeDuration && dutyCycle >= minConfirmationDutyCycle) {
          _phase = StressDetectionPhase.stressed;
          return _maybeEmitConfirmedEpisode(now, baseline.medianHr);
        }
        return null;

      case StressDetectionPhase.stressed:
        _accumulateEpisodeSample(now, rawHr, score);
        if (!score.isAboveExitThreshold) {
          _recoveryStartTime = now;
          _phase = StressDetectionPhase.recovering;
        }
        return null;

      case StressDetectionPhase.recovering:
        _accumulateEpisodeSample(now, rawHr, score);
        if (score.isAboveExitThreshold) {
          // Re-elevated within the merge window -> continues same episode
          _recoveryStartTime = null;
          _phase = StressDetectionPhase.stressed;
          return null;
        }
        if (_recoveryStartTime != null &&
            now.difference(_recoveryStartTime!) >= recoveryWindow) {
          // Fully recovered -> close episode and return to calm
          _resetEpisodeTracking();
          _phase = StressDetectionPhase.calm;
        }
        return null;
    }
  }

  void _startEpisode(DateTime now, int rawHr, double zScore) {
    _episodeStartTime = now;
    _recoveryStartTime = null;
    _episodePeakHr = rawHr;
    _episodeHrSum = rawHr.toDouble();
    _episodeSampleCount = 1;
    _episodeStressLoad = math.max(0.0, zScore) / 60.0;
    _episodeAlreadyEmitted = false;
    _elevationSamples
      ..clear()
      ..add((timestamp: now, aboveExit: true));
  }

  void _accumulateEpisodeSample(
    DateTime now,
    int rawHr,
    StressSampleScore score,
  ) {
    if (rawHr > _episodePeakHr) {
      _episodePeakHr = rawHr;
    }
    _episodeHrSum += rawHr;
    _episodeSampleCount++;
    _episodeStressLoad += math.max(0.0, score.zScore) / 60.0;

    _elevationSamples.add(
      (timestamp: now, aboveExit: score.isAboveExitThreshold),
    );
    final cutoff = now.subtract(spikeDuration);
    while (_elevationSamples.isNotEmpty &&
        _elevationSamples.first.timestamp.isBefore(cutoff)) {
      _elevationSamples.removeFirst();
    }
  }

  double _currentDutyCycle() {
    if (_elevationSamples.isEmpty) return 0.0;
    final activeCount = _elevationSamples.where((s) => s.aboveExit).length;
    return activeCount / _elevationSamples.length;
  }

  DetectedStressEpisode? _maybeEmitConfirmedEpisode(
    DateTime now,
    double baselineHr,
  ) {
    if (_episodeAlreadyEmitted) return null;
    _episodeAlreadyEmitted = true;

    if (_lastTriggeredAt != null &&
        now.difference(_lastTriggeredAt!) < cooldownDuration) {
      return null;
    }

    _lastTriggeredAt = now;
    final start = _episodeStartTime ?? now.subtract(spikeDuration);
    final durationSecs = math.max(
      now.difference(start).inSeconds,
      spikeDuration.inSeconds,
    );
    final meanHr = _episodeSampleCount > 0
        ? (_episodeHrSum / _episodeSampleCount).round()
        : _episodePeakHr;

    return DetectedStressEpisode(
      startTime: start,
      timestamp: now,
      peakHr: _episodePeakHr,
      meanHr: meanHr,
      baselineHr: baselineHr.round(),
      durationSeconds: durationSecs,
      stressLoad: double.parse(_episodeStressLoad.toStringAsFixed(2)),
    );
  }

  void _resetEpisodeTracking() {
    _episodeStartTime = null;
    _recoveryStartTime = null;
    _episodePeakHr = 0;
    _episodeHrSum = 0;
    _episodeSampleCount = 0;
    _episodeStressLoad = 0;
    _episodeAlreadyEmitted = false;
    _elevationSamples.clear();
  }

  /// Reset the entire detector state including baseline and signal filter.
  void reset() {
    signalFilter.reset();
    baselineEstimator.reset();
    scorer.reset();
    _resetEpisodeTracking();
    _phase = StressDetectionPhase.warmingUp;
    _lastSampleTime = null;
    _lastTriggeredAt = null;
  }
}
