import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_release_info.dart';
import '../providers/update_providers.dart';
import '../theme/app_colors.dart';

/// Modal dialog presenting a new GitHub Release with live download progress
/// and Android unknown-sources permission guidance.
class AppUpdateDialog extends ConsumerStatefulWidget {
  final UpdateCheckResult checkResult;

  const AppUpdateDialog({
    super.key,
    required this.checkResult,
  });

  static Future<void> show(
    BuildContext context,
    UpdateCheckResult checkResult,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppUpdateDialog(checkResult: checkResult),
    );
  }

  @override
  ConsumerState<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends ConsumerState<AppUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _downloadedApkPath;
  bool _needsPermission = false;
  String? _errorMessage;

  AppReleaseInfo get _release => widget.checkResult.release!;

  Future<void> _startUpdate() async {
    if (_isDownloading) return;

    final service = ref.read(appUpdateServiceProvider);

    // If the APK is already downloaded and we were waiting on install permission,
    // immediately retry launching the Android installer without re-downloading.
    if (_downloadedApkPath != null) {
      setState(() {
        _errorMessage = null;
      });
      final result = await service.installLocalApk(_downloadedApkPath!);
      if (!mounted) return;
      _handleInstallResult(result);
      return;
    }

    setState(() {
      _isDownloading = true;
      _progress = 0;
      _receivedBytes = 0;
      _totalBytes = _release.apkSizeBytes;
      _needsPermission = false;
      _errorMessage = null;
    });

    final result = await service.downloadAndInstall(
      _release,
      onProgress: (progress, received, total) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          _receivedBytes = received;
          _totalBytes = total;
        });
      },
    );

    if (!mounted) return;
    setState(() => _isDownloading = false);
    _handleInstallResult(result);
  }

  void _handleInstallResult(UpdateInstallResult result) {
    switch (result.status) {
      case UpdateInstallStatus.launchedInstaller:
        Navigator.of(context).pop();
      case UpdateInstallStatus.permissionRequired:
        setState(() {
          _downloadedApkPath = result.apkPath;
          _needsPermission = true;
        });
      case UpdateInstallStatus.error:
        setState(() {
          _errorMessage = result.errorMessage ?? 'Update failed.';
        });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_isDownloading,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.cardBorder, width: 0.5),
        ),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
        contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.pastelTeal.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'UPDATE AVAILABLE',
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.pastelTeal,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _release.name,
              style: textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'v${widget.checkResult.currentVersion} → v${_release.version} · ${_release.formattedSize}',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder, width: 0.5),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _release.releaseNotes,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _totalBytes > 0 ? _progress : null,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceLight,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.pastelTeal,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Downloading APK…',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.pastelTeal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _totalBytes > 0
                        ? '${(_progress * 100).round()}% · ${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}'
                        : _formatBytes(_receivedBytes),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
            if (_needsPermission) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.pastelAmber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.pastelAmber.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.security_update_good_rounded,
                      color: AppColors.pastelAmber,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Enable "Allow from this source" for Spike in Android Settings, then return here and tap Install Now.',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.pastelAmber,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.pastelCoral,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
            child: Text(
              'Later',
              style: textTheme.bodyMedium?.copyWith(
                color: _isDownloading
                    ? AppColors.textTertiary.withValues(alpha: 0.4)
                    : AppColors.textTertiary,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _isDownloading ? null : _startUpdate,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.pastelTeal,
              foregroundColor: AppColors.background,
              disabledBackgroundColor:
                  AppColors.pastelTeal.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: Icon(
              _downloadedApkPath != null
                  ? Icons.install_mobile_rounded
                  : Icons.system_update_rounded,
              size: 18,
            ),
            label: Text(
              _isDownloading
                  ? 'Downloading…'
                  : _downloadedApkPath != null
                      ? 'Install Now'
                      : _errorMessage != null
                          ? 'Retry Update'
                          : 'Update Now',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
