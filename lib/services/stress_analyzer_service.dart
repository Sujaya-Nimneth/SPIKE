import 'dart:async';
import 'dart:collection';
import '../models/stress_event.dart';
import 'calendar_service.dart';
import 'database_service.dart';

/// Analyzes heart rate data to detect stress events and correlate them
/// with active calendar meetings.
///
/// Algorithm:
/// 1. Maintains a rolling 5-minute window of HR samples (baseline).
/// 2. If current HR ≥ baseline × 1.25 for ≥ 2 consecutive minutes,
///    flags a "Stress Event".
/// 3. Queries the device calendar for the currently active meeting.
/// 4. Saves the event (timestamp, peak HR, meeting, attendees) to SQLite.
class StressAnalyzerService {
  final CalendarService _calendarService;
  final DatabaseService _databaseService;

  StressAnalyzerService({
    required CalendarService calendarService,
    required DatabaseService databaseService,
  })  : _calendarService = calendarService,
        _databaseService = databaseService;

  // ── Configuration ───────────────────────────────────────────

  /// Duration of the rolling baseline window.
  static const baselineWindow = Duration(minutes: 5);

  /// Spike threshold: current HR must be ≥ baseline × this factor.
  static const spikeThreshold = 1.25;

  /// How long the spike must be sustained before triggering an event.
  static const spikeDuration = Duration(minutes: 2);

  /// Cooldown period after a stress event before a new one can fire.
  static const cooldownDuration = Duration(minutes: 5);

  /// Maximum gap between samples before flushing the baseline buffer.
  /// If no HR sample arrives within this duration, the ring likely
  /// disconnected and the baseline data is stale.
  static const maxSampleGap = Duration(seconds: 10);

  // ── State ───────────────────────────────────────────────────

  /// Circular buffer of (timestamp, hr) pairs for rolling baseline.
  final Queue<_HrSample> _baselineBuffer = Queue();

  /// When the current spike started (null = no active spike).
  DateTime? _spikeStartTime;

  /// Peak HR observed during the current spike.
  int _currentPeakHr = 0;

  /// When the last stress event was recorded (for cooldown).
  DateTime? _lastEventTime;

  /// Stream controller for emitting stress events to the UI.
  final _eventController = StreamController<StressEvent>.broadcast();

  /// Whether the analyzer is actively processing HR data.
  bool _isRunning = false;

  /// Reentrance guard to prevent duplicate stress events.
  ///
  /// Since `_triggerStressEvent` is async (awaits calendar + DB) but
  /// `_onHeartRateReceived` is called synchronously on each HR sample,
  /// without this guard the trigger could fire multiple times while
  /// the first invocation is still in-flight.
  bool _isTriggering = false;

  StreamSubscription<int>? _hrSubscription;

  // ── Public API ──────────────────────────────────────────────

  /// Stream of detected stress events.
  Stream<StressEvent> get stressEventStream => _eventController.stream;

  /// Whether the analyzer is currently running.
  bool get isRunning => _isRunning;

  /// The current rolling baseline HR, or null if insufficient data.
  double? get currentBaseline {
    if (_baselineBuffer.isEmpty) return null;
    final sum = _baselineBuffer.fold<int>(0, (s, sample) => s + sample.hr);
    return sum / _baselineBuffer.length;
  }

  /// Whether a spike is currently being tracked.
  bool get isSpiking => _spikeStartTime != null;

  /// Start listening to a heart rate stream.
  void start(Stream<int> heartRateStream) {
    if (_isRunning) return;
    _isRunning = true;

    _hrSubscription = heartRateStream.listen(
      _onHeartRateReceived,
      onError: (_) {}, // Silently ignore stream errors
    );
  }

  /// Stop the analyzer and clean up.
  void stop() {
    _isRunning = false;
    _hrSubscription?.cancel();
    _hrSubscription = null;
  }

  /// Dispose of all resources.
  void dispose() {
    stop();
    _eventController.close();
    _baselineBuffer.clear();
  }

