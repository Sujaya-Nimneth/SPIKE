/// Safely extract initials from a full name or email (e.g. "John Doe" → "JD").
///
/// Guards against empty or whitespace-only strings to prevent [RangeError].
String getInitials(String name) {
  final cleaned = name.trim();
  if (cleaned.isEmpty) return '?';

  final target =
      cleaned.contains('@') ? cleaned.split('@').first.trim() : cleaned;
  if (target.isEmpty) return '?';

  final parts = target
      .split(RegExp(r'[\s._-]+'))
      .where((part) => part.isNotEmpty)
      .toList();

  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  final firstChar = parts.first.substring(0, 1);
  final lastChar = parts.last.substring(0, 1);
  return '$firstChar$lastChar'.toUpperCase();
}

/// Truncate a name to first name only for compact podium display.
String truncateName(String name) {
  final cleaned = name.trim();
  if (cleaned.isEmpty) return 'Unknown';
  final parts =
      cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return cleaned;
  return parts.first;
}

/// Format a coworker display name respecting [privacyMode].
String formatCoworkerName(
  String name, {
  required bool privacyMode,
  bool prefixCoworker = true,
}) {
  if (!privacyMode) return name;
  final initials = getInitials(name);
  return prefixCoworker ? 'Coworker $initials' : initials;
}
