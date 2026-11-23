import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_release_info.dart';
import '../utils/app_logger.dart';

typedef UpdateProgressCallback = void Function(
  double progress,
  int receivedBytes,
  int totalBytes,
);

/// Checks GitHub Releases for newer signed Android APKs and triggers
/// in-place installation via the native Android [FileProvider] bridge.
class AppUpdateService {
  static const String defaultOwner = 'Sujaya-Nimneth';
  static const String defaultRepo = 'SPIKE';
  static const String fallbackVersion = '1.0.0';

  static const MethodChannel _channel = MethodChannel(
    'com.smartring.smart_ring/app_updater',
  );

  final String owner;
  final String repo;

  AppUpdateService({
    this.owner = defaultOwner,
    this.repo = defaultRepo,
  });

  Uri get _latestReleaseUri => Uri.https(
        'api.github.com',
        '/repos/$owner/$repo/releases/latest',
      );

  /// Reads the currently installed version name from Android's `PackageManager`
  /// (or falls back to [fallbackVersion] on non-Android platforms/tests).
  Future<String> getInstalledVersion() async {
    if (kIsWeb || !Platform.isAndroid) {
      return fallbackVersion;
    }
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>(
        'getAppVersion',
      );
      final name = (info?['versionName'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        return name;
      }
    } catch (e) {
      AppLogger.w('Updater', 'Failed to query installed version: $e');
    }
    return fallbackVersion;
  }

  /// Queries GitHub's `/releases/latest` endpoint and compares its tag against
  /// the installed version.
  Future<UpdateCheckResult> checkForUpdate() async {
    final currentVersion = await getInstalledVersion();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client
          .getUrl(_latestReleaseUri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set('X-GitHub-Api-Version', '2022-11-28');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Spike-App-Updater/$currentVersion',
      );

      final response = await request
          .close()
          .timeout(const Duration(seconds: 12));
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == HttpStatus.notFound) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.noReleaseFound,
          currentVersion: currentVersion,
        );
      }

      if (response.statusCode != HttpStatus.ok) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          currentVersion: currentVersion,
          errorMessage: 'GitHub returned HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          currentVersion: currentVersion,
          errorMessage: 'Unexpected response from GitHub Releases.',
        );
      }

      final release = AppReleaseInfo.fromGitHubJson(decoded);
      if (release == null) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.noReleaseFound,
          currentVersion: currentVersion,
        );
      }

      final hasNewer = AppReleaseInfo.isNewerVersion(
        release.version,
        currentVersion,
      );
      return UpdateCheckResult(
        status: hasNewer
            ? UpdateCheckStatus.updateAvailable
            : UpdateCheckStatus.upToDate,
        currentVersion: currentVersion,
        release: release,
      );
    } catch (e) {
      AppLogger.w('Updater', 'Update check failed: $e');
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        currentVersion: currentVersion,
        errorMessage: _friendlyError(e),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads [release]'s APK into the app's private update cache directory,
  /// validates the ZIP/APK signature header, and launches Android's installer.
  Future<UpdateInstallResult> downloadAndInstall(
    AppReleaseInfo release, {
    UpdateProgressCallback? onProgress,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const UpdateInstallResult(
        status: UpdateInstallStatus.error,
        errorMessage: 'In-app APK installation is only supported on Android.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    File? partFile;

    try {
      final cacheDirPath = await _channel.invokeMethod<String>(
        'getUpdateCacheDir',
      );
      if (cacheDirPath == null || cacheDirPath.isEmpty) {
        return const UpdateInstallResult(
          status: UpdateInstallStatus.error,
          errorMessage: 'Could not access update cache directory.',
        );
      }

      final safeVersion = release.version.replaceAll(
        RegExp(r'[^0-9A-Za-z._-]'),
        '_',
      );
      final targetPath = '$cacheDirPath/spike-$safeVersion.apk';
      partFile = File('$targetPath.part');
      final targetFile = File(targetPath);

      // Clean stale APKs from previous updates.
      await _cleanCacheDir(Directory(cacheDirPath), keepPath: targetPath);

      final uri = Uri.parse(release.apkDownloadUrl);
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(HttpHeaders.userAgentHeader, 'Spike-App-Updater');

      final response = await request
          .close()
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        return UpdateInstallResult(
          status: UpdateInstallStatus.error,
          errorMessage: 'Download failed (HTTP ${response.statusCode}).',
        );
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : release.apkSizeBytes;
      var receivedBytes = 0;

      final sink = partFile.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          final progress = totalBytes > 0
              ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
              : 0.0;
          onProgress?.call(progress, receivedBytes, totalBytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      // Validate the downloaded file is a non-empty APK (ZIP magic: PK\x03\x04).
      final isValid = await _isValidApkFile(partFile);
      if (!isValid) {
        if (await partFile.exists()) {
          await partFile.delete();
        }
        return const UpdateInstallResult(
          status: UpdateInstallStatus.error,
          errorMessage: 'Downloaded file is incomplete or corrupted.',
        );
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetPath);
      partFile = null;

      return installLocalApk(targetPath);
    } catch (e) {
      AppLogger.e('Updater', 'APK download/install failed', e);
      if (partFile != null && await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      return UpdateInstallResult(
        status: UpdateInstallStatus.error,
        errorMessage: _friendlyError(e),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Launches the Android package installer for an already-downloaded APK,
  /// prompting the user to allow installs from this source if needed.
  Future<UpdateInstallResult> installLocalApk(String apkPath) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const UpdateInstallResult(
        status: UpdateInstallStatus.error,
        errorMessage: 'In-app APK installation is only supported on Android.',
      );
    }
    try {
      final canInstall = await _channel.invokeMethod<bool>(
            'canRequestPackageInstalls',
          ) ??
          false;
      if (!canInstall) {
        await _channel.invokeMethod<bool>('openInstallPermissionSettings');
        return UpdateInstallResult(
          status: UpdateInstallStatus.permissionRequired,
          apkPath: apkPath,
        );
      }

      await _channel.invokeMethod<bool>('installApk', {'path': apkPath});
      return UpdateInstallResult(
        status: UpdateInstallStatus.launchedInstaller,
        apkPath: apkPath,
      );
    } catch (e) {
      AppLogger.e('Updater', 'Native APK install call failed', e);
      return UpdateInstallResult(
        status: UpdateInstallStatus.error,
        apkPath: apkPath,
        errorMessage: _friendlyError(e),
      );
    }
  }

  Future<bool> _isValidApkFile(File file) async {
    if (!await file.exists()) return false;
    final length = await file.length();
    if (length < 1024) return false;

    final raf = await file.open();
    try {
      final header = await raf.read(4);
      return header.length == 4 &&
          header[0] == 0x50 && // 'P'
          header[1] == 0x4B && // 'K'
          header[2] == 0x03 &&
          header[3] == 0x04;
    } finally {
      await raf.close();
    }
  }

  Future<void> _cleanCacheDir(Directory dir, {required String keepPath}) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path != keepPath) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  String _friendlyError(Object e) {
    if (e is SocketException) {
      return 'No internet connection.';
    }
    if (e is PlatformException) {
      return e.message ?? 'Android installer error (${e.code}).';
    }
    return e.toString();
  }
}
