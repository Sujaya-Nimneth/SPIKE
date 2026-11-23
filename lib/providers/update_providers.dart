import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_release_info.dart';
import '../services/app_update_service.dart';

/// Singleton [AppUpdateService] backed by GitHub Releases.
final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService();
});

/// Installed app version string (queried natively on Android).
final installedAppVersionProvider = FutureProvider<String>((ref) async {
  return ref.read(appUpdateServiceProvider).getInstalledVersion();
});

/// Performs a single non-blocking update check shortly after app startup on Android.
///
/// Errors are swallowed so offline launches remain completely silent.
final autoUpdateCheckProvider = FutureProvider<UpdateCheckResult?>((ref) async {
  if (kIsWeb || !Platform.isAndroid) {
    return null;
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  final result = await ref.read(appUpdateServiceProvider).checkForUpdate();
  return result.hasUpdate ? result : null;
});