  // ── Core Algorithm ──────────────────────────────────────────

  void _onHeartRateReceived(int hr) {
    final now = DateTime.now();

    // Detect connection gaps: if last sample was >10 seconds ago,
    // the ring likely disconnected. Flush the buffer to prevent
    // stale data from poisoning the baseline.
    if (_baselineBuffer.isNotEmpty) {
      final lastSampleTime = _baselineBuffer.last.timestamp;
      if (now.difference(lastSampleTime) > maxSampleGap) {
        _baselineBuffer.clear();
        _spikeStartTime = null;
        _currentPeakHr = 0;
      }
    }

    // 1. Add to baseline buffer
    _baselineBuffer.add(_HrSample(timestamp: now, hr: hr));

    // 2. Trim samples outside the 5-minute window
    final cutoff = now.subtract(baselineWindow);
    while (_baselineBuffer.isNotEmpty &&
        _baselineBuffer.first.timestamp.isBefore(cutoff)) {
      _baselineBuffer.removeFirst();
    }

    // 3. Need at least 30 seconds of data for a meaningful baseline
    if (_baselineBuffer.length < 30) return;

    // 4. Calculate rolling average (baseline)
    final baseline = currentBaseline!;

    // 5. Check if current HR is a spike (≥ 25% above baseline)
    final threshold = baseline * spikeThreshold;

    if (hr >= threshold) {
      // Spike detected — start or continue tracking
      _spikeStartTime ??= now;
      if (hr > _currentPeakHr) _currentPeakHr = hr;

      // 6. Check if spike has been sustained for ≥ 2 minutes
      //    AND no trigger is currently in-flight (reentrance guard)
      final spikeElapsed = now.difference(_spikeStartTime!);
      if (spikeElapsed >= spikeDuration && !_isTriggering) {
        _triggerStressEvent(now, baseline);
      }
    } else {
      // HR dropped below threshold — reset spike tracking
      _spikeStartTime = null;
      _currentPeakHr = 0;
    }
  }

  /// Trigger a stress event: query calendar, save to DB, emit to stream.
  ///
  /// Protected by [_isTriggering] reentrance guard to prevent duplicate
  /// events when multiple HR samples arrive while the async calendar
  /// query and DB insert are in-flight.
  Future<void> _triggerStressEvent(DateTime now, double baseline) async {
    if (_isTriggering) return;
    _isTriggering = true;

    try {
      // Cooldown check: don't fire again within 5 minutes
      if (_lastEventTime != null &&
          now.difference(_lastEventTime!) < cooldownDuration) {
        return;
      }

      _lastEventTime = now;

      // Query the calendar for the active meeting(s)
      String? meetingTitle;
      List<String> attendees = [];

      try {
        final meeting = await _calendarService.getCurrentMeeting();
        if (meeting != null) {
          meetingTitle = meeting.title;
          attendees = meeting.attendees;
        }
      } catch (_) {
        // Calendar access might fail — continue without meeting info
      }

      // Calculate spike duration
      final duration = _spikeStartTime != null
          ? now.difference(_spikeStartTime!).inSeconds
          : spikeDuration.inSeconds;

      // Build the stress event
      final event = StressEvent(
        timestamp: now,
        peakHr: _currentPeakHr,
        baselineHr: baseline.round(),
        meetingTitle: meetingTitle,
        attendees: attendees,
        durationSeconds: duration,
      );

      // Save to SQLite
      try {
        await _databaseService.insertStressEvent(event);
      } catch (_) {
        // DB write failure shouldn't crash the analyzer
      }

      // Emit to the stream for UI (guard against closed controller)
      if (!_eventController.isClosed) {
        _eventController.add(event);
      }
    } finally {
      // Always release the reentrance guard and reset spike tracking
      _isTriggering = false;
      _spikeStartTime = null;
      _currentPeakHr = 0;
    }
  }
}

/// A single heart rate sample with its timestamp.
class _HrSample {
  final DateTime timestamp;
  final int hr;

  const _HrSample({required this.timestamp, required this.hr});
}
