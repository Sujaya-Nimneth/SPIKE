import 'dart:async';

/// Manages active manual meeting context for stress event correlation.
///
/// Since Spike uses privacy-first manual tagging (no device calendar
/// permissions required), users can optionally start an active meeting
/// session with selected coworkers—or tag coworkers on detected stress
/// events after the fact.
class CalendarService {
  CalendarService();

  CurrentMeeting? _activeMeeting;
  final _meetingController = StreamController<CurrentMeeting?>.broadcast();

  /// Stream of active manual meeting changes.
  Stream<CurrentMeeting?> get activeMeetingStream => _meetingController.stream;

  /// Currently active manual meeting session, if any.
  CurrentMeeting? get activeMeeting => _activeMeeting;

  /// Start a live meeting session with the specified [attendees] and optional [title].
  ///
  /// Any stress episode detected while this session is active will automatically
  /// be tagged with these coworkers.
  CurrentMeeting startMeetingSession({
    required List<String> attendees,
    String? title,
    Duration maxDuration = const Duration(hours: 2),
  }) {
    final now = DateTime.now();
    final cleanAttendees = attendees
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toSet()
        .toList();

    final meetingTitle = (title == null || title.trim().isEmpty)
        ? 'Meeting with ${cleanAttendees.join(', ')}'
        : title.trim();

    _activeMeeting = CurrentMeeting(
      title: meetingTitle,
      attendees: cleanAttendees,
      start: now,
      end: now.add(maxDuration),
    );

    if (!_meetingController.isClosed) {
      _meetingController.add(_activeMeeting);
    }
    return _activeMeeting!;
  }

  /// End the currently active manual meeting session.
  void endMeetingSession() {
    _activeMeeting = null;
    if (!_meetingController.isClosed) {
      _meetingController.add(null);
    }
  }

  /// Returns the currently active meeting session if it has not expired.
  Future<CurrentMeeting?> getCurrentMeeting() async {
    final current = _activeMeeting;
    if (current == null) return null;
    if (DateTime.now().isAfter(current.end)) {
      endMeetingSession();
      return null;
    }
    return current;
  }

  void dispose() {
    _meetingController.close();
  }
}

/// A snapshot of an active meeting session and its tagged coworkers.
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
  String toString() => 'CurrentMeeting($title, attendees: $attendees)';
}
