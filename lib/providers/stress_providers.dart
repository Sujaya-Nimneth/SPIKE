import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stress_event.dart';
import '../models/leaderboard_entry.dart';
import '../services/calendar_service.dart';
import '../services/database_service.dart';
import '../services/stress/stress_detector.dart';
import '../services/stress_analyzer_service.dart';
import 'ble_providers.dart';

// ── Active Meeting Session Service ──────────────────────────────

/// Provides the [CalendarService] managing active manual meeting sessions.
final calendarServiceProvider = Provider<CalendarService>((ref) {
  final service = CalendarService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// StateNotifier managing the currently active manual meeting session.
class ActiveMeetingNotifier extends StateNotifier<CurrentMeeting?> {
  final CalendarService _service;

  ActiveMeetingNotifier(this._service) : super(_service.activeMeeting);

  void startSession({
    required List<String> attendees,
    String? title,
  }) {
    state = _service.startMeetingSession(
      attendees: attendees,
      title: title,
    );
  }

  void endSession() {
    _service.endMeetingSession();
    state = null;
  }
}

/// Exposes the currently active manual meeting session (`null` when not in a meeting).
final activeMeetingProvider =
    StateNotifierProvider<ActiveMeetingNotifier, CurrentMeeting?>((ref) {
  final service = ref.watch(calendarServiceProvider);
  return ActiveMeetingNotifier(service);
});

// ── Database Service & Reactivity ───────────────────────────────

/// Provides the [DatabaseService] instance.
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(() => service.close());
  return service;
});

/// Emits whenever any stress event or coworker tag is modified in SQLite.
final databaseChangesProvider = StreamProvider<void>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return db.changes;
});

// ── Stress Analyzer & Live Calm Score ───────────────────────────

/// Provides the [StressAnalyzerService], wired to the BLE HR stream,
/// active meeting session service, and SQLite database.
final stressAnalyzerProvider = Provider<StressAnalyzerService>((ref) {
  final calendarService = ref.watch(calendarServiceProvider);
  final databaseService = ref.watch(databaseServiceProvider);

  final analyzer = StressAnalyzerService(
    calendarService: calendarService,
    databaseService: databaseService,
  );

  final bleService = ref.watch(bleServiceProvider);
  analyzer.start(bleService.heartRateStream);

  ref.onDispose(() => analyzer.dispose());
  return analyzer;
});

/// Streams live Calm Score (0–100), seeded with the current score (default 88).
final calmScoreProvider = StreamProvider<int>((ref) async* {
  final analyzer = ref.watch(stressAnalyzerProvider);
  yield analyzer.currentCalmScore;
  yield* analyzer.calmScoreStream;
});

/// Streams the current [StressDetectionPhase] of the detector.
final stressPhaseProvider = StreamProvider<StressDetectionPhase>((ref) async* {
  final analyzer = ref.watch(stressAnalyzerProvider);
  yield analyzer.currentPhase;
  yield* analyzer.phaseStream;
});

// ── Active Stress Event Stream ──────────────────────────────────

/// Streams stress events as they are detected in real time.
final activeStressEventProvider = StreamProvider<StressEvent>((ref) {
  final analyzer = ref.watch(stressAnalyzerProvider);
  return analyzer.stressEventStream;
});

// ── Leaderboard UI State Providers ──────────────────────────────

/// Selected timeframe filter for the leaderboard (`7 Days`, `30 Days`, `All Time`).
final leaderboardPeriodProvider = StateProvider<LeaderboardPeriod>((ref) {
  return LeaderboardPeriod.allTime;
});

/// Office-safe privacy mode: when `true`, displays coworker initials instead of full names.
final leaderboardPrivacyModeProvider = StateProvider<bool>((ref) {
  return false;
});

// ── Stress Events & Coworker Queries from DB ────────────────────

/// Fetches all stored stress events from the database.
final stressEventsProvider = FutureProvider<List<StressEvent>>((ref) async {
  ref.watch(activeStressEventProvider);
  ref.watch(databaseChangesProvider);

  final db = ref.watch(databaseServiceProvider);
  return db.getAllStressEvents();
});

/// Fetches stress events that have not yet been tagged with any coworkers.
final untaggedStressEventsProvider =
    FutureProvider<List<StressEvent>>((ref) async {
  ref.watch(activeStressEventProvider);
  ref.watch(databaseChangesProvider);

  final db = ref.watch(databaseServiceProvider);
  return db.getUntaggedStressEvents();
});

/// Fetches all saved coworker names for quick-select tagging chips.
final coworkerNamesProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(databaseChangesProvider);

  final db = ref.watch(databaseServiceProvider);
  return db.getAllCoworkerNames();
});

/// Fetches the coworker stress leaderboard for the selected [LeaderboardPeriod],
/// ranked by raw spike count descending.
final leaderboardProvider =
    FutureProvider<List<LeaderboardEntry>>((ref) async {
  ref.watch(activeStressEventProvider);
  ref.watch(databaseChangesProvider);
  final period = ref.watch(leaderboardPeriodProvider);

  final db = ref.watch(databaseServiceProvider);
  return db.getLeaderboard(period: period);
});

/// Fetches historical stress events associated with a specific coworker.
final coworkerEventsProvider =
    FutureProvider.family<List<StressEvent>, String>((ref, name) async {
  ref.watch(databaseChangesProvider);

  final db = ref.watch(databaseServiceProvider);
  return db.getEventsForCoworker(name);
});

/// The total number of stress events recorded in the selected [LeaderboardPeriod].
final stressEventCountProvider = FutureProvider<int>((ref) async {
  ref.watch(activeStressEventProvider);
  ref.watch(databaseChangesProvider);
  final period = ref.watch(leaderboardPeriodProvider);

  final db = ref.watch(databaseServiceProvider);
  return db.getStressEventCount(period: period);
});
