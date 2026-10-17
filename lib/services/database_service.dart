import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/stress_event.dart';
import '../models/leaderboard_entry.dart';

/// SQLite database service for storing and querying stress events,
/// coworker profiles, and normalized event-attendee relationships.
class DatabaseService {
  static const _dbName = 'stress_events.db';
  static const _dbVersion = 2;
  static const _eventsTable = 'stress_events';
  static const _attendeesTable = 'event_attendees';
  static const _coworkersTable = 'coworkers';

  Database? _database;
  Completer<Database>? _initCompleter;

  final _changesController = StreamController<void>.broadcast();

  /// Broadcast stream that emits whenever stress events or coworker tags change.
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
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createV2Schema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateV1ToV2(db);
        }
      },
    );
  }

  Future<void> _createV2Schema(Database db) async {
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
        name TEXT PRIMARY KEY,
        hidden INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $_attendeesTable (
        event_id INTEGER NOT NULL,
        coworker_name TEXT NOT NULL,
        PRIMARY KEY (event_id, coworker_name)
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_stress_events_timestamp ON $_eventsTable(timestamp DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_event_attendees_name ON $_attendeesTable(coworker_name)',
    );
  }

  Future<void> _migrateV1ToV2(Database db) async {
    // Add v2 columns to existing stress_events table
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

    // Backfill normalized attendees table from legacy JSON column
    final rows = await db.query(_eventsTable);
    final nowIso = DateTime.now().toIso8601String();
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

  // ── Insert & Update ─────────────────────────────────────────

  /// Insert a new stress event and normalize its attendees.
  Future<int> insertStressEvent(StressEvent event) async {
    final db = await database;
    final cleanAttendees = _normalizeNames(event.attendees);
    final normalizedEvent = event.copyWith(attendees: cleanAttendees);

    final eventId = await db.transaction<int>((txn) async {
      final id = await txn.insert(_eventsTable, normalizedEvent.toMap());
      await _syncEventAttendeesTxn(txn, id, cleanAttendees);
      return id;
    });

    _notifyChanged();
    return eventId;
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
      final updates = <String, dynamic>{
        'attendees': jsonEncode(cleanAttendees),
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
      await _syncEventAttendeesTxn(txn, eventId, cleanAttendees);
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

  /// Delete a single stress event by ID.
  Future<void> deleteStressEvent(int eventId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        _attendeesTable,
        where: 'event_id = ?',
        whereArgs: [eventId],
      );
      await txn.delete(
        _eventsTable,
        where: 'id = ?',
        whereArgs: [eventId],
      );
    });
    _notifyChanged();
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

    final nowIso = DateTime.now().toIso8601String();
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

  /// Add a coworker to the directory for quick tagging.
  Future<void> addCoworker(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final db = await database;
    await db.insert(
      _coworkersTable,
      {
        'name': trimmed,
        'hidden': 0,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
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
      await txn.insert(
        _coworkersTable,
        {
          'name': cleanNew,
          'hidden': 0,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      final affectedRows = await txn.query(
        _attendeesTable,
        where: 'coworker_name = ?',
        whereArgs: [cleanOld],
      );

      for (final row in affectedRows) {
        final eventId = row['event_id'] as int;
        await txn.insert(
          _attendeesTable,
          {'event_id': eventId, 'coworker_name': cleanNew},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await txn.delete(
        _attendeesTable,
        where: 'coworker_name = ?',
        whereArgs: [cleanOld],
      );
      await txn.delete(
        _coworkersTable,
        where: 'name = ?',
        whereArgs: [cleanOld],
      );

      // Update JSON column on affected events for consistency
      for (final row in affectedRows) {
        final eventId = row['event_id'] as int;
        final currentAttendees = await txn.query(
          _attendeesTable,
          where: 'event_id = ?',
          whereArgs: [eventId],
        );
        final names = currentAttendees
            .map((r) => r['coworker_name'] as String)
            .toList();
        await txn.update(
          _eventsTable,
          {'attendees': jsonEncode(names)},
          where: 'id = ?',
          whereArgs: [eventId],
        );
      }
    });

    _notifyChanged();
  }

  /// Hide a coworker from the leaderboard without deleting historical events.
  Future<void> setCoworkerHidden(String name, {required bool hidden}) async {
    final db = await database;
    await db.update(
      _coworkersTable,
      {'hidden': hidden ? 1 : 0},
      where: 'name = ?',
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

  // ── Queries ─────────────────────────────────────────────────

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

  /// Fetch all stress events associated with a specific coworker.
  Future<List<StressEvent>> getEventsForCoworker(String name) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT e.*
      FROM $_eventsTable e
      INNER JOIN $_attendeesTable a ON e.id = a.event_id
      WHERE a.coworker_name = ? AND e.user_label != 'dismissed'
      ORDER BY e.timestamp DESC
      ''',
      [name],
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
    final cutoff = period.window != null
        ? DateTime.now().subtract(period.window!).toIso8601String()
        : null;

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

  // ── Leaderboard Aggregation (SQL-backed) ────────────────────

  /// Aggregate stress events by coworker using normalized SQL tables,
  /// ranked by raw spike count descending, then average peak HR descending.
  Future<List<LeaderboardEntry>> getLeaderboard({
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
  }) async {
    final db = await database;
    final cutoff = period.window != null
        ? DateTime.now().subtract(period.window!).toIso8601String()
        : null;

    final whereClause = cutoff != null
        ? "WHERE e.user_label != 'dismissed' AND COALESCE(c.hidden, 0) = 0 AND e.timestamp >= ?"
        : "WHERE e.user_label != 'dismissed' AND COALESCE(c.hidden, 0) = 0";

    final rows = await db.rawQuery(
      '''
      SELECT
        a.coworker_name AS name,
        COUNT(DISTINCT e.id) AS spike_count,
        AVG(e.peak_hr) AS avg_peak_hr,
        MAX(e.peak_hr) AS max_peak_hr,
        AVG(e.baseline_hr) AS avg_baseline_hr,
        SUM(e.duration_seconds) AS total_duration_seconds,
        MAX(e.timestamp) AS last_seen
      FROM $_attendeesTable a
      INNER JOIN $_eventsTable e ON e.id = a.event_id
      LEFT JOIN $_coworkersTable c ON c.name = a.coworker_name
      $whereClause
      GROUP BY a.coworker_name
      ORDER BY spike_count DESC, avg_peak_hr DESC
      ''',
      cutoff != null ? [cutoff] : null,
    );

    return rows.map((row) => LeaderboardEntry.fromMap(row)).toList();
  }

  // ── Delete ──────────────────────────────────────────────────

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
}
