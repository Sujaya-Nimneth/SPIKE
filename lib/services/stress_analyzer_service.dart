import 'dart:async';
import '../models/stress_event.dart';
import '../utils/app_logger.dart';
import 'calendar_service.dart';
import 'database_service.dart';
import 'stress/stress_detector.dart';

/// Orchestrates real-time heart rate stress analysis using the v2
/// [StressDetector] pipeline and persists detected episodes to [DatabaseService].
///
/// Pipeline:
/// 1. [HrSignalFilter]: range validation (35–210 BPM), slew-rate artifact
///    rejection, and 5-sample median smoothing.
/// 2. [BaselineEstimator]: 10-minute rolling median + MAD baseline that
///    freezes updates during elevated HR so spikes never self-contaminate.
/// 3. [StressScorer]: z-score + ratio evaluation and EMA-smoothed Calm Score.
/// 4. [StressDetector]: hysteresis state machine requiring >= 80% elevated
///    duty cycle over 2 minutes before confirming a stress episode.
class StressAnalyzerService {
  static const _tag = 'StressAnalyzer';

  final CalendarService _calendarService;
  final DatabaseService _databaseService;
  final StressDetector _detector;

  StressAnalyzerService({
    required CalendarService calendarService,
    required DatabaseService databaseService,
    StressDetector? detector,
  })  : _calendarService = calendarService,
        _databaseService = databaseService,
        _detector = detector ?? StressDetector();

  final _eventController = StreamController<StressEvent>.broadcast();
  final _calmScoreController = StreamController<int>.broadcast();
  final _phaseController = StreamController<StressDetectionPhase>.broadcast();

  bool _isRunning = false;
  bool _isTriggering = false;
  int _lastEmittedCalmScore = 88;
  StressDetectionPhase _lastEmittedPhase = StressDetectionPhase.warmingUp;

  StreamSubscription<int>? _hrSubscription;

  // ── Public API ──────────────────────────────────────────────

  /// Stream of newly detected and persisted stress events.
  Stream<StressEvent> get stressEventStream => _eventController.stream;

  /// Stream of live Calm Score updates (0–100, default 88).
  Stream<int> get calmScoreStream => _calmScoreController.stream;

  /// Stream of detector phase transitions.
  Stream<StressDetectionPhase> get phaseStream => _phaseController.stream;

  /// Whether the analyzer is actively subscribed to a heart rate stream.
  bool get isRunning => _isRunning;

  /// Current rolling median baseline HR, or `null` while warming up.
  double? get currentBaseline => _detector.currentBaseline;

  /// Current smoothed Calm Score (0–100).
  int get currentCalmScore => _detector.calmScore;

  /// Current phase of the stress detector state machine.
  StressDetectionPhase get currentPhase => _detector.phase;

  /// Whether an elevation or confirmed spike is currently active.
  bool get isSpiking => _detector.isSpiking;

  /// Start listening to a heart rate stream.
  void start(Stream<int> heartRateStream) {
    if (_isRunning) return;
    _isRunning = true;

    _hrSubscription = heartRateStream.listen(
      _onHeartRateReceived,
      onError: (Object err) {
        AppLogger.warn(_tag, 'HR stream error', err);
      },
    );
  }

  /// Stop the analyzer subscription.
  void stop() {
    _isRunning = false;
    _hrSubscription?.cancel();
    _hrSubscription = null;
  }

  /// Dispose of all resources.
  void dispose() {
    stop();
    _eventController.close();
    _calmScoreController.close();
    _phaseController.close();
  }

  // ── Core Processing ─────────────────────────────────────────

  void _onHeartRateReceived(int hr) {
    final episode = _detector.processSample(hr);

    // Broadcast Calm Score changes
    final newCalm = _detector.calmScore;
    if (newCalm != _lastEmittedCalmScore && !_calmScoreController.isClosed) {
      _lastEmittedCalmScore = newCalm;
      _calmScoreController.add(newCalm);
    }

    // Broadcast phase transitions
    final newPhase = _detector.phase;
    if (newPhase != _lastEmittedPhase && !_phaseController.isClosed) {
      _lastEmittedPhase = newPhase;
      _phaseController.add(newPhase);
    }

    if (episode != null && !_isTriggering) {
      unawaited(_persistDetectedEpisode(episode));
    }
  }

  Future<void> _persistDetectedEpisode(DetectedStressEpisode episode) async {
    if (_isTriggering) return;
    _isTriggering = true;

    try {
      String? meetingTitle;
      List<String> attendees = [];

      try {
        final meeting = await _calendarService.getCurrentMeeting();
        if (meeting != null) {
          meetingTitle = meeting.title;
          attendees = meeting.attendees;
        }
      } catch (e) {
        AppLogger.warn(_tag, 'Failed to read active meeting session', e);
      }

      final event = StressEvent(
        timestamp: episode.timestamp,
        peakHr: episode.peakHr,
        meanHr: episode.meanHr,
        baselineHr: episode.baselineHr,
        meetingTitle: meetingTitle,
        attendees: attendees,
        durationSeconds: episode.durationSeconds,
        stressLoad: episode.stressLoad,
        label: attendees.isNotEmpty
            ? StressEventLabel.confirmed
            : StressEventLabel.unconfirmed,
      );

      int? insertedId;
      try {
        insertedId = await _databaseService.insertStressEvent(event);
      } catch (e) {
        AppLogger.error(_tag, 'Failed to insert stress event into SQLite', e);
      }

      final savedEvent =
          insertedId != null ? event.copyWith(id: insertedId) : event;

      if (!_eventController.isClosed) {
        _eventController.add(savedEvent);
      }
    } finally {
      _isTriggering = false;
    }
  }
}
