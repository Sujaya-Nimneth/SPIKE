import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stress_event.dart';
import '../models/leaderboard_entry.dart';
import '../services/calendar_service.dart';
import '../services/database_service.dart';
import '../services/stress_analyzer_service.dart';
import 'ble_providers.dart';

// ── Calendar Service ────────────────────────────────────────────

/// Provides the singleton [CalendarService].
final calendarServiceProvider = Provider<CalendarService>((ref) {
  return CalendarService();
});

// ── Database Service ────────────────────────────────────────────

/// Provides the singleton [DatabaseService].
///
/// The database is lazily initialized on first access.
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final service = DatabaseService();
  ref.onDispose(() => service.close());
  return service;
});

// ── Stress Analyzer ─────────────────────────────────────────────

/// Provides the [StressAnalyzerService], wired to the HR stream,
/// calendar service, and database.
///
/// Automatically starts analyzing when the HR stream is available.
final stressAnalyzerProvider = Provider<StressAnalyzerService>((ref) {
  final calendarService = ref.watch(calendarServiceProvider);
  final databaseService = ref.watch(databaseServiceProvider);

  final analyzer = StressAnalyzerService(
    calendarService: calendarService,
    databaseService: databaseService,
  );

  // Wire the analyzer to the HR stream from the BLE service
  final bleService = ref.watch(bleServiceProvider);
  analyzer.start(bleService.heartRateStream);

  ref.onDispose(() => analyzer.dispose());
  return analyzer;
});

// ── Active Stress Event Stream ──────────────────────────────────

/// Streams stress events as they are detected in real time.
///
/// Useful for showing notifications or alerts in the UI.
final activeStressEventProvider = StreamProvider<StressEvent>((ref) {
  final analyzer = ref.watch(stressAnalyzerProvider);
  return analyzer.stressEventStream;
});

// ── Stress Events from DB ───────────────────────────────────────

/// Fetches all stored stress events from the database.
///
/// Call `ref.invalidate(stressEventsProvider)` to refresh after
/// a new event is recorded.
final stressEventsProvider = FutureProvider<List<StressEvent>>((ref) async {
  // Re-fetch whenever a new stress event is detected
  ref.watch(activeStressEventProvider);

  final db = ref.watch(databaseServiceProvider);
  return db.getAllStressEvents();
});

// ── Leaderboard ─────────────────────────────────────────────────

/// Fetches the coworker stress leaderboard from the database.
///
/// Automatically refreshes when new stress events arrive.
final leaderboardProvider =
    FutureProvider<List<LeaderboardEntry>>((ref) async {
  // Re-fetch whenever a new stress event is detected
  ref.watch(activeStressEventProvider);

  final db = ref.watch(databaseServiceProvider);
  return db.getLeaderboard();
});

// ── Stress Event Count ──────────────────────────────────────────

/// The total number of stress events recorded.
final stressEventCountProvider = FutureProvider<int>((ref) async {
  ref.watch(activeStressEventProvider);

  final db = ref.watch(databaseServiceProvider);
  return db.getStressEventCount();
});
