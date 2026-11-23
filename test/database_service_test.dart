import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:smart_ring/models/daily_activity.dart';
import 'package:smart_ring/models/leaderboard_entry.dart';
import 'package:smart_ring/models/sleep_session.dart';
import 'package:smart_ring/models/stress_event.dart';
import 'package:smart_ring/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('DatabaseService v3', () {
    late DatabaseService db;
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('spike_db_test_');
      db = DatabaseService(
        databaseFactory: databaseFactoryFfi,
        dbPathOverride: p.join(tempDir.path, 'test.db'),
      );
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('deduplicates coworkers case-insensitively and updates episode metrics', () async {
      final now = DateTime.now();
      final id1 = await db.insertStressEvent(
        StressEvent(
          timestamp: now.subtract(const Duration(days: 2)),
          peakHr: 102,
          baselineHr: 68,
          meetingTitle: 'Sprint Review',
          attendees: ['Alice', 'Bob'],
          durationSeconds: 120,
          stressLoad: 2.1,
          label: StressEventLabel.confirmed,
        ),
      );
      await db.insertStressEvent(
        StressEvent(
          timestamp: now.subtract(const Duration(days: 15)),
          peakHr: 110,
          baselineHr: 70,
          meetingTitle: 'Budget Sync',
          attendees: ['alice'], // case variant
          durationSeconds: 180,
          stressLoad: 3.4,
          label: StressEventLabel.confirmed,
        ),
      );

      final boardAll = await db.getLeaderboard(period: LeaderboardPeriod.allTime);
      expect(boardAll.length, 2);
      expect(boardAll.first.name, 'Alice');
      expect(boardAll.first.spikeCount, 2);

      final board7d = await db.getLeaderboard(period: LeaderboardPeriod.days7);
      expect(board7d.length, 2);
      expect(board7d.first.spikeCount, 1);

      final aliceEvents7d = await db.getEventsForCoworker(
        'Alice',
        period: LeaderboardPeriod.days7,
      );
      expect(aliceEvents7d.length, 1);

      await db.updateEpisodeMetrics(
        id1,
        peakHr: 118,
        meanHr: 108,
        durationSeconds: 260,
        stressLoad: 4.5,
      );
      final updated = await db.getEventsForCoworker(
        'Alice',
        period: LeaderboardPeriod.days7,
      );
      expect(updated.first.peakHr, 118);
      expect(updated.first.meanHr, 108);
      expect(updated.first.durationSeconds, 260);
    });

    test('supports rename, hide/unhide, cascade delete, and clearAll', () async {
      final id = await db.insertStressEvent(
        StressEvent(
          timestamp: DateTime.now(),
          peakHr: 105,
          baselineHr: 68,
          attendees: ['Charlie'],
          durationSeconds: 150,
          label: StressEventLabel.confirmed,
        ),
      );

      await db.renameCoworker('Charlie', 'Charles');
      expect(await db.getAllCoworkerNames(), ['Charles']);

      await db.setCoworkerHidden('Charles', hidden: true);
      expect(await db.getAllCoworkerNames(), isEmpty);
      expect(await db.getHiddenCoworkerNames(), ['Charles']);
      expect(await db.getLeaderboard(), isEmpty);

      await db.setCoworkerHidden('Charles', hidden: false);
      expect(await db.getLeaderboard(), hasLength(1));

      await db.deleteStressEvent(id);
      expect(await db.getAllStressEvents(), isEmpty);

      await db.insertStressEvent(
        StressEvent(
          timestamp: DateTime.now(),
          peakHr: 98,
          baselineHr: 66,
          attendees: ['Dana'],
          durationSeconds: 130,
          label: StressEventLabel.confirmed,
        ),
      );
      expect(await db.clearAll(), 1);
      expect(await db.getAllCoworkerNames(), isEmpty);
    });

    test('persists HR summaries, Activity, Sleep, averages, and sync state', () async {
      final day1 = DateTime(2026, 11, 23, 10, 0);
      final day2 = DateTime(2026, 11, 24, 11, 0);

      await db.recordHeartRateSample(70, timestamp: day1, restingHr: 62);
      await db.recordHeartRateSample(80, timestamp: day1, restingHr: 62);
      await db.recordHeartRateSample(66, timestamp: day2, restingHr: 60);

      final latestHr = await db.getLatestHrSummary();
      expect(latestHr, isNotNull);
      expect(latestHr!.lastHr, 66);
      expect(latestHr.date, '2026-11-24');

      final hrAvgs = await db.getDailyHrAverages(days: 7);
      expect(hrAvgs.daysCount, 2);
      expect(hrAvgs.avgDailyHr, closeTo(70.5, 0.1)); // (75 + 66) / 2
      expect(hrAvgs.avgRestingHr, closeTo(61.0, 0.1));

      await db.upsertDailyActivity(
        DailyActivityRecord(
          date: '2026-11-23',
          steps: 6000,
          calories: 300,
          distanceMeters: 4200,
          activeMinutes: 45,
          syncedAt: day1,
        ),
      );
      await db.upsertDailyActivity(
        DailyActivityRecord(
          date: '2026-11-24',
          steps: 10000,
          calories: 500,
          distanceMeters: 7400,
          activeMinutes: 75,
          syncedAt: day2,
        ),
      );

      final actAvgs = await db.getActivityAverages(days: 7);
      expect(actAvgs.daysCount, 2);
      expect(actAvgs.avgSteps, 8000);
      expect(actAvgs.avgCalories, 400);

      await db.upsertSleepSession(
        SleepSessionRecord(
          date: '2026-11-24',
          totalSleepMinutes: 450,
          timeInBedMinutes: 470,
          awakeMinutes: 20,
          lightMinutes: 240,
          deepMinutes: 110,
          remMinutes: 100,
          efficiencyPercent: 96,
          sleepScore: 89,
          restingHr: 56,
          syncedAt: day2,
        ),
      );

      final sleepAvgs = await db.getSleepAverages(days: 7);
      expect(sleepAvgs.nightsCount, 1);
      expect(sleepAvgs.avgSleepScore, 89);

      await db.updateSyncState('last_device_name', 'R02_Test');
      await db.updateSyncState('last_battery_percent', '82');
      await db.updateSyncState('last_battery_charging', '0');

      final status = await db.getDeviceSyncStatus();
      expect(status.lastDeviceName, 'R02_Test');
      expect(status.lastBatteryPercent, 82);
      expect(status.lastBatteryCharging, isFalse);
      expect(status.lastActivitySyncAt, isNotNull);
      expect(status.lastSleepSyncAt, isNotNull);
    });

    test('migrates v2 database to v3 cleanly with deduped coworkers and mean_hr backfill', () async {
      final migrateDir = Directory.systemTemp.createTempSync('spike_mig_test_');
      final dbPath = p.join(migrateDir.path, 'legacy_v2.db');
      try {
        // Create an explicit v2 database
        final rawDb = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: (d, _) async {
              await d.execute('''
                CREATE TABLE stress_events (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  timestamp TEXT NOT NULL,
                  peak_hr INTEGER NOT NULL,
                  mean_hr INTEGER NOT NULL DEFAULT 0,
                  baseline_hr INTEGER NOT NULL,
                  meeting_title TEXT,
                  attendees TEXT,
                  duration_seconds INTEGER NOT NULL,
                  stress_load REAL NOT NULL DEFAULT 0.0,
                  user_label TEXT NOT NULL DEFAULT 'unconfirmed'
                )
              ''');
              await d.execute('''
                CREATE TABLE coworkers (
                  name TEXT PRIMARY KEY,
                  hidden INTEGER NOT NULL DEFAULT 0,
                  created_at TEXT NOT NULL
                )
              ''');
              await d.execute('''
                CREATE TABLE event_attendees (
                  event_id INTEGER NOT NULL,
                  coworker_name TEXT NOT NULL,
                  PRIMARY KEY (event_id, coworker_name)
                )
              ''');
              await d.insert('stress_events', {
                'id': 1,
                'timestamp': DateTime.now().toUtc().toIso8601String(),
                'peak_hr': 104,
                'mean_hr': 0,
                'baseline_hr': 68,
                'attendees': '["Alice"]',
                'duration_seconds': 120,
                'user_label': 'confirmed',
              });
              await d.insert('stress_events', {
                'id': 2,
                'timestamp': DateTime.now().toUtc().toIso8601String(),
                'peak_hr': 108,
                'mean_hr': 0,
                'baseline_hr': 68,
                'attendees': '["alice"]',
                'duration_seconds': 120,
                'user_label': 'confirmed',
              });
              await d.insert('coworkers', {
                'name': 'Alice',
                'hidden': 0,
                'created_at': '2026-01-01T00:00:00Z',
              });
              await d.insert('coworkers', {
                'name': 'alice',
                'hidden': 0,
                'created_at': '2026-01-02T00:00:00Z',
              });
              await d.insert('event_attendees', {
                'event_id': 1,
                'coworker_name': 'Alice',
              });
              await d.insert('event_attendees', {
                'event_id': 2,
                'coworker_name': 'alice',
              });
            },
          ),
        );
        await rawDb.close();

        // Open with DatabaseService (version 3)
        final migrated = DatabaseService(
          databaseFactory: databaseFactoryFfi,
          dbPathOverride: dbPath,
        );
        final board = await migrated.getLeaderboard();
        expect(board.length, 1);
        expect(board.first.spikeCount, 2);

        final events = await migrated.getAllStressEvents();
        expect(events.every((e) => e.meanHr == e.peakHr), isTrue);

        await migrated.close();
      } finally {
        if (migrateDir.existsSync()) {
          migrateDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
