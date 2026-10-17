import 'dart:convert';

/// User confirmation status for a recorded stress episode.
enum StressEventLabel {
  unconfirmed('unconfirmed'),
  confirmed('confirmed'),
  dismissed('dismissed');

  final String value;
  const StressEventLabel(this.value);

  static StressEventLabel fromString(String? raw) {
    for (final item in StressEventLabel.values) {
      if (item.value == raw) return item;
    }
    return StressEventLabel.unconfirmed;
  }
}

/// A recorded stress episode with associated meeting/coworker context.
class StressEvent {
  final int? id;
  final DateTime timestamp;
  final int peakHr;
  final int meanHr;
  final int baselineHr;
  final String? meetingTitle;
  final List<String> attendees;
  final int durationSeconds;
  final double stressLoad;
  final StressEventLabel label;

  const StressEvent({
    this.id,
    required this.timestamp,
    required this.peakHr,
    int? meanHr,
    required this.baselineHr,
    this.meetingTitle,
    this.attendees = const [],
    required this.durationSeconds,
    this.stressLoad = 0.0,
    this.label = StressEventLabel.unconfirmed,
  }) : meanHr = meanHr ?? peakHr;

  /// Elevation above baseline in BPM.
  int get elevationBpm => peakHr - baselineHr;

  /// Percentage elevation above baseline (e.g. 28 for +28%).
  int get elevationPercent =>
      baselineHr > 0 ? (((peakHr - baselineHr) / baselineHr) * 100).round() : 0;

  /// Whether this event has at least one tagged coworker.
  bool get isTagged => attendees.isNotEmpty;

  StressEvent copyWith({
    int? id,
    DateTime? timestamp,
    int? peakHr,
    int? meanHr,
    int? baselineHr,
    String? meetingTitle,
    List<String>? attendees,
    int? durationSeconds,
    double? stressLoad,
    StressEventLabel? label,
  }) {
    return StressEvent(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      peakHr: peakHr ?? this.peakHr,
      meanHr: meanHr ?? this.meanHr,
      baselineHr: baselineHr ?? this.baselineHr,
      meetingTitle: meetingTitle ?? this.meetingTitle,
      attendees: attendees ?? this.attendees,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      stressLoad: stressLoad ?? this.stressLoad,
      label: label ?? this.label,
    );
  }

  /// Serialize to a SQLite-compatible map.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.toIso8601String(),
      'peak_hr': peakHr,
      'mean_hr': meanHr,
      'baseline_hr': baselineHr,
      'meeting_title': meetingTitle,
      'attendees': jsonEncode(attendees),
      'duration_seconds': durationSeconds,
      'stress_load': stressLoad,
      'user_label': label.value,
    };
  }

  /// Deserialize from a SQLite row (supports both v1 and v2 schemas).
  factory StressEvent.fromMap(Map<String, dynamic> map) {
    List<String> parseAttendees(dynamic raw) {
      if (raw == null || raw == '') return [];
      try {
        final decoded = jsonDecode(raw as String);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
      return [];
    }

    final peak = map['peak_hr'] as int;
    final mean = (map['mean_hr'] as int?) ?? peak;
    final load = (map['stress_load'] as num?)?.toDouble() ?? 0.0;

    return StressEvent(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      peakHr: peak,
      meanHr: mean,
      baselineHr: map['baseline_hr'] as int,
      meetingTitle: map['meeting_title'] as String?,
      attendees: parseAttendees(map['attendees']),
      durationSeconds: map['duration_seconds'] as int,
      stressLoad: load,
      label: StressEventLabel.fromString(map['user_label'] as String?),
    );
  }

  @override
  String toString() =>
      'StressEvent(id: $id, peak: $peakHr, baseline: $baselineHr, '
      'meeting: $meetingTitle, attendees: $attendees)';
}
