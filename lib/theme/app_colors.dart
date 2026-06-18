import 'dart:ui';

/// Oura-inspired deep dark-mode color palette with pastel accents.
class AppColors {
  AppColors._();

  // ── Backgrounds ──────────────────────────────────────────────
  static const Color background = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF141419);
  static const Color surfaceVariant = Color(0xFF1C1C24);
  static const Color surfaceLight = Color(0xFF24242E);

  // ── Pastel Accents ───────────────────────────────────────────
  static const Color pastelTeal = Color(0xFF5ECFCA);
  static const Color pastelCoral = Color(0xFFE8857A);
  static const Color pastelAmber = Color(0xFFF0C75E);
  static const Color pastelSage = Color(0xFF8FBF9F);
  static const Color pastelLavender = Color(0xFFB4A7D6);
  static const Color pastelBlue = Color(0xFF6FA8DC);

  // ── Text ─────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0F0F5);
  static const Color textSecondary = Color(0xFF8A8A9A);
  static const Color textTertiary = Color(0xFF5A5A6A);

  // ── Navigation ───────────────────────────────────────────────
  static const Color navActive = pastelTeal;
  static const Color navInactive = Color(0xFF4A4A5A);
  static const Color navBarBackground = Color(0xFF0E0E14);

  // ── Misc ─────────────────────────────────────────────────────
  static const Color divider = Color(0xFF2A2A34);
  static const Color cardBorder = Color(0xFF2A2A34);
  static const Color shimmer = Color(0xFF3A3A44);
}
