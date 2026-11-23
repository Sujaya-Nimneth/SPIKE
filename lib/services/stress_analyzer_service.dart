import 'dart:async';
import '../models/stress_event.dart';
import '../utils/app_logger.dart';
import 'calendar_service.dart';
import 'database_service.dart';
import 'stress/stress_detector.dart';

/// Orchestrates real-time heart rate stress analysis using the v2
/// [StressDetector] pipeline and persists detected episodes to [DatabaseService].
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
  final _baselineController = StreamController<double?>.broadcast();

  bool _isRunning = false;
  int _lastEmittedCalmScore = 88;
  StressDetectionPhase _lastEmittedPhase = StressDetectionPhase.warmingUp;
  double? _lastEmittedBaseline;

  int? _activePersistedEventId;
  Future<void> _dbOpQueue = Future<void>.value();

  StreamSubscription<int>? _hrSubscription;

  // ── Public API ──────────────────────────────────────────────

  /// Stream of newly detected and persisted stress events.
  Stream<StressEvent> get stressEventStream => _eventController.stream;

  /// Stream of live Calm Score updates (0–100, default 88).
  Stream<int> get calmScoreStream => _calmScoreController.stream;

  /// Stream of detector phase transitions.
  Stream<StressDetectionPhase> get phaseStream => _phaseController.stream;

  /// Stream of rolling median baseline BPM updates (`null` while calibrating).
  Stream<double?> get baselineStream => _baselineController.stream;

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

  /// Reset the stress detector state and baseline calibration.
  void resetDetector() {
    _detector.reset();
    _activePersistedEventId = null;
    _emitTelemetryUpdates();
  }

  /// Stop the analyzer subscription.
  void stop() {
    _isRunning = false;
    unawaited(_hrSubscription?.cancel());
    _hrSubscription = null;
  }

  /// Dispose of all resources.
  void dispose() {
    stop();
    unawaited(_eventController.close());
    unawaited(_calmScoreController.close());
    unawaited(_phaseController.close());
    unawaited(_baselineController.close());
  }

  // ── Core Processing ─────────────────────────────────────────

  void _onHeartRateReceived(int hr) {
    final result = _detector.processSampleWithLifecycle(hr);
    _emitTelemetryUpdates();

    if (result.started != null) {
      final started = result.started!;
      _enqueueDbOp(() => _persistDetectedEpisode(started));
    }

    if (result.completed != null) {
      final completed = result.completed!;
      _enqueueDbOp(() => _finalizePersistedEpisode(completed));
    }
  }

  void _emitTelemetryUpdates() {
    final newCalm = _detector.calmScore;
    if (newCalm != _lastEmittedCalmScore && !_calmScoreController.isClosed) {
      _lastEmittedCalmScore = newCalm;
      _calmScoreController.add(newCalm);
    }

    final newPhase = _detector.phase;
    if (newPhase != _lastEmittedPhase && !_phaseController.isClosed) {
      _lastEmittedPhase = newPhase;
      _phaseController.add(newPhase);
    }

    final newBaseline = _detector.currentBaseline;
    final baselineChanged = (newBaseline == null) != (_lastEmittedBaseline == null) ||
        (newBaseline != null &&
            _lastEmittedBaseline != null &&
            (newBaseline - _lastEmittedBaseline!).abs() >= 0.5);
    if (baselineChanged && !_baselineController.isClosed) {
      _lastEmittedBaseline = newBaseline;
      _baselineController.add(newBaseline);
    }
  }

  void _enqueueDbOp(Future<void> Function() op) {
    _dbOpQueue = _dbOpQueue.then((_) => op()).catchError((Object e) {
      AppLogger.error(_tag, 'Queued DB operation failed', e);
    });
  }

  Future<void> _persistDetectedEpisode(DetectedStressEpisode episode) async {
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

    try {
      final insertedId = await _databaseService.insertStressEvent(event);
      _activePersistedEventId = insertedId;
      final savedEvent = event.copyWith(id: insertedId);
      if (!_eventController.isClosed) {
        _eventController.add(savedEvent);
      }
    } catch (e) {
      _activePersistedEventId = null;
      AppLogger.error(_tag, 'Failed to insert stress event into SQLite', e);
    }
  }

  Future<void> _finalizePersistedEpisode(DetectedStressEpisode episode) async {
    final eventId = _activePersistedEventId;
    _activePersistedEventId = null;
    if (eventId == null) return;

    try {
      await _databaseService.updateEpisodeMetrics(
        eventId,
        peakHr: episode.peakHr,
        meanHr: episode.meanHr,
        durationSeconds: episode.durationSeconds,
        stressLoad: episode.stressLoad,
      );
    } catch (e) {
      AppLogger.warn(_tag, 'Failed to update recovered episode metrics', e);
    }
  }
}
