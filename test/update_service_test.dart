import 'package:deer/services/update/update_models.dart';
import 'package:deer/services/update/update_platform.dart';
import 'package:deer/services/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppVersion', () {
    test('compares semantic versions', () {
      expect(AppVersion.parse('1.0.0').compareTo(AppVersion.parse('1.0.1')), -1);
      expect(AppVersion.parse('1.2.0').compareTo(AppVersion.parse('1.1.9')), 1);
      expect(AppVersion.parse('v1.2.3').compareTo(AppVersion.parse('1.2.3')), 0);
    });

    test('compares build numbers only when both are present', () {
      expect(
        AppVersion.parse('1.0.0+2').compareTo(AppVersion.parse('1.0.0+1')),
        1,
      );
      expect(
        AppVersion.parse('1.0.0+1').compareTo(AppVersion.parse('1.0.0')),
        0,
      );
    });

    test('handles prereleases', () {
      expect(
        AppVersion.parse('2.0.0-beta').compareTo(AppVersion.parse('2.0.0')),
        -1,
      );
      expect(
        AppVersion.parse('2.0.0-beta.2')
            .compareTo(AppVersion.parse('2.0.0-beta.1')),
        1,
      );
      expect(
        AppVersion.parse('2.0.0-rc.1')
            .compareTo(AppVersion.parse('2.0.0-beta.9')),
        1,
      );
    });
  });

  group('UpdateFeedParser', () {
    test('parses GitHub release JSON', () {
      final release = UpdateFeedParser.parseRelease({
        'tag_name': 'v1.2.0',
        'name': 'deer 1.2.0',
        'body': 'Fixes and improvements',
        'html_url': 'https://github.com/zwdart/deer/releases/tag/v1.2.0',
        'published_at': '2026-01-02T03:04:05Z',
        'prerelease': false,
        'assets': [
          {
            'name': 'deer-linux-x64.tar.gz',
            'browser_download_url':
                'https://example.com/deer-linux-x64.tar.gz',
            'size': 1234,
            'content_type': 'application/gzip',
          },
          {'name': 'broken-asset'},
        ],
      });

      expect(release.version, 'v1.2.0');
      expect(release.tagName, 'v1.2.0');
      expect(release.name, 'deer 1.2.0');
      expect(release.notes, 'Fixes and improvements');
      expect(release.publishedAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(release.assets.length, 1);
      expect(release.assets.first.size, 1234);
      expect(release.assets.first.contentType, 'application/gzip');
    });

    test('parses custom server JSON', () {
      final release = UpdateFeedParser.parseRelease({
        'version': '1.3.0',
        'build': 13,
        'notes': 'Custom feed',
        'release_url': 'https://updates.example.com/deer/1.3.0',
        'assets': [
          {
            'name': 'deer-windows-x64.zip',
            'download_url': 'https://updates.example.com/deer-windows-x64.zip',
            'bytes': 55,
          },
        ],
      });

      expect(release.version, '1.3.0');
      expect(release.build, 13);
      expect(release.htmlUrl, 'https://updates.example.com/deer/1.3.0');
      expect(release.assets.first.url,
          'https://updates.example.com/deer-windows-x64.zip');
      expect(release.assets.first.size, 55);
    });

    test('picks the first stable item from a release list', () {
      final release = UpdateFeedParser.parseRelease([
        {'tag_name': 'v2.0.0-beta', 'prerelease': true},
        {'tag_name': 'v1.9.0', 'body': 'stable'},
      ]);
      expect(release.tagName, 'v1.9.0');
    });

    test('rejects invalid release payloads', () {
      expect(
        () => UpdateFeedParser.parseRelease({'name': 'missing version'}),
        throwsA(isA<UpdateException>()),
      );
      expect(
        () => UpdateFeedParser.parseRelease([]),
        throwsA(isA<UpdateException>()),
      );
    });
  });

  group('asset selection', () {
    final assets = [
      const UpdateAsset(name: 'deer-android.apk', url: 'https://x/android.apk'),
      const UpdateAsset(
        name: 'deer-ios-unsigned.zip',
        url: 'https://x/ios.zip',
      ),
      const UpdateAsset(name: 'deer-macos.zip', url: 'https://x/macos.zip'),
      const UpdateAsset(
        name: 'deer-linux-x64.tar.gz',
        url: 'https://x/linux.tar.gz',
      ),
      const UpdateAsset(
        name: 'deer-windows-x64.zip',
        url: 'https://x/windows.zip',
      ),
      const UpdateAsset(name: 'deer-linux-x64.tar.gz.sha256', url: 'https://x/sha'),
    ];

    test('selects a distinct package for every platform', () {
      expect(
        UpdateService.selectAsset(assets, UpdatePlatform.android)?.name,
        'deer-android.apk',
      );
      expect(
        UpdateService.selectAsset(assets, UpdatePlatform.ios)?.name,
        'deer-ios-unsigned.zip',
      );
      expect(
        UpdateService.selectAsset(assets, UpdatePlatform.macOS)?.name,
        'deer-macos.zip',
      );
      expect(
        UpdateService.selectAsset(assets, UpdatePlatform.windows)?.name,
        'deer-windows-x64.zip',
      );
      expect(
        UpdateService.selectAsset(assets, UpdatePlatform.linux)?.name,
        'deer-linux-x64.tar.gz',
      );
    });

    test('uses architecture hints when provided', () {
      const multiArch = [
        UpdateAsset(name: 'deer-arm64.apk', url: 'https://x/arm64.apk'),
        UpdateAsset(name: 'deer-x64.apk', url: 'https://x/x64.apk'),
      ];
      expect(
        UpdateService.selectAsset(
          multiArch,
          UpdatePlatform.android,
          architecture: 'arm64',
        )?.name,
        'deer-arm64.apk',
      );
      expect(
        UpdateService.selectAsset(
          multiArch,
          UpdatePlatform.android,
          architecture: 'x64',
        )?.name,
        'deer-x64.apk',
      );
    });

    test('returns null when no package matches the platform', () {
      const onlyIpa = [
        UpdateAsset(name: 'deer.ipa', url: 'https://x/deer.ipa'),
      ];
      expect(
        UpdateService.selectAsset(onlyIpa, UpdatePlatform.windows),
        isNull,
      );
    });
  });

  test('update result compares local and remote versions', () {
    const release = UpdateRelease(
      version: '1.1.0',
      tagName: 'v1.1.0',
      name: 'deer 1.1.0',
      notes: '',
      htmlUrl: 'https://example.com',
      assets: [],
    );
    final result = UpdateCheckResult(
      localVersion: AppVersion.parse('1.0.0'),
      remoteVersion: AppVersion.parse(release.version),
      release: release,
      asset: null,
      platform: UpdatePlatform.linux,
    );
    expect(result.hasUpdate, isTrue);
    expect(result.hasAsset, isFalse);
    expect(result.downloadUrl, 'https://example.com');
  });
}
