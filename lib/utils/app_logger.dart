import 'package:flutter/foundation.dart';

/// Centralized lightweight logger for Spike.
///
/// Logs are only emitted in debug mode unless [verboseLogging] is enabled.
class AppLogger {
  AppLogger._();

  /// Toggle verbose telemetry logging (e.g. raw BLE scan packets).
  static bool verboseLogging = false;

  static void info(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  static void verbose(String tag, String message) {
    if (kDebugMode && verboseLogging) {
      debugPrint('[$tag][V] $message');
    }
  }

  static void warn(String tag, String message, [Object? error]) {
    if (kDebugMode) {
      debugPrint('[$tag][WARN] $message${error != null ? ': $error' : ''}');
    }
  }

  static void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (kDebugMode) {
      debugPrint('[$tag][ERROR] $message${error != null ? ': $error' : ''}');
      if (stackTrace != null && verboseLogging) {
        debugPrint(stackTrace.toString());
      }
    }
  }
}
