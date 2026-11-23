/// Metadata for a downloadable Android release hosted on GitHub Releases.
class AppReleaseInfo {
  final String tagName;
  final String version;
  final String name;
  final String releaseNotes;
  final String apkDownloadUrl;
  final String apkFileName;
  final int apkSizeBytes;
  final String htmlUrl;
  final DateTime? publishedAt;

  const AppReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.apkFileName,
    required this.apkSizeBytes,
    required this.htmlUrl,
    this.publishedAt,
  });

  /// Formats the APK size as a human-readable megabyte string (e.g. `24.3 MB`).
  String get formattedSize {
    if (apkSizeBytes <= 0) return 'Unknown size';
    final mb = apkSizeBytes / (1024 * 1024);
    if (mb >= 1) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final kb = apkSizeBytes / 1024;
    return '${kb.toStringAsFixed(0)} KB';
  }

  /// Parses a GitHub Releases API JSON payload (`/releases/latest`).
  ///
  /// Returns `null` if the release does not contain an `.apk` asset.
  static AppReleaseInfo? fromGitHubJson(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] as String?)?.trim() ?? '';
    if (tagName.isEmpty) return null;

    final rawAssets = json['assets'];
    if (rawAssets is! List) return null;

    Map<String, dynamic>? apkAsset;
    for (final entry in rawAssets) {
      if (entry is Map<String, dynamic>) {
        final name = (entry['name'] as String?)?.trim() ?? '';
        final url = (entry['browser_download_url'] as String?)?.trim() ?? '';
        if (name.toLowerCase().endsWith('.apk') && url.isNotEmpty) {
          apkAsset = entry;
          break;
        }
      }
    }

    if (apkAsset == null) return null;

    final version = normalizeVersion(tagName);
    final releaseName = (json['name'] as String?)?.trim();
    final body = (json['body'] as String?)?.trim() ?? '';
    final htmlUrl = (json['html_url'] as String?)?.trim() ?? '';
    final publishedRaw = json['published_at'] as String?;

    return AppReleaseInfo(
      tagName: tagName,
      version: version,
      name: (releaseName != null && releaseName.isNotEmpty)
          ? releaseName
          : 'Spike v$version',
      releaseNotes: body.isNotEmpty ? body : 'Bug fixes and improvements.',
      apkDownloadUrl: (apkAsset['browser_download_url'] as String).trim(),
      apkFileName: (apkAsset['name'] as String).trim(),
      apkSizeBytes: (apkAsset['size'] as num?)?.toInt() ?? 0,
      htmlUrl: htmlUrl,
      publishedAt: publishedRaw != null ? DateTime.tryParse(publishedRaw) : null,
    );
  }

  /// Strips a leading `v`/`V` prefix and trims whitespace.
  static String normalizeVersion(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      return trimmed.substring(1).trim();
    }
    return trimmed;
  }

  /// Returns `true` if [latest] represents a newer semantic version than [current].
  ///
  /// Supports standard `major.minor.patch`, optional `v` prefix, optional
  /// `-prerelease` tags (stable > prerelease for same core version), and
  /// optional `+build` suffixes.
  static bool isNewerVersion(String latest, String current) {
    final l = _ParsedVersion.tryParse(latest);
    final c = _ParsedVersion.tryParse(current);
    if (l == null || c == null) return false;
    return l.compareTo(c) > 0;
  }
}

class _ParsedVersion implements Comparable<_ParsedVersion> {
  final List<int> core;
  final String? preRelease;
  final int? buildNumber;

  const _ParsedVersion({
    required this.core,
    this.preRelease,
    this.buildNumber,
  });

  static _ParsedVersion? tryParse(String raw) {
    var normalized = AppReleaseInfo.normalizeVersion(raw);
    if (normalized.isEmpty) return null;

    int? buildNumber;
    final plusIdx = normalized.indexOf('+');
    if (plusIdx != -1) {
      buildNumber = int.tryParse(normalized.substring(plusIdx + 1).trim());
      normalized = normalized.substring(0, plusIdx);
    }

    String? preRelease;
    final dashIdx = normalized.indexOf('-');
    if (dashIdx != -1) {
      preRelease = normalized.substring(dashIdx + 1).trim();
      if (preRelease.isEmpty) preRelease = null;
      normalized = normalized.substring(0, dashIdx);
    }

    final parts = normalized.split('.');
    if (parts.isEmpty) return null;

    final core = <int>[];
    for (final part in parts) {
      final parsed = int.tryParse(part.trim());
      if (parsed == null || parsed < 0) return null;
      core.add(parsed);
    }
    while (core.length < 3) {
      core.add(0);
    }

    return _ParsedVersion(
      core: core,
      preRelease: preRelease,
      buildNumber: buildNumber,
    );
  }

  @override
  int compareTo(_ParsedVersion other) {
    final maxLen = core.length > other.core.length ? core.length : other.core.length;
    for (var i = 0; i < maxLen; i++) {
      final a = i < core.length ? core[i] : 0;
      final b = i < other.core.length ? other.core[i] : 0;
      if (a != b) return a.compareTo(b);
    }

    // Stable release (no preRelease) > pre-release for the same core version.
    if (preRelease == null && other.preRelease != null) return 1;
    if (preRelease != null && other.preRelease == null) return -1;
    if (preRelease != null && other.preRelease != null) {
      final cmp = preRelease!.compareTo(other.preRelease!);
      if (cmp != 0) return cmp;
    }

    if (buildNumber != null && other.buildNumber != null) {
      return buildNumber!.compareTo(other.buildNumber!);
    }
    return 0;
  }
}

enum UpdateCheckStatus {
  updateAvailable,
  upToDate,
  noReleaseFound,
  error,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String currentVersion;
  final AppReleaseInfo? release;
  final String? errorMessage;

  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.release,
    this.errorMessage,
  });

  bool get hasUpdate =>
      status == UpdateCheckStatus.updateAvailable && release != null;
}

enum UpdateInstallStatus {
  launchedInstaller,
  permissionRequired,
  error,
}

class UpdateInstallResult {
  final UpdateInstallStatus status;
  final String? apkPath;
  final String? errorMessage;

  const UpdateInstallResult({
    required this.status,
    this.apkPath,
    this.errorMessage,
  });
}
