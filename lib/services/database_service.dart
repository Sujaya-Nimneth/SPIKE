import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/daily_activity.dart';
import '../models/daily_hr_summary.dart';
import '../models/device_sync_status.dart';
import '../models/leaderboard_entry.dart';
import '../models/sleep_session.dart';
import '../models/stress_event.dart';

/// SQLite database service for storing and querying stress events,
/// coworker profiles, normalized event-attendee relationships, and
/// persisted smart-ring telemetry (heart rate, activity, sleep, sync state).
class DatabaseService {
  DatabaseService({
    DatabaseFactory? databaseFactory,
    String? dbPathOverride,
  })  : _databaseFactory = databaseFactory,
        _dbPathOverride = dbPathOverride;

  static const _dbName = 'stress_events.db';
  static const _dbVersion = 3;

  static const _eventsTable = 'stress_events';
  static const _attendeesTable = 'event_attendees';
  static const _coworkersTable = 'coworkers';
  static const _dailyHrTable = 'daily_hr_summaries';
  static const _dailyActivityTable = 'daily_activity';
  static const _sleepSessionsTable = 'sleep_sessions';
  static const _syncStateTable = 'device_sync_state';

  final DatabaseFactory? _databaseFactory;
  final String? _dbPathOverride;

  Database? _database;
  Completer<Database>? _initCompleter;

  final _changesController = StreamController<void>.broadcast();

  /// Broadcast stream that emits whenever stress events, coworker tags, or
  /// persisted ring telemetry change.
  Stream<void> get changes => _changesController.stream;

  void _notifyChanged() {
    if (!_changesController.isClosed) {
      _changesController.add(null);
    }
  }

  /// Open (or create) the database.
  Future<Database> get database async {
    if (_database != null) return _database!;

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<Database>();
    try {
      _database = await _initDatabase();
      _initCompleter!.complete(_database!);
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path =
        _dbPathOverride ?? join(await getDatabasesPath(), _dbName);

    final options = OpenDatabaseOptions(
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createV3Schema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateV1ToV2(db);
        }
        if (oldVersion < 3) {
          await _migrateV2ToV3(db);
        }
      },
    );

