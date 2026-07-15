/// Service for reading local calendar events from the device.
///
/// Used by the StressAnalyzerService to find the currently active meeting
/// when a stress event triggers.
///
/// NOTE: The `device_calendar` plugin has been removed due to AGP 9
/// incompatibility. This is a no-op stub that preserves the public API.
/// Replace with a modern calendar plugin when one becomes available.
class CalendarService {
  /// Singleton instance.
  static final CalendarService _instance = CalendarService._internal();
  factory CalendarService() => _instance;
  CalendarService._internal();

  // ── Permissions ─────────────────────────────────────────────

  /// Request calendar read permissions from the user.
  Future<bool> requestPermissions() async => false;

  /// Check whether calendar permissions have been granted.
  Future<bool> hasPermissions() async => false;

  // ── Calendars ───────────────────────────────────────────────

  /// Retrieve all calendars available on the device.
  Future<List<dynamic>> getCalendars() async => [];

  // ── Events ──────────────────────────────────────────────────

  /// Fetch events from a specific calendar within a date range.
  Future<List<dynamic>> getEvents(
    String calendarId, {
    required DateTime start,
    required DateTime end,
  }) async => [];

  /// Fetch today's events from all calendars.
  Future<List<dynamic>> getTodayEvents() async => [];

  /// Fetch upcoming events for the next N days across all calendars.
  Future<List<dynamic>> getUpcomingEvents({int days = 7}) async => [];

  // ── Meeting Lookup (used by StressAnalyzer) ─────────────────

  /// Find ALL currently active meetings and merge their attendees.
  ///
  /// Returns `null` — calendar integration is currently disabled.
  Future<CurrentMeeting?> getCurrentMeeting() async => null;
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
