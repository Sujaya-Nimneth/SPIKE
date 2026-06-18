import 'dart:convert';

/// A recorded stress event with associated meeting context.
class StressEvent {
  final int? id;
  final DateTime timestamp;
  final int peakHr;
  final int baselineHr;
  final String? meetingTitle;
  final List<String> attendees;
  final int durationSeconds;

  const StressEvent({
    this.id,
    required this.timestamp,
    required this.peakHr,
    required this.baselineHr,
    this.meetingTitle,
    this.attendees = const [],
    required this.durationSeconds,
  });

  /// Serialize to a SQLite-compatible map.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
      'peak_hr': peakHr,
      'baseline_hr': baselineHr,
      'meeting_title': meetingTitle,
      'attendees': jsonEncode(attendees),
      'duration_seconds': durationSeconds,
    };
  }

  /// Deserialize from a SQLite row.
  factory StressEvent.fromMap(Map<String, dynamic> map) {
    List<String> parseAttendees(dynamic raw) {
      if (raw == null || raw == '') return [];
      try {
        final decoded = jsonDecode(raw as String);
        if (decoded is List) {
          return decoded.cast<String>();
        }
      } catch (_) {}
      return [];
    }

    return StressEvent(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      peakHr: map['peak_hr'] as int,
      baselineHr: map['baseline_hr'] as int,
      meetingTitle: map['meeting_title'] as String?,
      attendees: parseAttendees(map['attendees']),
      durationSeconds: map['duration_seconds'] as int,
    );
  }

  @override
  String toString() =>
      'StressEvent(peak: $peakHr, baseline: $baselineHr, '
      'meeting: $meetingTitle, attendees: $attendees)';
}
