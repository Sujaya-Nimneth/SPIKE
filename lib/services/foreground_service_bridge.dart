import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils/app_logger.dart';

/// Platform bridge to start, update, and stop the Android `connectedDevice`
/// foreground service while the smart ring is connected.
///
/// Safe no-op on non-Android platforms and under unit/widget tests where no
/// platform channel handler is registered.
class ForegroundServiceBridge {
  static const _tag = 'FgService';
  static const MethodChannel _channel =
      MethodChannel('com.smartring.smart_ring/ble_foreground_service');

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> start({
    String title = 'Spike · Ring Connected',
    String text = 'Streaming heart rate & stress telemetry',
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('startService', {
        'title': title,
        'text': text,
      });
    } on MissingPluginException {
      // Expected in unit/widget tests.
    } catch (e) {
      AppLogger.warn(_tag, 'Failed to start foreground service', e);
    }
  }

  Future<void> update({
    required String title,
    required String text,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('updateNotification', {
        'title': title,
        'text': text,
      });
    } on MissingPluginException {
      // Expected in unit/widget tests.
    } catch (e) {
      AppLogger.warn(_tag, 'Failed to update foreground notification', e);
    }
  }

  Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopService');
    } on MissingPluginException {
      // Expected in unit/widget tests.
    } catch (e) {
      AppLogger.warn(_tag, 'Failed to stop foreground service', e);
    }
  }
}
