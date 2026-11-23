import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ring/models/app_release_info.dart';

void main() {
  group('AppReleaseInfo.isNewerVersion', () {
    test('detects newer major, minor, and patch versions', () {
      expect(AppReleaseInfo.isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(AppReleaseInfo.isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(AppReleaseInfo.isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(AppReleaseInfo.isNewerVersion('v1.2.3', '1.2.2'), isTrue);
      expect(AppReleaseInfo.isNewerVersion('v1.10.0', 'v1.2.0'), isTrue);
    });

    test('returns false for equal or older versions', () {
      expect(AppReleaseInfo.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(AppReleaseInfo.isNewerVersion('v1.0.0', '1.0.0'), isFalse);
      expect(AppReleaseInfo.isNewerVersion('0.9.9', '1.0.0'), isFalse);
      expect(AppReleaseInfo.isNewerVersion('1.0.0', '1.0.1'), isFalse);
    });

    test('ranks stable release ahead of pre-release of same core version', () {
      expect(AppReleaseInfo.isNewerVersion('1.1.0', '1.1.0-beta.1'), isTrue);
      expect(AppReleaseInfo.isNewerVersion('1.1.0-beta.1', '1.1.0'), isFalse);
      expect(
        AppReleaseInfo.isNewerVersion('1.1.0-beta.2', '1.1.0-beta.1'),
        isTrue,
      );
    });

    test('handles optional build numbers and malformed strings gracefully', () {
      expect(AppReleaseInfo.isNewerVersion('1.0.0+2', '1.0.0+1'), isTrue);
      expect(AppReleaseInfo.isNewerVersion('1.0.0+1', '1.0.0+2'), isFalse);
      expect(AppReleaseInfo.isNewerVersion('invalid', '1.0.0'), isFalse);
      expect(AppReleaseInfo.isNewerVersion('1.0.0', ''), isFalse);
    });
  });

  group('AppReleaseInfo.fromGitHubJson', () {
    test('extracts APK asset, version, size, and release notes', () {
      final json = <String, dynamic>{
        'tag_name': 'v1.2.0',
        'name': 'Spike v1.2.0',
        'body': '- Improved HRV readiness scoring\n- Faster ring reconnect',
        'html_url': 'https://github.com/Sujaya-Nimneth/SPIKE/releases/tag/v1.2.0',
        'published_at': '2026-11-24T00:00:00Z',
        'assets': [
          {
            'name': 'spike-v1.2.0.apk.sha256',
            'size': 84,
            'browser_download_url':
                'https://github.com/Sujaya-Nimneth/SPIKE/releases/download/v1.2.0/spike-v1.2.0.apk.sha256',
          },
          {
            'name': 'spike-v1.2.0.apk',
            'size': 25165824,
            'browser_download_url':
                'https://github.com/Sujaya-Nimneth/SPIKE/releases/download/v1.2.0/spike-v1.2.0.apk',
          },
        ],
      };

      final release = AppReleaseInfo.fromGitHubJson(json);
      expect(release, isNotNull);
      expect(release!.tagName, 'v1.2.0');
      expect(release.version, '1.2.0');
      expect(release.name, 'Spike v1.2.0');
      expect(release.apkFileName, 'spike-v1.2.0.apk');
      expect(release.apkSizeBytes, 25165824);
      expect(release.formattedSize, '24.0 MB');
      expect(release.releaseNotes, contains('Improved HRV readiness scoring'));
      expect(release.publishedAt, isNotNull);
    });

    test('returns null when release has no APK asset', () {
      final json = <String, dynamic>{
        'tag_name': 'v1.2.0',
        'name': 'Source-only release',
        'assets': [
          {
            'name': 'notes.txt',
            'size': 120,
            'browser_download_url': 'https://example.com/notes.txt',
          },
        ],
      };

      expect(AppReleaseInfo.fromGitHubJson(json), isNull);
    });

    test('falls back to default name and notes when omitted', () {
      final json = <String, dynamic>{
        'tag_name': 'v2.0.0',
        'name': '',
        'body': '',
        'assets': [
          {
            'name': 'SPIKE-RELEASE.APK',
            'size': 1024 * 512,
            'browser_download_url': 'https://example.com/spike.apk',
          },
        ],
      };

      final release = AppReleaseInfo.fromGitHubJson(json);
      expect(release, isNotNull);
      expect(release!.name, 'Spike v2.0.0');
      expect(release.releaseNotes, 'Bug fixes and improvements.');
      expect(release.formattedSize, '512 KB');
    });
  });
}
