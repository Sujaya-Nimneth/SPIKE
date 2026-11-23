import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ring/models/readiness_snapshot.dart';
import 'package:smart_ring/models/sleep_session.dart';
import 'package:smart_ring/services/readiness/readiness_calculator.dart';

void main() {
  group('ReadinessCalculator', () {
    test('returns uncalibrated when no telemetry is available', () {
      final snap = ReadinessCalculator.calculate();

      expect(snap.score, isNull);
      expect(snap.zone, ReadinessZone.uncalibrated);
      expect(snap.factors.every((f) => !f.isAvailable), isTrue);
    });

    test('computes Peak Recovery zone for strong sleep, low RHR, and calm state', () {
      final sleep = SleepSessionRecord(
        date: '2026-11-24',
        totalSleepMinutes: 465,
        timeInBedMinutes: 485,
        awakeMinutes: 20,
        lightMinutes: 240,
        deepMinutes: 120,
        remMinutes: 105,
        efficiencyPercent: 96,
        sleepScore: 92,
        restingHr: 54,
        syncedAt: DateTime(2026, 11, 24, 7, 30),
      );

      final snap = ReadinessCalculator.calculate(
        latestSleep: sleep,
        currentRestingHr: 54,
        sevenDayAvgRestingHr: 58.0,
        calmScore: 92,
        todayStressCount: 0,
        isLive: true,
      );

      expect(snap.score, isNotNull);
      expect(snap.score!, greaterThanOrEqualTo(67));
      expect(snap.zone, ReadinessZone.peak);
      expect(snap.factors.where((f) => f.isAvailable).length, 3);
    });

    test('computes Rest zone for short fragmented sleep, elevated RHR, and stress spikes', () {
      final sleep = SleepSessionRecord(
        date: '2026-11-24',
        totalSleepMinutes: 210,
        timeInBedMinutes: 300,
        awakeMinutes: 90,
        lightMinutes: 160,
        deepMinutes: 30,
        remMinutes: 20,
        efficiencyPercent: 70,
        sleepScore: 32,
        restingHr: 74,
        syncedAt: DateTime(2026, 11, 24, 6, 30),
      );

      final snap = ReadinessCalculator.calculate(
        latestSleep: sleep,
        currentRestingHr: 74,
        sevenDayAvgRestingHr: 60.0,
        calmScore: 40,
        todayStressCount: 4,
        isLive: false,
      );

      expect(snap.score, isNotNull);
      expect(snap.score!, lessThan(34));
      expect(snap.zone, ReadinessZone.rest);
    });

    test('renormalizes weights when only partial telemetry (HR only) exists', () {
      final snap = ReadinessCalculator.calculate(
        currentRestingHr: 62,
        sevenDayAvgRestingHr: 62.0,
      );

      expect(snap.score, 78);
      expect(snap.zone, ReadinessZone.peak);
      expect(snap.factors.where((f) => f.isAvailable).length, 1);
    });
  });
}
