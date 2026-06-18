import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/stress_event.dart';
import '../models/leaderboard_entry.dart';

/// SQLite database service for storing and querying stress events.
class DatabaseService {
  static const _dbName = 'stress_events.db';
  static const _dbVersion = 1;
  static const _tableName = 'stress_events';

  Database? _database;

  /// Completer to prevent double-initialization race condition.
  /// If two callers hit `database` simultaneously before init completes,
  /// only one will call `_initDatabase()` and the other will wait on
  /// this completer.
  Completer<Database>? _initCompleter;

  /// Open (or create) the database. Must be called before any queries.
  ///
  /// Uses a [Completer] to ensure single-initialization even under
  /// concurrent access from the stress analyzer (writing) and the
  /// leaderboard UI (reading) simultaneously.
  Future<Database> get database async {
    if (_database != null) return _database!;

    // If another caller is already initializing, wait for it
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
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            peak_hr INTEGER NOT NULL,
            baseline_hr INTEGER NOT NULL,
            meeting_title TEXT,
            attendees TEXT,
            duration_seconds INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  // ── Insert ──────────────────────────────────────────────────

  /// Insert a new stress event into the database.
  Future<int> insertStressEvent(StressEvent event) async {
    final db = await database;
    return db.insert(_tableName, event.toMap());
  }

  // ── Query ───────────────────────────────────────────────────

  /// Fetch all stress events, most recent first.
  Future<List<StressEvent>> getAllStressEvents() async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      orderBy: 'timestamp DESC',
    );
    return rows.map((row) => StressEvent.fromMap(row)).toList();
  }

  /// Fetch the N most recent stress events.
  Future<List<StressEvent>> getRecentStressEvents({int limit = 20}) async {
    final db = await database;
    final rows = await db.query(
      _tableName,
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map((row) => StressEvent.fromMap(row)).toList();
  }

  /// Get the total count of stress events.
  Future<int> getStressEventCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ── Leaderboard Aggregation ─────────────────────────────────

  /// Aggregate stress events by attendee name, ranking coworkers by
  /// how many HR spikes they are associated with.
  ///
  /// This explodes the JSON attendees array, counts spikes per person,
  /// and returns results sorted by spike count descending.
  Future<List<LeaderboardEntry>> getLeaderboard() async {
    final db = await database;

    // SQLite doesn't natively support JSON array iteration, so we
    // fetch all events and aggregate in Dart.
    final rows = await db.query(
      _tableName,
      orderBy: 'timestamp DESC',
    );

    // Aggregate: attendee name → list of (peakHr, timestamp)
    final Map<String, List<({int peakHr, DateTime timestamp})>> agg = {};

    for (final row in rows) {
      final attendeesRaw = row['attendees'] as String?;
      if (attendeesRaw == null || attendeesRaw.isEmpty) continue;

      List<String> attendees;
      try {
        final decoded = jsonDecode(attendeesRaw);
        if (decoded is List) {
          attendees = decoded.cast<String>();
        } else {
          continue;
        }
      } catch (_) {
        continue;
      }

      final peakHr = row['peak_hr'] as int;
      final timestamp = DateTime.parse(row['timestamp'] as String);

      for (final name in attendees) {
        if (name.isEmpty) continue;
        agg.putIfAbsent(name, () => []);
        agg[name]!.add((peakHr: peakHr, timestamp: timestamp));
      }
    }

    // Build leaderboard entries
    final entries = agg.entries.map((entry) {
      final spikes = entry.value;
      final totalHr = spikes.fold<int>(0, (sum, s) => sum + s.peakHr);
      final avgHr = totalHr / spikes.length;
      final lastSeen = spikes.first.timestamp; // already sorted DESC

      return LeaderboardEntry(
        name: entry.key,
        spikeCount: spikes.length,
        avgPeakHr: avgHr,
        lastSeen: lastSeen,
      );
    }).toList();

    // Sort by spike count descending, then by avg peak HR descending
    entries.sort((a, b) {
      final countCmp = b.spikeCount.compareTo(a.spikeCount);
      if (countCmp != 0) return countCmp;
      return b.avgPeakHr.compareTo(a.avgPeakHr);
    });

    return entries;
  }

  // ── Delete ──────────────────────────────────────────────────

  /// Delete all stress events.
  Future<int> clearAll() async {
    final db = await database;
    return db.delete(_tableName);
  }

  /// Close the database connection.
  Future<void> close() async {
    await _database?.close();
    _database = null;
    _initCompleter = null;
  }
}
