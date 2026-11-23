import '../../models/readiness_snapshot.dart';
import '../../models/sleep_session.dart';

/// Computes a WHOOP-style Ready Score (0–100%) from real synced telemetry:
/// - **Sleep Performance (45%)**: duration vs 8h target, efficiency, and deep+REM ratio.
/// - **Resting HR Recovery (30%)**: current baseline/resting HR vs 7-day rolling baseline.
/// - **Autonomic Calm (25%)**: live/latest Calm Score minus today's stress spike strain.
///
/// Weights automatically re-normalize across whichever components have genuine
/// ring data so partial syncs remain honest and transparent.
class ReadinessCalculator {
  ReadinessCalculator._();

  static const double _sleepWeight = 0.45;
  static const double _rhrWeight = 0.30;
  static const double _calmWeight = 0.25;

  static ReadinessSnapshot calculate({
    SleepSessionRecord? latestSleep,
    SleepAverages? sleepAverages,
    int? currentRestingHr,
    double? sevenDayAvgRestingHr,
    int? calmScore,
    int todayStressCount = 0,
    bool isLive = false,
    DateTime? lastSyncedAt,
    double? dailyAvgReadyScore,
  }) {
    final factors = <ReadinessFactor>[];

    // 1. Sleep Performance (45%)
    final hasSleep = latestSleep != null && latestSleep.totalSleepMinutes > 0;
    if (hasSleep) {
      final h = latestSleep.totalSleepMinutes ~/ 60;
      final m = latestSleep.totalSleepMinutes % 60;
      factors.add(
        ReadinessFactor(
          label: 'Sleep',
          displayValue: '${h}h ${m}m',
          score: latestSleep.sleepScore,
          weight: _sleepWeight,
          detail: '${latestSleep.efficiencyPercent}% eff · score ${latestSleep.sleepScore}',
          isAvailable: true,
        ),
      );
    } else {
      factors.add(
        const ReadinessFactor(
          label: 'Sleep',
          displayValue: '--',
          score: null,
          weight: _sleepWeight,
          detail: 'Sync sleep from ring',
          isAvailable: false,
        ),
      );
    }

    // 2. Resting HR Recovery (30%)
    if (currentRestingHr != null && currentRestingHr > 0) {
      final int rhrScore;
      final String rhrDetail;
      if (sevenDayAvgRestingHr != null && sevenDayAvgRestingHr > 0) {
        final delta = currentRestingHr - sevenDayAvgRestingHr;
        rhrScore = (78.0 - (delta * 4.5)).round().clamp(15, 100);
        final sign = delta >= 0 ? '+' : '';
        rhrDetail = '$sign${delta.toStringAsFixed(1)} vs 7d avg';
      } else {
        rhrScore = (100 - ((currentRestingHr - 55).clamp(0, 45) * 1.1))
            .round()
            .clamp(25, 95);
        rhrDetail = 'Baseline calibrated';
      }
      factors.add(
        ReadinessFactor(
          label: 'Resting HR',
          displayValue: '$currentRestingHr bpm',
          score: rhrScore,
          weight: _rhrWeight,
          detail: rhrDetail,
          isAvailable: true,
        ),
      );
    } else {
      factors.add(
        const ReadinessFactor(
          label: 'Resting HR',
          displayValue: '--',
          score: null,
          weight: _rhrWeight,
          detail: 'Awaiting HR baseline',
          isAvailable: false,
        ),
      );
    }

    // 3. Autonomic Calm / Strain Load (25%)
    if (calmScore != null) {
      final penalty = (todayStressCount * 8).clamp(0, 32);
      final calmFactorScore = (calmScore - penalty).clamp(0, 100);
      factors.add(
        ReadinessFactor(
          label: 'Calm',
          displayValue: '$calmScore',
          score: calmFactorScore,
          weight: _calmWeight,
          detail: todayStressCount == 0
              ? 'No stress spikes today'
              : '$todayStressCount ${todayStressCount == 1 ? 'spike' : 'spikes'} today',
          isAvailable: true,
        ),
      );
    } else {
      factors.add(
        const ReadinessFactor(
          label: 'Calm',
          displayValue: '--',
          score: null,
          weight: _calmWeight,
          detail: 'Connect ring for live calm',
          isAvailable: false,
        ),
      );
    }

    final available = factors.where((f) => f.isAvailable && f.score != null);
    final totalWeight = available.fold<double>(0.0, (sum, f) => sum + f.weight);

    if (totalWeight <= 0) {
      return ReadinessSnapshot(
        score: null,
        zone: ReadinessZone.uncalibrated,
        headline: 'Awaiting Ring Sync',
        guidance:
            'Connect your Colmi R02 smart ring to calibrate your resting baseline, sleep performance, and daily readiness.',
        factors: factors,
        isLive: isLive,
        lastSyncedAt: lastSyncedAt,
        dailyAvgReadyScore: dailyAvgReadyScore,
      );
    }

    final weightedSum = available.fold<double>(
      0.0,
      (sum, f) => sum + (f.score! * f.weight),
    );
    final readyScore = (weightedSum / totalWeight).round().clamp(0, 100);

    final ReadinessZone zone;
    final String headline;
    final String guidance;

    if (readyScore >= 67) {
      zone = ReadinessZone.peak;
      headline = 'Prime to Perform';
      guidance =
          'Your recovery signals are in the green. Strong capacity for deep focus, challenging meetings, and training.';
    } else if (readyScore >= 34) {
      zone = ReadinessZone.adequate;
      headline = 'Steady & Balanced';
      guidance =
          'Moderate recovery today. Pace demanding work blocks and build in brief breathing breaks between meetings.';
    } else {
      zone = ReadinessZone.rest;
      headline = 'Prioritize Recovery';
      guidance =
          'Elevated cardiovascular strain or limited sleep detected. Protect downtime and avoid unnecessary stressors today.';
    }

    // Compute multi-day average readiness if historical sleep is available
    double? computedAvgReady = dailyAvgReadyScore;
    if (computedAvgReady == null &&
        sleepAverages != null &&
        sleepAverages.nightsCount > 0) {
      computedAvgReady = sleepAverages.avgSleepScore;
    }

    return ReadinessSnapshot(
      score: readyScore,
      zone: zone,
      headline: headline,
      guidance: guidance,
      factors: factors,
      isLive: isLive,
      lastSyncedAt: lastSyncedAt,
      dailyAvgReadyScore: computedAvgReady,
    );
  }
}
