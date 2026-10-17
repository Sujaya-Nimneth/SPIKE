/// Zero-dependency date and time formatting helpers for Spike UI.
class DateFormatter {
  DateFormatter._();

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> _shortWeekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _shortMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Formats a date as e.g. "Saturday, Oct 17".
  static String formatHeaderDate(DateTime date) {
    final weekday = _weekdays[(date.weekday - 1).clamp(0, 6)];
    final month = _shortMonths[(date.month - 1).clamp(0, 11)];
    return '$weekday, $month ${date.day}';
  }

  /// Formats a timestamp as e.g. "Oct 17 · 2:30 PM".
  static String formatShortDateTime(DateTime date) {
    final month = _shortMonths[(date.month - 1).clamp(0, 11)];
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$month ${date.day} · $hour12:$minute $period';
  }

  /// Formats a relative time string such as "Just now", "12m ago", "3h ago", "2d ago".
  static String formatRelative(DateTime timestamp, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final month = _shortMonths[(timestamp.month - 1).clamp(0, 11)];
    return '$month ${timestamp.day}';
  }

  /// Returns the last 7 short weekday labels ending with [today].
  static List<String> lastSevenDayLabels([DateTime? today]) {
    final ref = today ?? DateTime.now();
    return List.generate(7, (index) {
      final day = ref.subtract(Duration(days: 6 - index));
      return _shortWeekdays[(day.weekday - 1).clamp(0, 6)];
    });
  }
}
