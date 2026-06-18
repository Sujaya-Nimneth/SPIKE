import 'package:device_calendar/device_calendar.dart';

/// Service for reading local calendar events from the device.
///
/// Used by the StressAnalyzerService to find the currently active meeting
/// when a stress event triggers.
class CalendarService {
  /// Singleton instance.
  static final CalendarService _instance = CalendarService._internal();
  factory CalendarService() => _instance;
  CalendarService._internal();

  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  bool _permissionsGranted = false;

  // ── Permissions ─────────────────────────────────────────────

  /// Request calendar read permissions from the user.
  Future<bool> requestPermissions() async {
    final result = await _plugin.requestPermissions();
    _permissionsGranted = result.isSuccess && (result.data ?? false);
    return _permissionsGranted;
  }

  /// Check whether calendar permissions have been granted.
  Future<bool> hasPermissions() async {
    final result = await _plugin.hasPermissions();
    _permissionsGranted = result.isSuccess && (result.data ?? false);
    return _permissionsGranted;
  }

  // ── Calendars ───────────────────────────────────────────────

  /// Retrieve all calendars available on the device.
  Future<List<Calendar>> getCalendars() async {
    if (!_permissionsGranted) {
      final granted = await requestPermissions();
      if (!granted) return [];
    }

    final result = await _plugin.retrieveCalendars();
    if (result.isSuccess && result.data != null) {
      return result.data!;
    }
    return [];
  }

  // ── Events ──────────────────────────────────────────────────

  /// Fetch events from a specific calendar within a date range.
  Future<List<Event>> getEvents(
    String calendarId, {
    required DateTime start,
    required DateTime end,
  }) async {
    if (!_permissionsGranted) {
      final granted = await requestPermissions();
      if (!granted) return [];
    }

    final params = RetrieveEventsParams(
      startDate: start,
      endDate: end,
    );

    final result = await _plugin.retrieveEvents(calendarId, params);
    if (result.isSuccess && result.data != null) {
      return result.data!;
    }
    return [];
  }

  /// Fetch today's events from all calendars.
  Future<List<Event>> getTodayEvents() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _getEventsFromAllCalendars(startOfDay, endOfDay);
  }

  /// Fetch upcoming events for the next N days across all calendars.
  Future<List<Event>> getUpcomingEvents({int days = 7}) async {
    final now = DateTime.now();
    final end = now.add(Duration(days: days));

    return _getEventsFromAllCalendars(now, end);
  }

  // ── Meeting Lookup (used by StressAnalyzer) ─────────────────

  /// Find ALL currently active meetings and merge their attendees.
  ///
  /// Searches all calendars for events where `now` falls between
  /// the event's start and end time. If multiple overlapping events
  /// exist, their titles are joined and attendees are deduplicated.
  /// Returns `null` if no meeting is currently active.
  Future<CurrentMeeting?> getCurrentMeeting() async {
    final now = DateTime.now();

    // Search a narrow window: events from 1 hour ago to 1 hour ahead
    // to reduce query scope while catching any active meeting.
    final searchStart = now.subtract(const Duration(hours: 1));
    final searchEnd = now.add(const Duration(hours: 1));

    final allEvents = await _getEventsFromAllCalendars(searchStart, searchEnd);

    // Collect ALL currently active events (not just the first)
    final activeEvents = allEvents.where((event) {
      final start = event.start;
      final end = event.end;
      if (start == null || end == null) return false;
      return now.isAfter(start) && now.isBefore(end);
    }).toList();

    if (activeEvents.isEmpty) return null;

    // Merge titles and deduplicate attendees from all active events
    final titles = activeEvents
        .map((e) => e.title ?? 'Untitled')
        .toList();
    final allAttendees = <String>{};
    for (final event in activeEvents) {
      final attendees = (event.attendees ?? [])
          .where((a) => a?.name != null && a!.name!.isNotEmpty)
          .map((a) => a!.name!);
      allAttendees.addAll(attendees);
    }

    return CurrentMeeting(
      title: titles.join(' + '),
      attendees: allAttendees.toList(),
      start: activeEvents.first.start!,
      end: activeEvents.first.end!,
    );
  }

  // ── Private Helpers ─────────────────────────────────────────

  /// Fetch events from all calendars within the given date range.
  Future<List<Event>> _getEventsFromAllCalendars(
    DateTime start,
    DateTime end,
  ) async {
    final calendars = await getCalendars();
    final allEvents = <Event>[];

    for (final calendar in calendars) {
      if (calendar.id == null) continue;
      final events = await getEvents(calendar.id!, start: start, end: end);
      allEvents.addAll(events);
    }

    // Sort by start time
    allEvents.sort((a, b) {
      final aStart = a.start ?? DateTime(2000);
      final bStart = b.start ?? DateTime(2000);
      return aStart.compareTo(bStart);
    });

    return allEvents;
  }
}

/// A snapshot of the currently active meeting(s).
class CurrentMeeting {
  final String title;
  final List<String> attendees;
  final DateTime start;
  final DateTime end;

  const CurrentMeeting({
    required this.title,
    required this.attendees,
    required this.start,
    required this.end,
  });

  @override
  String toString() =>
      'CurrentMeeting($title, attendees: $attendees)';
}
