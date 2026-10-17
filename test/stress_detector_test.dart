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

      expect(filter.process(bpm: 30, timestamp: t0), isNull);
      expect(filter.process(bpm: 230, timestamp: t0), isNull);

      final s1 = filter.process(bpm: 70, timestamp: t0);
      expect(s1, isNotNull);
      expect(s1!.rawBpm, 70);

      // Jump of 50 BPM within 2 seconds exceeds maxSlewRatePerSec (6 BPM/s)
      final outlier = filter.process(
        bpm: 120,
        timestamp: t0.add(const Duration(seconds: 2)),
      );
      expect(outlier, isNull);

      // Realistic gradual increase succeeds
      final s2 = filter.process(
        bpm: 74,
        timestamp: t0.add(const Duration(seconds: 4)),
      );
      expect(s2, isNotNull);
    });
  });

  group('BaselineEstimator', () {
    test('freezes baseline during elevated stress so spikes do not raise resting HR', () {
      final estimator = BaselineEstimator();
      final t0 = DateTime(2026, 1, 1, 9, 0, 0);

      for (int i = 0; i < 15; i++) {
        estimator.update(
          bpm: 70.0 + (i % 3 - 1), // 69, 70, 71
          timestamp: t0.add(Duration(seconds: i * 10)),
          isElevated: false,
        );
      }

      final restingSnapshot = estimator.snapshot();
      expect(restingSnapshot.isCalibrated, isTrue);
      expect(restingSnapshot.medianBpm, closeTo(70.0, 1.0));

      // Feed high spike readings with isElevated: true
      for (int i = 0; i < 20; i++) {
        final snap = estimator.update(
          bpm: 115.0,
          timestamp: t0.add(Duration(minutes: 5, seconds: i * 10)),
          isElevated: true,
        );
        expect(snap.medianBpm, closeTo(70.0, 1.0));
      }
    });
  });

  group('StressScorer', () {
    test('computes elevated stress and lower calm score when HR is above baseline', () {
      const baseline = BaselineSnapshot(
        medianBpm: 68.0,
        madBpm: 2.0,
        robustSigma: 3.0,
        sampleCount: 20,
      );

      final calmResult = StressScorer.evaluate(
        smoothedBpm: 69.0,
        baseline: baseline,
      );
      expect(calmResult.isElevated, isFalse);
      expect(calmResult.calmScore, greaterThanOrEqualTo(80));

      final stressedResult = StressScorer.evaluate(
        smoothedBpm: 96.0,
        baseline: baseline,
      );
      expect(stressedResult.isElevated, isTrue);
      expect(stressedResult.stressScore, greaterThan(55.0));
      expect(stressedResult.calmScore, lessThan(50));
    });
  });

  group('StressDetector', () {
    test('detects 2-minute sustained spike, tolerates brief dip, and enforces cooldown', () {
      final detector = StressDetector(
        minEpisodeDuration: const Duration(minutes: 2),
        cooldownDuration: const Duration(minutes: 10),
      );
      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      // 1. Calibrate resting baseline around 68 BPM for 3 minutes (every 10s)
      for (int i = 0; i < 18; i++) {
        final out = detector.addMeasurement(
          bpm: 68 + (i % 3 - 1),
          timestamp: t0.add(Duration(seconds: i * 10)),
        );
        expect(out.detectedEpisode, isNull);
        expect(out.phase, StressPhase.calm);
      }

      // 2. Ramp up and sustain ~98 BPM for 130 seconds, including a brief 1-sample dip
      final spikeStart = t0.add(const Duration(minutes: 4));
      StressDetectorOutput? detectedOut;

      final pattern = <int>[
        78,
        88,
        96,
        98,
        99,
        97,
        71, // single transient dip (80% duty cycle should tolerate this)
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
      ];

      for (int i = 0; i < pattern.length; i++) {
        final out = detector.addMeasurement(
          bpm: pattern[i],
          timestamp: spikeStart.add(Duration(seconds: i * 10)),
        );
        if (out.detectedEpisode != null) {
          detectedOut = out;
          break;
        }
      }

      expect(detectedOut, isNotNull);
      expect(detectedOut!.phase, StressPhase.cooldown);
      expect(detectedOut.detectedEpisode!.peakBpm, greaterThanOrEqualTo(98));
      expect(detectedOut.detectedEpisode!.baselineBpm, closeTo(68.0, 2.0));
      expect(detectedOut.detectedEpisode!.durationSeconds, greaterThanOrEqualTo(120));

      // 3. During the 10-minute cooldown, further high readings do not emit duplicate episodes
      final cooldownStart = spikeStart.add(const Duration(minutes: 4));
      for (int i = 0; i < 15; i++) {
        final out = detector.addMeasurement(
          bpm: 99,
          timestamp: cooldownStart.add(Duration(seconds: i * 10)),
        );
        expect(out.detectedEpisode, isNull);
      }
    });
  });
}
