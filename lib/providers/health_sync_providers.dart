import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_activity.dart';
import '../models/daily_hr_summary.dart';
import '../models/device_sync_status.dart';
import '../models/readiness_snapshot.dart';
import '../models/sleep_session.dart';
import '../services/ble_service.dart';
import '../services/database_service.dart';
import '../services/readiness/readiness_calculator.dart';
import '../utils/app_logger.dart';
import 'ble_providers.dart';
import 'stress_providers.dart';

/// Persists BLE connection metadata, battery readings, daily activity (`0x43`),
/// and sleep BigData (`0xBC`/`0x27`) into SQLite as packets arrive.
class HealthSyncCoordinator {
  static const _tag = 'HealthSync';

  final BleService _bleService;
  final DatabaseService _db;

  StreamSubscription<DailyActivityRecord>? _activitySub;
  StreamSubscription<SleepSessionRecord>? _sleepSub;
  StreamSubscription<BleConnectionState>? _connSub;
  StreamSubscription<({int percent, bool isCharging})>? _batterySub;

  bool _wasConnected = false;

  HealthSyncCoordinator({
    required BleService bleService,
    required DatabaseService databaseService,
  })  : _bleService = bleService,
        _db = databaseService {
    _start();
  }

  void _start() {
    _activitySub = _bleService.activitySyncStream.listen((record) async {
      try {
        await _db.upsertDailyActivity(record);
      } catch (e) {
        AppLogger.warn(_tag, 'Failed to persist daily activity', e);
      }
    });

    _sleepSub = _bleService.sleepSyncStream.listen((session) async {
      try {
        await _db.upsertSleepSession(session);
      } catch (e) {
        AppLogger.warn(_tag, 'Failed to persist sleep session', e);
      }
    });

    _connSub = _bleService.connectionStream.listen((connState) async {
      try {
        if (connState == BleConnectionState.connected) {
          _wasConnected = true;
          final nowIso = DateTime.now().toUtc().toIso8601String();
          await _db.updateSyncState('last_connected_at', nowIso, notify: false);
          final name = _bleService.connectedDevice?.platformName;
          if (name != null && name.isNotEmpty) {
            await _db.updateSyncState('last_device_name', name);
          } else {
            await _db.updateSyncState('last_device_name', 'Colmi R02');
          }
        } else if (_wasConnected &&
            (connState == BleConnectionState.disconnected ||
                connState == BleConnectionState.error)) {
          _wasConnected = false;
          await _db.updateSyncState(
            'last_connected_at',
            DateTime.now().toUtc().toIso8601String(),
          );
        }
      } catch (e) {
        AppLogger.warn(_tag, 'Failed to persist connection metadata', e);
      }
    });

    _batterySub = _bleService.batteryStream.listen((battery) async {
      try {
        await _db.updateSyncState(
          'last_battery_percent',
          '${battery.percent}',
          notify: false,
        );
        await _db.updateSyncState(
          'last_battery_charging',
          battery.isCharging ? '1' : '0',
        );
      } catch (e) {
        AppLogger.warn(_tag, 'Failed to persist battery status', e);
      }
    });
  }

  void dispose() {
    unawaited(_activitySub?.cancel());
    unawaited(_sleepSub?.cancel());
    unawaited(_connSub?.cancel());
    unawaited(_batterySub?.cancel());
  }
}

/// Initializes and owns [HealthSyncCoordinator] for the lifetime of the app.
final healthSyncCoordinatorProvider = Provider<HealthSyncCoordinator?>((ref) {
  final bleService = ref.watch(bleServiceProvider);
  final db = ref.watch(databaseServiceProvider);
  final coordinator = HealthSyncCoordinator(
    bleService: bleService,
    databaseService: db,
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

// ── Selected Tab Provider ───────────────────────────────────────

/// Active tab index in [MainShell], allowing Home cards to switch tabs cleanly.
final selectedTabProvider = StateProvider<int>((ref) => 0);

// ── Sync Status & Persisted Telemetry Providers ─────────────────

final deviceSyncStatusProvider = FutureProvider<DeviceSyncStatus>((ref) async {
  ref.watch(databaseChangesProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.getDeviceSyncStatus();
});

final latestHrSummaryProvider = FutureProvider<DailyHrSummary?>((ref) async {
  ref.watch(databaseChangesProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.getLatestHrSummary();
});

final recentHrSummariesProvider =
    FutureProvider<List<DailyHrSummary>>((ref) async {
  ref.watch(databaseChangesProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.getRecentHrSummaries(days: 7);
});

final dailyHrAveragesProvider = FutureProvider<
    ({double? avgDailyHr, double? avgRestingHr, int daysCount})>((ref) async {
  ref.watch(databaseChangesProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.getDailyHrAverages(days: 7);
});

final latestActivityProvider = FutureProvider<DailyActivityRecord?>((ref) async {
  ref.watch(databaseChangesProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.getLatestActivity();
});

final recentActivityProvider =
    FutureProvider<List<DailyActivityRecord>>((ref) async {
  ref.watch(databaseChangesProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.getRecentActivity(days: 7);
});

final activityAveragesProvider = FutureProvider<ActivityAverages>((ref) async {
  ref.watch(databaseChangesProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.getActivityAverages(days: 7);
});

final latestSleepProvider = FutureProvider<SleepSessionRecord?>((ref) async {
  ref.watch(databaseChangesProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.getLatestSleepSession();
});

final recentSleepProvider =
    FutureProvider<List<SleepSessionRecord>>((ref) async {
  ref.watch(databaseChangesProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.getRecentSleepSessions(days: 7);
});

final sleepAveragesProvider = FutureProvider<SleepAverages>((ref) async {
  ref.watch(databaseChangesProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.getSleepAverages(days: 7);
});

// ── WHOOP-style Ready Score Provider ────────────────────────────

final readinessProvider = Provider<ReadinessSnapshot>((ref) {
  final connState =
      ref.watch(bleConnectionStateProvider).valueOrNull ??
          BleConnectionState.disconnected;
  final isConnected = connState == BleConnectionState.connected;

  final baselineHr = ref.watch(baselineHrProvider).valueOrNull;
  final liveCalm = ref.watch(calmScoreProvider).valueOrNull;
  final todayStressCount = ref.watch(todayStressCountProvider).valueOrNull ?? 0;

  final latestSleep = ref.watch(latestSleepProvider).valueOrNull;
  final sleepAvgs = ref.watch(sleepAveragesProvider).valueOrNull;
  final latestHr = ref.watch(latestHrSummaryProvider).valueOrNull;
  final hrAvgs = ref.watch(dailyHrAveragesProvider).valueOrNull;
  final syncStatus = ref.watch(deviceSyncStatusProvider).valueOrNull;

  final effectiveRestingHr = baselineHr?.round() ??
      latestSleep?.restingHr ??
      latestHr?.restingHr ??
      latestHr?.avgHr.round();

  final sevenDayAvgRhr = hrAvgs?.avgRestingHr ?? hrAvgs?.avgDailyHr;
  final effectiveCalm = (isConnected && baselineHr != null) ? liveCalm : null;

  return ReadinessCalculator.calculate(
    latestSleep: latestSleep,
    sleepAverages: sleepAvgs,
    currentRestingHr: effectiveRestingHr,
    sevenDayAvgRestingHr: sevenDayAvgRhr,
    calmScore: effectiveCalm,
    todayStressCount: todayStressCount,
    isLive: isConnected,
    lastSyncedAt: syncStatus?.lastConnectedAt ?? latestHr?.updatedAt,
  );
});
