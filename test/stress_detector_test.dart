import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ring/services/stress/baseline_estimator.dart';
import 'package:smart_ring/services/stress/hr_signal_filter.dart';
import 'package:smart_ring/services/stress/stress_detector.dart';
import 'package:smart_ring/services/stress/stress_scorer.dart';

void main() {
  group('HrSignalFilter', () {
    test('rejects out-of-range physiological readings and sudden slew-rate outliers', () {
      final filter = HrSignalFilter();
      final t0 = DateTime(2026, 1, 1, 9, 0, 0);

      expect(filter.process(30, timestamp: t0), isNull);
      expect(filter.process(230, timestamp: t0), isNull);

      final s1 = filter.process(70, timestamp: t0);
      expect(s1, isNotNull);
      expect(s1!.rawHr, 70);

      // Jump of 60 BPM within 2 seconds exceeds maxAllowedJump (50 BPM)
      final outlier = filter.process(
        130,
        timestamp: t0.add(const Duration(seconds: 2)),
      );
      expect(outlier, isNull);

      // Realistic gradual increase succeeds
      final s2 = filter.process(
        74,
        timestamp: t0.add(const Duration(seconds: 4)),
      );
      expect(s2, isNotNull);
    });
  });

  group('BaselineEstimator', () {
    test('freezes baseline during elevated stress so spikes do not raise resting HR', () {
      final estimator = BaselineEstimator(minSamplesToReady: 15);
      final t0 = DateTime(2026, 1, 1, 9, 0, 0);

      for (int i = 0; i < 15; i++) {
        final ts = t0.add(Duration(seconds: i * 10));
        final bpm = 70.0 + (i % 3 - 1);
        estimator.addSample(
          CleanHrSample(timestamp: ts, rawHr: bpm.round(), smoothedHr: bpm),
          isElevated: false,
        );
      }

      expect(estimator.isReady, isTrue);
      final restingSnapshot = estimator.current!;
      expect(restingSnapshot.medianHr, closeTo(70.0, 1.0));

      // Feed high spike readings with isElevated: true
      for (int i = 0; i < 20; i++) {
        final ts = t0.add(Duration(minutes: 5, seconds: i * 10));
        estimator.addSample(
          CleanHrSample(timestamp: ts, rawHr: 115, smoothedHr: 115.0),
          isElevated: true,
        );
        expect(estimator.current!.medianHr, closeTo(70.0, 1.0));
      }
    });
  });

  group('StressScorer', () {
    test('computes elevated stress and lower calm score when HR is above baseline', () {
      final scorer = StressScorer();
      const baseline = BaselineSnapshot(
        medianHr: 68.0,
        mad: 2.0,
        robustSigma: 3.0,
        sampleCount: 20,
      );

      final calmResult = scorer.evaluate(69.0, baseline);
      expect(calmResult.isAboveEntryThreshold, isFalse);
      expect(calmResult.calmScore, greaterThanOrEqualTo(80));

      StressSampleScore? stressedResult;
      for (int i = 0; i < 15; i++) {
        stressedResult = scorer.evaluate(96.0, baseline);
      }
      expect(stressedResult!.isAboveEntryThreshold, isTrue);
      expect(stressedResult.instantStressScore, greaterThan(55.0));
      expect(stressedResult.calmScore, lessThan(50));
    });
  });

  group('StressDetector', () {
    test('detects 2-minute sustained spike, tolerates brief dip, and enforces cooldown', () {
      final detector = StressDetector(
        spikeDuration: const Duration(minutes: 2),
        cooldownDuration: const Duration(minutes: 10),
        recoveryWindow: const Duration(seconds: 30),
      );
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      // 1. Calibrate resting baseline around 68 BPM for ~3.5 minutes (20 samples)
      for (int i = 0; i < 20; i++) {
        final ep = detector.processSample(
          68 + (i % 3 - 1),
          timestamp: t0.add(Duration(seconds: i * 10)),
        );
        expect(ep, isNull);
      }
      expect(detector.phase, StressDetectionPhase.calm);

      // 2. Ramp up and sustain ~98 BPM for >= 120s, including a brief 1-sample dip
      final spikeStart = t0.add(const Duration(minutes: 4));
      DetectedStressEpisode? detected;

      final pattern = <int>[
        78,
        88,
        96,
        98,
        99,
        97,
        71, // single transient dip (80% duty cycle tolerates this)
        98,
        99,
        100,
        99,
        98,
        99,
        100,
        99,
        98,
        99,
        99,
      ];

      for (int i = 0; i < pattern.length; i++) {
        final ep = detector.processSample(
          pattern[i],
          timestamp: spikeStart.add(Duration(seconds: i * 10)),
        );
        if (ep != null) {
          detected = ep;
          break;
        }
      }

      expect(detected, isNotNull);
      expect(detector.phase, StressDetectionPhase.stressed);
      expect(detected!.peakHr, greaterThanOrEqualTo(98));
      expect(detected.baselineHr, closeTo(68, 2));
      expect(detected.durationSeconds, greaterThanOrEqualTo(120));

      // 3. Recover briefly then re-spike within cooldown -> should NOT emit duplicate episode
      final recoveryStart = spikeStart.add(const Duration(minutes: 4));
      for (int i = 0; i < 6; i++) {
        final ep = detector.processSample(
          68,
          timestamp: recoveryStart.add(Duration(seconds: i * 10)),
        );
        expect(ep, isNull);
      }

      final secondSpikeStart = recoveryStart.add(const Duration(minutes: 1, seconds: 10));
      for (int i = 0; i < 16; i++) {
        final ep = detector.processSample(
          99,
          timestamp: secondSpikeStart.add(Duration(seconds: i * 10)),
        );
        expect(ep, isNull);
      }
    });

    test('resets to warmingUp after >10m gap and emits completed metrics on recovery', () {
      final detector = StressDetector(
        spikeDuration: const Duration(minutes: 2),
        cooldownDuration: const Duration(minutes: 5),
        recoveryWindow: const Duration(seconds: 30),
      );
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      // Calibrate baseline ~68 BPM
      for (int i = 0; i < 20; i++) {
        detector.processSample(68, timestamp: t0.add(Duration(seconds: i * 10)));
      }
      expect(detector.phase, StressDetectionPhase.calm);

      // Start spike at t0 + 4m; hits 2-min mark at ~t0 + 6m with peak 98
      final spikeStart = t0.add(const Duration(minutes: 4));
      DetectedStressEpisode? started;
      for (int i = 0; i <= 12; i++) {
        final res = detector.processSampleWithLifecycle(
          98,
          timestamp: spikeStart.add(Duration(seconds: i * 10)),
        );
        started ??= res.started;
      }
      expect(started, isNotNull);
      expect(started!.peakHr, 98);

      // Peak climbs to 112 BPM while stressed
      for (int i = 13; i <= 18; i++) {
        detector.processSampleWithLifecycle(
          112,
          timestamp: spikeStart.add(Duration(seconds: i * 10)),
        );
      }

      // Recover back to 68 BPM for >= recoveryWindow (30s)
      final recStart = spikeStart.add(const Duration(minutes: 3, seconds: 10));
      DetectedStressEpisode? completed;
      for (int i = 0; i <= 4; i++) {
        final res = detector.processSampleWithLifecycle(
          68,
          timestamp: recStart.add(Duration(seconds: i * 10)),
        );
        completed ??= res.completed;
      }

      expect(completed, isNotNull);
      expect(completed!.peakHr, 112);
      expect(completed.durationSeconds, greaterThanOrEqualTo(220));
      expect(detector.phase, StressDetectionPhase.calm);

      // Gap > 10 minutes flushes baseline -> must revert to warmingUp
      final afterLongGap = recStart.add(const Duration(minutes: 15));
      detector.processSampleWithLifecycle(70, timestamp: afterLongGap);
      expect(detector.phase, StressDetectionPhase.warmingUp);
      expect(detector.baselineEstimator.isReady, isFalse);
    });
  });

  group('BaselineEstimator prolonged freeze', () {
    test('allows baseline re-anchoring after maxContinuousFreezeDuration', () {
      final estimator = BaselineEstimator(
        minSamplesToReady: 5,
        maxContinuousFreezeDuration: const Duration(minutes: 30),
      );
      final t0 = DateTime(2026, 1, 1, 9, 0, 0);

      for (int i = 0; i < 5; i++) {
        estimator.addSample(
          CleanHrSample(
            timestamp: t0.add(Duration(seconds: i * 10)),
            rawHr: 65,
            smoothedHr: 65.0,
          ),
          isElevated: false,
        );
      }
      expect(estimator.current!.medianHr, 65.0);

      // Elevated for 36 minutes after freeze begins at m=5 (samples every 5m stay <= 10m gap)
      for (int m = 5; m <= 40; m += 5) {
        estimator.addSample(
          CleanHrSample(
            timestamp: t0.add(Duration(minutes: m)),
            rawHr: 92,
            smoothedHr: 92.0,
          ),
          isElevated: true,
        );
      }
      // After >30m continuous freeze, new samples are allowed into the window
      expect(estimator.current!.medianHr, greaterThan(65.0));
    });
  });
}
