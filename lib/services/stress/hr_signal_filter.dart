import 'dart:collection';

/// A validated and smoothed heart rate sample emitted by [HrSignalFilter].
class CleanHrSample {
  final DateTime timestamp;
  final int rawHr;
  final double smoothedHr;

  const CleanHrSample({
    required this.timestamp,
    required this.rawHr,
    required this.smoothedHr,
  });
}

/// Pre-processes raw BLE heart rate readings to reject optical sensor
/// artifacts and smooth transient single-sample spikes.
///
/// Pipeline:
/// 1. Physiological range gate (`35..210` BPM).
/// 2. Slew-rate artifact gate (rejects instantaneous jumps `> 25 BPM/s`
///    when consecutive samples arrive within 5 seconds).
/// 3. Sliding 5-sample median filter over recent samples (`<= 15s` old).
class HrSignalFilter {
  static const int minValidHr = 35;
  static const int maxValidHr = 210;
  static const double maxSlewBpmPerSec = 25.0;
  static const int medianWindowSize = 5;
  static const Duration medianMaxAge = Duration(seconds: 15);

  final Queue<({DateTime timestamp, int hr})> _recentWindow = Queue();
  DateTime? _lastAcceptedTime;
  int? _lastAcceptedHr;

  /// Process a raw BPM value at [timestamp].
  ///
  /// Returns a [CleanHrSample] if valid, or `null` if rejected as an artifact.
  CleanHrSample? process(int rawHr, {DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();

    // 1. Physiological bounds check
    if (rawHr < minValidHr || rawHr > maxValidHr) {
      return null;
    }

    // 2. Slew-rate jump rejection for back-to-back optical glitches
    if (_lastAcceptedTime != null && _lastAcceptedHr != null) {
      final dtMs = now.difference(_lastAcceptedTime!).inMilliseconds;
      if (dtMs > 0 && dtMs <= 5000) {
        final dtSec = dtMs / 1000.0;
        final jump = (rawHr - _lastAcceptedHr!).abs();
        // Allow at least 18 BPM step for 1 Hz sampling, or 25 BPM/s
        final maxAllowedJump = (maxSlewBpmPerSec * dtSec).clamp(18.0, 60.0);
        if (jump > maxAllowedJump) {
          return null;
        }
      }
    }

    _lastAcceptedTime = now;
    _lastAcceptedHr = rawHr;

    // 3. Maintain recent window for 5-sample median smoothing
    final cutoff = now.subtract(medianMaxAge);
    while (_recentWindow.isNotEmpty &&
        _recentWindow.first.timestamp.isBefore(cutoff)) {
      _recentWindow.removeFirst();
    }
    _recentWindow.add((timestamp: now, hr: rawHr));
    while (_recentWindow.length > medianWindowSize) {
      _recentWindow.removeFirst();
    }

    final sorted = _recentWindow.map((e) => e.hr).toList()..sort();
    final mid = sorted.length ~/ 2;
    final smoothed = sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2.0;

    return CleanHrSample(
      timestamp: now,
      rawHr: rawHr,
      smoothedHr: smoothed,
    );
  }

  /// Reset filter state.
  void reset() {
    _recentWindow.clear();
    _lastAcceptedTime = null;
    _lastAcceptedHr = null;
  }
}