    if (_databaseFactory != null) {
      return _databaseFactory.openDatabase(path, options: options);
    }
    return openDatabase(
      path,
      version: options.version,
      onConfigure: options.onConfigure,
      onCreate: options.onCreate,
      onUpgrade: options.onUpgrade,
    );
  }

  Future<void> _createV3Schema(Database db) async {
    await db.execute('''
      CREATE TABLE $_eventsTable (
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

    await db.execute('''
      CREATE TABLE $_coworkersTable (
        name TEXT PRIMARY KEY COLLATE NOCASE,
        hidden INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $_attendeesTable (
        event_id INTEGER NOT NULL,
        coworker_name TEXT NOT NULL COLLATE NOCASE,
        PRIMARY KEY (event_id, coworker_name),
        FOREIGN KEY (event_id) REFERENCES $_eventsTable(id) ON DELETE CASCADE,
        FOREIGN KEY (coworker_name) REFERENCES $_coworkersTable(name)
          ON UPDATE CASCADE ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_stress_events_timestamp ON $_eventsTable(timestamp DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_event_attendees_name ON $_attendeesTable(coworker_name)',
    );

    await _createTelemetryTables(db);
  }

  Future<void> _createTelemetryTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_dailyHrTable (
        date TEXT PRIMARY KEY,
        last_hr INTEGER NOT NULL,
        min_hr INTEGER NOT NULL,
        max_hr INTEGER NOT NULL,
        hr_sum INTEGER NOT NULL,
        sample_count INTEGER NOT NULL,
        resting_hr INTEGER,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_dailyActivityTable (
        date TEXT PRIMARY KEY,
        steps INTEGER NOT NULL,
        calories INTEGER NOT NULL,
        distance_meters INTEGER NOT NULL,
        active_minutes INTEGER NOT NULL,
        step_goal INTEGER NOT NULL DEFAULT 8000,
        synced_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_sleepSessionsTable (
        date TEXT PRIMARY KEY,
        bedtime TEXT,
        wake_time TEXT,
        total_sleep_minutes INTEGER NOT NULL,
        time_in_bed_minutes INTEGER NOT NULL,
        awake_minutes INTEGER NOT NULL,
        light_minutes INTEGER NOT NULL,
        deep_minutes INTEGER NOT NULL,
        rem_minutes INTEGER NOT NULL,
        efficiency_percent INTEGER NOT NULL,
        sleep_score INTEGER NOT NULL,
        resting_hr INTEGER,
        synced_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_syncStateTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_daily_hr_date ON $_dailyHrTable(date DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_daily_activity_date ON $_dailyActivityTable(date DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sleep_sessions_date ON $_sleepSessionsTable(date DESC)',
    );
  }

  Future<void> _migrateV1ToV2(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE $_eventsTable ADD COLUMN mean_hr INTEGER NOT NULL DEFAULT 0',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE $_eventsTable ADD COLUMN stress_load REAL NOT NULL DEFAULT 0.0',
      );
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE $_eventsTable ADD COLUMN user_label TEXT NOT NULL DEFAULT 'unconfirmed'",
      );
    } catch (_) {}

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_coworkersTable (
        name TEXT PRIMARY KEY,
        hidden INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_attendeesTable (
        event_id INTEGER NOT NULL,
        coworker_name TEXT NOT NULL,
        PRIMARY KEY (event_id, coworker_name)
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_stress_events_timestamp ON $_eventsTable(timestamp DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_event_attendees_name ON $_attendeesTable(coworker_name)',
    );

    final rows = await db.query(_eventsTable);
    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (final row in rows) {
      final eventId = row['id'] as int?;
      final rawJson = row['attendees'] as String?;
      if (eventId == null || rawJson == null || rawJson.isEmpty) continue;
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          for (final item in decoded) {
            final cleanName = item.toString().trim();
            if (cleanName.isEmpty) continue;
            await db.insert(
              _coworkersTable,
              {'name': cleanName, 'hidden': 0, 'created_at': nowIso},
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            await db.insert(
              _attendeesTable,
              {'event_id': eventId, 'coworker_name': cleanName},
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _migrateV2ToV3(Database db) async {
    // 1. Backfill missing mean_hr on legacy rows
    await db.execute(
      'UPDATE $_eventsTable SET mean_hr = peak_hr WHERE mean_hr = 0',
    );

    // 2. Deduplicate coworkers case-insensitively and enforce COLLATE NOCASE + FKs
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final canonicalByKey = <String, ({String name, int hidden, String createdAt})>{};

    final existingCoworkers = await db.query(_coworkersTable);
    for (final row in existingCoworkers) {
      final rawName = (row['name'] as String?)?.trim() ?? '';
      if (rawName.isEmpty) continue;
      final key = rawName.toLowerCase();
      final hidden = (row['hidden'] as int?) ?? 0;
      final createdAt = (row['created_at'] as String?) ?? nowIso;

      final existing = canonicalByKey[key];
      if (existing == null) {
        canonicalByKey[key] = (
          name: rawName,
          hidden: hidden,
          createdAt: createdAt,
        );
      } else {
        // Keep visible if any variant was visible
        canonicalByKey[key] = (
          name: existing.name,
          hidden: (existing.hidden == 0 || hidden == 0) ? 0 : 1,
          createdAt: existing.createdAt,
        );
      }
    }

    final existingLinks = await db.query(_attendeesTable);
    for (final row in existingLinks) {
      final rawName = (row['coworker_name'] as String?)?.trim() ?? '';
      if (rawName.isEmpty) continue;
      final key = rawName.toLowerCase();
      canonicalByKey.putIfAbsent(
        key,
        () => (name: rawName, hidden: 0, createdAt: nowIso),
      );
    }

    await db.execute('DROP TABLE IF EXISTS ${_coworkersTable}_v3');
    await db.execute('''
      CREATE TABLE ${_coworkersTable}_v3 (
        name TEXT PRIMARY KEY COLLATE NOCASE,
        hidden INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    for (final entry in canonicalByKey.values) {
      await db.insert(
        '${_coworkersTable}_v3',
        {
          'name': entry.name,
          'hidden': entry.hidden,
          'created_at': entry.createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    // Collect valid event IDs to avoid orphan links violating FK
    final eventRows = await db.query(_eventsTable, columns: ['id']);
    final validEventIds = eventRows.map((r) => r['id'] as int).toSet();

    await db.execute('DROP TABLE IF EXISTS ${_attendeesTable}_v3');
    await db.execute('DROP TABLE $_coworkersTable');
    await db.execute('ALTER TABLE ${_coworkersTable}_v3 RENAME TO $_coworkersTable');

    await db.execute('''
      CREATE TABLE ${_attendeesTable}_v3 (
        event_id INTEGER NOT NULL,
        coworker_name TEXT NOT NULL COLLATE NOCASE,
        PRIMARY KEY (event_id, coworker_name),
        FOREIGN KEY (event_id) REFERENCES $_eventsTable(id) ON DELETE CASCADE,
        FOREIGN KEY (coworker_name) REFERENCES $_coworkersTable(name)
          ON UPDATE CASCADE ON DELETE CASCADE
      )
    ''');

    for (final row in existingLinks) {
      final eventId = row['event_id'] as int?;
      final rawName = (row['coworker_name'] as String?)?.trim() ?? '';
      if (eventId == null || !validEventIds.contains(eventId) || rawName.isEmpty) {
        continue;
      }
      final canonical = canonicalByKey[rawName.toLowerCase()]?.name ?? rawName;
      await db.insert(
        '${_attendeesTable}_v3',
        {'event_id': eventId, 'coworker_name': canonical},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await db.execute('DROP TABLE $_attendeesTable');
    await db.execute('ALTER TABLE ${_attendeesTable}_v3 RENAME TO $_attendeesTable');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_event_attendees_name ON $_attendeesTable(coworker_name)',
    );

    // 3. Create new v3 telemetry tables
    await _createTelemetryTables(db);
  }

  // ── Stress Event Insert & Update ────────────────────────────

  /// Insert a new stress event and normalize its attendees.
  Future<int> insertStressEvent(StressEvent event) async {
    final db = await database;
    final cleanAttendees = _normalizeNames(event.attendees);

    final eventId = await db.transaction<int>((txn) async {
      final canonicalAttendees =
          await _resolveCanonicalNamesTxn(txn, cleanAttendees);
      final normalizedEvent = event.copyWith(attendees: canonicalAttendees);
      final id = await txn.insert(_eventsTable, normalizedEvent.toMap());
      await _syncEventAttendeesTxn(txn, id, canonicalAttendees);
      return id;
    });

    _notifyChanged();
    return eventId;
  }

  /// Update finalized episode metrics once a confirmed stress spike recovers.
  Future<void> updateEpisodeMetrics(
    int eventId, {
    required int peakHr,
    required int meanHr,
    required int durationSeconds,
    required double stressLoad,
  }) async {
    final db = await database;
    await db.update(
      _eventsTable,
      {
        'peak_hr': peakHr,
        'mean_hr': meanHr,
        'duration_seconds': durationSeconds,
        'stress_load': stressLoad,
      },
      where: 'id = ?',
      whereArgs: [eventId],
    );
    _notifyChanged();
  }

  /// Update the tagged coworkers and optional meeting title for an event.
  Future<void> updateEventAttendees(
    int eventId,
    List<String> attendees, {
    String? meetingTitle,
  }) async {
    final db = await database;
    final cleanAttendees = _normalizeNames(attendees);

    await db.transaction((txn) async {
      final canonicalAttendees =
          await _resolveCanonicalNamesTxn(txn, cleanAttendees);
      final updates = <String, dynamic>{
        'attendees': jsonEncode(canonicalAttendees),
        'user_label': StressEventLabel.confirmed.value,
      };
      if (meetingTitle != null) {
        updates['meeting_title'] =
            meetingTitle.trim().isEmpty ? null : meetingTitle.trim();
      }

      await txn.update(
        _eventsTable,
        updates,
        where: 'id = ?',
        whereArgs: [eventId],
      );
      await _syncEventAttendeesTxn(txn, eventId, canonicalAttendees);
    });

    _notifyChanged();
  }

  /// Update the user confirmation label (`confirmed` or `dismissed`) for an event.
  Future<void> updateEventLabel(int eventId, StressEventLabel label) async {
    final db = await database;
    await db.update(
      _eventsTable,
      {'user_label': label.value},
      where: 'id = ?',
      whereArgs: [eventId],
    );
    _notifyChanged();
  }

  /// Delete a single stress event by ID (cascades to `event_attendees`).
  Future<void> deleteStressEvent(int eventId) async {
    final db = await database;
    await db.delete(
      _eventsTable,
      where: 'id = ?',
      whereArgs: [eventId],
    );
    _notifyChanged();
  }

  Future<List<String>> _resolveCanonicalNamesTxn(
    Transaction txn,
    List<String> names,
  ) async {
    final resolved = <String>[];
    for (final name in names) {
      final existing = await txn.query(
        _coworkersTable,
        columns: ['name'],
        where: 'name = ? COLLATE NOCASE',
        whereArgs: [name],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        resolved.add(existing.first['name'] as String);
      } else {
        resolved.add(name);
      }
    }
    return resolved;
  }

  Future<void> _syncEventAttendeesTxn(
    Transaction txn,
    int eventId,
    List<String> attendees,
  ) async {
    await txn.delete(
      _attendeesTable,
      where: 'event_id = ?',
      whereArgs: [eventId],
    );

    final nowIso = DateTime.now().toUtc().toIso8601String();
    for (final name in attendees) {
      await txn.insert(
        _coworkersTable,
        {'name': name, 'hidden': 0, 'created_at': nowIso},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.insert(
        _attendeesTable,
        {'event_id': eventId, 'coworker_name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  List<String> _normalizeNames(List<String> names) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in names) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  // ── Coworker Directory ──────────────────────────────────────

  /// Add a coworker to the directory for quick tagging (case-insensitive).
  Future<void> addCoworker(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await database;
    final existing = await db.query(
      _coworkersTable,
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      // Ensure un-hidden if re-added explicitly
      if ((existing.first['hidden'] as int?) == 1) {
        await db.update(
          _coworkersTable,
          {'hidden': 0},
          where: 'name = ? COLLATE NOCASE',
          whereArgs: [trimmed],
        );
        _notifyChanged();
      }
      return;
    }

    await db.insert(
      _coworkersTable,
      {
        'name': trimmed,
        'hidden': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _notifyChanged();
  }

  /// Rename or merge a coworker across all historical stress events.
  Future<void> renameCoworker(String oldName, String newName) async {
    final cleanOld = oldName.trim();
    final cleanNew = newName.trim();
    if (cleanOld.isEmpty || cleanNew.isEmpty || cleanOld == cleanNew) return;

    final db = await database;
    await db.transaction((txn) async {
      // Case-only rename (e.g. "alice" -> "Alice")
      if (cleanOld.toLowerCase() == cleanNew.toLowerCase()) {
        final affectedRows = await txn.query(
          _attendeesTable,
          columns: ['event_id'],
          where: 'coworker_name = ? COLLATE NOCASE',
          whereArgs: [cleanOld],
        );
        await txn.update(
          _coworkersTable,
          {'name': cleanNew},
          where: 'name = ? COLLATE NOCASE',
          whereArgs: [cleanOld],
        );
        await _refreshEventAttendeesJsonTxn(
          txn,
          affectedRows.map((r) => r['event_id'] as int),
        );
        return;
      }

      // Merging into an existing or new coworker
      final existingTarget = await txn.query(
        _coworkersTable,
        columns: ['name'],
        where: 'name = ? COLLATE NOCASE',
        whereArgs: [cleanNew],
        limit: 1,
      );
      final targetName = existingTarget.isNotEmpty
          ? existingTarget.first['name'] as String
          : cleanNew;

      if (existingTarget.isEmpty) {
        await txn.insert(
          _coworkersTable,
          {
            'name': targetName,
            'hidden': 0,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      final affectedRows = await txn.query(
        _attendeesTable,
        columns: ['event_id'],
        where: 'coworker_name = ? COLLATE NOCASE',
        whereArgs: [cleanOld],
      );

      for (final row in affectedRows) {
        final eventId = row['event_id'] as int;
        await txn.insert(
          _attendeesTable,
          {'event_id': eventId, 'coworker_name': targetName},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await txn.delete(
        _attendeesTable,
        where: 'coworker_name = ? COLLATE NOCASE',
        whereArgs: [cleanOld],
      );
      await txn.delete(
        _coworkersTable,
        where: 'name = ? COLLATE NOCASE',
        whereArgs: [cleanOld],
      );

      await _refreshEventAttendeesJsonTxn(
        txn,
        affectedRows.map((r) => r['event_id'] as int),
      );
    });

    _notifyChanged();
  }

  Future<void> _refreshEventAttendeesJsonTxn(
    Transaction txn,
    Iterable<int> eventIds,
  ) async {
    for (final eventId in eventIds.toSet()) {
      final currentAttendees = await txn.query(
        _attendeesTable,
        where: 'event_id = ?',
        whereArgs: [eventId],
      );
      final names =
          currentAttendees.map((r) => r['coworker_name'] as String).toList();
      await txn.update(
        _eventsTable,
        {'attendees': jsonEncode(names)},
        where: 'id = ?',
        whereArgs: [eventId],
      );
    }
  }

  /// Hide or unhide a coworker from the leaderboard without deleting events.
  Future<void> setCoworkerHidden(String name, {required bool hidden}) async {
    final db = await database;
    await db.update(
      _coworkersTable,
      {'hidden': hidden ? 1 : 0},
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [name.trim()],
    );
    _notifyChanged();
  }

  /// Returns all non-hidden coworker names for quick-select tagging chips.
  Future<List<String>> getAllCoworkerNames() async {
    final db = await database;
    final rows = await db.query(
      _coworkersTable,
      where: 'hidden = 0',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Returns all currently hidden coworker names.
  Future<List<String>> getHiddenCoworkerNames() async {
    final db = await database;
    final rows = await db.query(
      _coworkersTable,
      where: 'hidden = 1',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  // ── Stress Queries ──────────────────────────────────────────

  String? _periodCutoffUtc(LeaderboardPeriod period) {
    if (period.window == null) return null;
    return DateTime.now().toUtc().subtract(period.window!).toIso8601String();
  }

  /// Fetch all non-dismissed stress events, most recent first.
  Future<List<StressEvent>> getAllStressEvents({
    bool includeDismissed = false,
  }) async {
    final db = await database;
    final rows = await db.query(
      _eventsTable,
      where: includeDismissed ? null : "user_label != 'dismissed'",
      orderBy: 'timestamp DESC',
    );
    return rows.map((row) => StressEvent.fromMap(row)).toList();
  }

  /// Fetch stress events that do not yet have any tagged coworkers.
  Future<List<StressEvent>> getUntaggedStressEvents() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT e.*
      FROM $_eventsTable e
      LEFT JOIN $_attendeesTable a ON e.id = a.event_id
      WHERE e.user_label != 'dismissed'
      GROUP BY e.id
      HAVING COUNT(a.coworker_name) = 0
      ORDER BY e.timestamp DESC
    ''');
    return rows.map((row) => StressEvent.fromMap(row)).toList();
  }

  /// Fetch stress events associated with a specific coworker (filtered by [period]).
  Future<List<StressEvent>> getEventsForCoworker(
    String name, {
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
  }) async {
    final db = await database;
    final cutoff = _periodCutoffUtc(period);
    final rows = await db.rawQuery(
      cutoff != null
          ? '''
            SELECT e.*
            FROM $_eventsTable e
            INNER JOIN $_attendeesTable a ON e.id = a.event_id
            WHERE a.coworker_name = ? COLLATE NOCASE
              AND e.user_label != 'dismissed'
              AND e.timestamp >= ?
            ORDER BY e.timestamp DESC
            '''
          : '''
            SELECT e.*
            FROM $_eventsTable e
            INNER JOIN $_attendeesTable a ON e.id = a.event_id
            WHERE a.coworker_name = ? COLLATE NOCASE
              AND e.user_label != 'dismissed'
            ORDER BY e.timestamp DESC
            ''',
      cutoff != null ? [name, cutoff] : [name],
    );
    return rows.map((row) => StressEvent.fromMap(row)).toList();
  }

  /// Fetch the N most recent stress events.
  Future<List<StressEvent>> getRecentStressEvents({int limit = 20}) async {
    final db = await database;
    final rows = await db.query(
      _eventsTable,
      where: "user_label != 'dismissed'",
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map((row) => StressEvent.fromMap(row)).toList();
  }

  /// Get the total count of active stress events (optionally within [period]).
  Future<int> getStressEventCount({
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
  }) async {
    final db = await database;
    final cutoff = _periodCutoffUtc(period);

    final result = cutoff != null
        ? await db.rawQuery(
            "SELECT COUNT(*) as count FROM $_eventsTable WHERE user_label != 'dismissed' AND timestamp >= ?",
            [cutoff],
          )
        : await db.rawQuery(
            "SELECT COUNT(*) as count FROM $_eventsTable WHERE user_label != 'dismissed'",
          );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Count active stress events recorded since local midnight today.
  Future<int> getTodayStressEventCount({DateTime? now}) async {
    final db = await database;
    final ref = now ?? DateTime.now();
    final startOfDayUtc =
        DateTime(ref.year, ref.month, ref.day).toUtc().toIso8601String();
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM $_eventsTable WHERE user_label != 'dismissed' AND timestamp >= ?",
      [startOfDayUtc],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Aggregate stress events by coworker using normalized SQL tables.
  Future<List<LeaderboardEntry>> getLeaderboard({
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
  }) async {
    final db = await database;
    final cutoff = _periodCutoffUtc(period);

    final whereClause = cutoff != null
        ? "WHERE e.user_label != 'dismissed' AND COALESCE(c.hidden, 0) = 0 AND e.timestamp >= ?"
        : "WHERE e.user_label != 'dismissed' AND COALESCE(c.hidden, 0) = 0";

    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(c.name, a.coworker_name) AS name,
        COUNT(DISTINCT e.id) AS spike_count,
        AVG(e.peak_hr) AS avg_peak_hr,
        MAX(e.peak_hr) AS max_peak_hr,
        AVG(e.baseline_hr) AS avg_baseline_hr,
        SUM(e.duration_seconds) AS total_duration_seconds,
        MAX(e.timestamp) AS last_seen
      FROM $_attendeesTable a
      INNER JOIN $_eventsTable e ON e.id = a.event_id
      LEFT JOIN $_coworkersTable c ON c.name = a.coworker_name COLLATE NOCASE
      $whereClause
      GROUP BY COALESCE(c.name, a.coworker_name) COLLATE NOCASE
      ORDER BY spike_count DESC, avg_peak_hr DESC
      ''',
      cutoff != null ? [cutoff] : null,
    );

    return rows.map((row) => LeaderboardEntry.fromMap(row)).toList();
  }

  // ── Persisted Heart Rate Summaries ──────────────────────────

  /// Atomically record a real BLE heart rate sample into today's summary.
  Future<void> recordHeartRateSample(
    int bpm, {
    DateTime? timestamp,
    int? restingHr,
    bool notify = true,
  }) async {
    final db = await database;
    final ts = (timestamp ?? DateTime.now()).toLocal();
    final dateKey = _formatDateKey(ts);
    final updatedIso = ts.toUtc().toIso8601String();

    await db.rawInsert(
      '''
      INSERT INTO $_dailyHrTable
        (date, last_hr, min_hr, max_hr, hr_sum, sample_count, resting_hr, updated_at)
      VALUES (?, ?, ?, ?, ?, 1, ?, ?)
      ON CONFLICT(date) DO UPDATE SET
        last_hr = excluded.last_hr,
        min_hr = MIN($_dailyHrTable.min_hr, excluded.min_hr),
        max_hr = MAX($_dailyHrTable.max_hr, excluded.max_hr),
        hr_sum = $_dailyHrTable.hr_sum + excluded.hr_sum,
        sample_count = $_dailyHrTable.sample_count + 1,
        resting_hr = COALESCE(excluded.resting_hr, $_dailyHrTable.resting_hr),
        updated_at = excluded.updated_at
      ''',
      [dateKey, bpm, bpm, bpm, bpm, restingHr, updatedIso],
    );
    if (notify) {
      _notifyChanged();
    }
  }

  Future<DailyHrSummary?> getTodayHrSummary({DateTime? now}) async {
    final db = await database;
    final dateKey = _formatDateKey((now ?? DateTime.now()).toLocal());
    final rows = await db.query(
      _dailyHrTable,
      where: 'date = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailyHrSummary.fromMap(rows.first);
  }

  Future<DailyHrSummary?> getLatestHrSummary() async {
    final db = await database;
    final rows = await db.query(
      _dailyHrTable,
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailyHrSummary.fromMap(rows.first);
  }

  Future<List<DailyHrSummary>> getRecentHrSummaries({int days = 7}) async {
    final db = await database;
    final rows = await db.query(
      _dailyHrTable,
      orderBy: 'date DESC',
      limit: days,
    );
    return rows.map(DailyHrSummary.fromMap).toList();
  }

  /// Returns the average daily HR and average resting HR over the last [days] days.
  Future<({double? avgDailyHr, double? avgRestingHr, int daysCount})>
      getDailyHrAverages({int days = 7}) async {
    final recent = await getRecentHrSummaries(days: days);
    if (recent.isEmpty) {
      return (avgDailyHr: null, avgRestingHr: null, daysCount: 0);
    }
    final avgDaily =
        recent.map((r) => r.avgHr).reduce((a, b) => a + b) / recent.length;
    final restingValues =
        recent.where((r) => r.restingHr != null).map((r) => r.restingHr!);
    final avgResting = restingValues.isEmpty
        ? null
        : restingValues.reduce((a, b) => a + b) / restingValues.length;
    return (
      avgDailyHr: avgDaily,
      avgRestingHr: avgResting,
      daysCount: recent.length,
    );
  }

  // ── Persisted Daily Activity ────────────────────────────────

  Future<void> upsertDailyActivity(DailyActivityRecord record) async {
    final db = await database;
    await db.insert(
      _dailyActivityTable,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _setSyncStateRaw(
      db,
      'last_activity_sync_at',
      record.syncedAt.toUtc().toIso8601String(),
    );
    _notifyChanged();
  }

  Future<DailyActivityRecord?> getTodayActivity({DateTime? now}) async {
    final db = await database;
    final dateKey = _formatDateKey((now ?? DateTime.now()).toLocal());
    final rows = await db.query(
      _dailyActivityTable,
      where: 'date = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailyActivityRecord.fromMap(rows.first);
  }

  Future<DailyActivityRecord?> getLatestActivity() async {
    final db = await database;
    final rows = await db.query(
      _dailyActivityTable,
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailyActivityRecord.fromMap(rows.first);
  }

  Future<List<DailyActivityRecord>> getRecentActivity({int days = 7}) async {
    final db = await database;
    final rows = await db.query(
      _dailyActivityTable,
      orderBy: 'date DESC',
      limit: days,
    );
    return rows.map(DailyActivityRecord.fromMap).toList();
  }

  Future<ActivityAverages> getActivityAverages({int days = 7}) async {
    final recent = await getRecentActivity(days: days);
    if (recent.isEmpty) return ActivityAverages.empty;
    final n = recent.length;
    return ActivityAverages(
      avgSteps: recent.fold<int>(0, (s, r) => s + r.steps) / n,
      avgCalories: recent.fold<int>(0, (s, r) => s + r.calories) / n,
      avgDistanceMeters:
          recent.fold<int>(0, (s, r) => s + r.distanceMeters) / n,
      avgActiveMinutes:
          recent.fold<int>(0, (s, r) => s + r.activeMinutes) / n,
      daysCount: n,
    );
  }

  // ── Persisted Sleep Sessions ────────────────────────────────

  Future<void> upsertSleepSession(SleepSessionRecord record) async {
    final db = await database;
    await db.insert(
      _sleepSessionsTable,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _setSyncStateRaw(
      db,
      'last_sleep_sync_at',
      record.syncedAt.toUtc().toIso8601String(),
    );
    _notifyChanged();
  }

  Future<SleepSessionRecord?> getLatestSleepSession() async {
    final db = await database;
    final rows = await db.query(
      _sleepSessionsTable,
      orderBy: 'date DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SleepSessionRecord.fromMap(rows.first);
  }

  Future<List<SleepSessionRecord>> getRecentSleepSessions({
    int days = 7,
  }) async {
    final db = await database;
    final rows = await db.query(
      _sleepSessionsTable,
      orderBy: 'date DESC',
      limit: days,
    );
    return rows.map(SleepSessionRecord.fromMap).toList();
  }

  Future<SleepAverages> getSleepAverages({int days = 7}) async {
    final recent = await getRecentSleepSessions(days: days);
    if (recent.isEmpty) return SleepAverages.empty;
    final n = recent.length;
    return SleepAverages(
      avgTotalSleepMinutes:
          recent.fold<int>(0, (s, r) => s + r.totalSleepMinutes) / n,
      avgEfficiencyPercent:
          recent.fold<int>(0, (s, r) => s + r.efficiencyPercent) / n,
      avgSleepScore: recent.fold<int>(0, (s, r) => s + r.sleepScore) / n,
      avgDeepMinutes: recent.fold<int>(0, (s, r) => s + r.deepMinutes) / n,
      avgRemMinutes: recent.fold<int>(0, (s, r) => s + r.remMinutes) / n,
      nightsCount: n,
    );
  }

  // ── Device Sync Metadata ────────────────────────────────────

  Future<void> _setSyncStateRaw(Database db, String key, String value) async {
    await db.insert(
      _syncStateTable,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateSyncState(
    String key,
    String value, {
    bool notify = true,
  }) async {
    final db = await database;
    await _setSyncStateRaw(db, key, value);
    if (notify) {
      _notifyChanged();
    }
  }

  Future<DeviceSyncStatus> getDeviceSyncStatus() async {
    final db = await database;
    final rows = await db.query(_syncStateTable);
    final map = <String, String>{
      for (final row in rows)
        row['key'] as String: row['value'] as String,
    };

    DateTime? parseOptDate(String? raw) =>
        raw != null ? DateTime.tryParse(raw)?.toLocal() : null;

    return DeviceSyncStatus(
      lastConnectedAt: parseOptDate(map['last_connected_at']),
      lastDeviceName: map['last_device_name'],
      lastBatteryPercent: map['last_battery_percent'] != null
          ? int.tryParse(map['last_battery_percent']!)
          : null,
      lastBatteryCharging: map['last_battery_charging'] != null
          ? map['last_battery_charging'] == '1'
          : null,
      lastActivitySyncAt: parseOptDate(map['last_activity_sync_at']),
      lastSleepSyncAt: parseOptDate(map['last_sleep_sync_at']),
    );
  }

  // ── Delete & Close ──────────────────────────────────────────

  /// Delete all stress events and coworker records.
  Future<int> clearAll() async {
    final db = await database;
    final deleted = await db.transaction<int>((txn) async {
      await txn.delete(_attendeesTable);
      await txn.delete(_coworkersTable);
      return txn.delete(_eventsTable);
    });
    _notifyChanged();
    return deleted;
  }

  /// Close the database connection.
  Future<void> close() async {
    await _changesController.close();
    await _database?.close();
    _database = null;
    _initCompleter = null;
  }

  static String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
