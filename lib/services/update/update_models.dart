import 'update_platform.dart';

/// A semantic version with an optional build number and pre-release suffix.
///
/// Accepted examples: `1.2.3`, `v1.2.3`, `1.2.3+12`, `2.0.0-beta.1`.
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;
  final int? build;
  final String preRelease;

  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.build,
    this.preRelease = '',
  });

  factory AppVersion.parse(String raw, {int? build}) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }

    int? explicitBuild = build;
    final plus = value.indexOf('+');
    if (plus >= 0) {
      explicitBuild ??= int.tryParse(value.substring(plus + 1).trim());
      value = value.substring(0, plus);
    }

    var preRelease = '';
    final dash = value.indexOf('-');
    if (dash >= 0) {
      preRelease = value.substring(dash + 1);
      value = value.substring(0, dash);
    }

    final parts = value.split('.');
    int numberAt(int index) {
      if (index >= parts.length) return 0;
      final match = RegExp(r'^\d+').stringMatch(parts[index]);
      return int.tryParse(match ?? '') ?? 0;
    }

    return AppVersion(
      major: numberAt(0),
      minor: numberAt(1),
      patch: numberAt(2),
      build: explicitBuild,
      preRelease: preRelease,
    );
  }

  bool get hasBuild => build != null && build! > 0;

  @override
  int compareTo(AppVersion other) {
    final core = _compareInt(major, other.major) ??
        _compareInt(minor, other.minor) ??
        _compareInt(patch, other.patch);
    if (core != null) return core;

    // Only compare build numbers when both sides provide one. GitHub release
    // tags usually do not contain a build number, so a missing build must not
    // make an otherwise equal version look older or newer.
    if (hasBuild && other.hasBuild) {
      final buildResult = _compareInt(build!, other.build!);
      if (buildResult != null) return buildResult;
    }

    return _comparePreRelease(preRelease, other.preRelease);
  }

  static int? _compareInt(int a, int b) => a == b ? null : (a < b ? -1 : 1);

  static int _comparePreRelease(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;
    final left = a.split('.');
    final right = b.split('.');
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      if (i >= left.length) return -1;
      if (i >= right.length) return 1;
      final l = left[i];
      final r = right[i];
      final ln = int.tryParse(l);
      final rn = int.tryParse(r);
      if (ln != null && rn != null) {
        if (ln != rn) return ln < rn ? -1 : 1;
      } else if (ln != null) {
        return -1;
      } else if (rn != null) {
        return 1;
      } else {
        final result = l.compareTo(r);
        if (result != 0) return result < 0 ? -1 : 1;
      }
    }
    return 0;
  }

  String get display => preRelease.isEmpty
      ? '$major.$minor.$patch'
      : '$major.$minor.$patch-$preRelease';

  @override
  String toString() => hasBuild ? '$display+$build' : display;
}

class UpdateAsset {
  final String name;
  final String url;
  final int size;
  final String contentType;

  const UpdateAsset({
    required this.name,
    required this.url,
    this.size = 0,
    this.contentType = '',
  });

  factory UpdateAsset.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Release asset must be a JSON object');
    }
    final map = Map<String, dynamic>.from(raw);
    final name = _string(map, const ['name', 'filename', 'file_name']);
    final url = _string(map, const [
      'browser_download_url',
      'download_url',
      'url',
      'href',
    ]);
    if (url.isEmpty) {
      throw const FormatException('Release asset is missing a download URL');
    }
    return UpdateAsset(
      name: name.isEmpty ? _fileNameFromUrl(url) : name,
      url: url,
      size: _integer(map, const ['size', 'bytes', 'file_size']),
      contentType: _string(map, const ['content_type', 'contentType', 'type']),
    );
  }

  bool get hasSize => size > 0;
}

class UpdateRelease {
  final String version;
  final String tagName;
  final String name;
  final String notes;
  final String htmlUrl;
  final DateTime? publishedAt;
  final bool prerelease;
  final int? build;
  final List<UpdateAsset> assets;

  const UpdateRelease({
    required this.version,
    required this.tagName,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    required this.assets,
    this.publishedAt,
    this.prerelease = false,
    this.build,
  });

  String get displayName => name.isNotEmpty ? name : tagName;
}

class UpdateCheckResult {
  final AppVersion localVersion;
  final AppVersion remoteVersion;
  final UpdateRelease release;
  final UpdateAsset? asset;
  final UpdatePlatform platform;

  const UpdateCheckResult({
    required this.localVersion,
    required this.remoteVersion,
    required this.release,
    required this.asset,
    required this.platform,
  });

  bool get hasUpdate => remoteVersion.compareTo(localVersion) > 0;

  bool get hasAsset => asset != null;

  String get downloadUrl => asset?.url ?? release.htmlUrl;
}

class UpdateException implements Exception {
  final String message;

  const UpdateException(this.message);

  @override
  String toString() => message;
}

/// Parses GitHub Releases JSON and a small, server-friendly superset of it.
///
/// GitHub shape:
/// ```json
/// {
///   "tag_name": "v1.2.0",
///   "name": "deer 1.2.0",
///   "body": "Release notes",
///   "html_url": "https://github.com/owner/repo/releases/tag/v1.2.0",
///   "published_at": "2026-01-01T00:00:00Z",
///   "prerelease": false,
///   "assets": [
///     {
///       "name": "deer-linux-x64.tar.gz",
///       "browser_download_url": "https://.../deer-linux-x64.tar.gz",
///       "size": 12345678,
///       "content_type": "application/gzip"
///     }
///   ]
/// }
/// ```
///
/// Custom server shape may use `version`, `build`, `notes`,
/// `release_url` and asset `download_url` instead.
class UpdateFeedParser {
  UpdateFeedParser._();

  static UpdateRelease parseRelease(Object? json) {
    Object? value = json;
    if (value is List) {
      final list = value;
      if (list.isEmpty) {
        throw const UpdateException('更新接口返回了空的版本列表');
      }
      Object? selected;
      for (final item in list) {
        if (item is Map &&
            item['draft'] != true &&
            item['prerelease'] != true) {
          selected = item;
          break;
        }
      }
      value = selected ?? list.first;
    }
    if (value is! Map) {
      throw const UpdateException('更新接口返回的数据格式不正确');
    }
    final map = Map<String, dynamic>.from(value);

    final tagName = _string(map, const ['tag_name', 'tag', 'version']);
    final rawVersion = _string(map, const ['version', 'tag_name', 'tag']);
    final version = rawVersion.isEmpty ? tagName : rawVersion;
    if (version.isEmpty) {
      throw const UpdateException('更新接口缺少版本号');
    }

    final assetsRaw = map['assets'];
    final assets = <UpdateAsset>[];
    if (assetsRaw is List) {
      for (final item in assetsRaw) {
        try {
          assets.add(UpdateAsset.fromJson(item));
        } on FormatException {
          // Ignore malformed assets so one bad entry cannot hide a release.
        }
      }
    }

    DateTime? publishedAt;
    final published = _string(map, const ['published_at', 'publishedAt', 'date']);
    if (published.isNotEmpty) {
      publishedAt = DateTime.tryParse(published);
    }

    return UpdateRelease(
      version: version,
      tagName: tagName.isEmpty ? version : tagName,
      name: _string(map, const ['name', 'title', 'release_name']),
      notes: _string(map, const ['body', 'notes', 'changelog', 'description']),
      htmlUrl: _string(map, const [
        'html_url',
        'release_url',
        'releaseUrl',
        'url',
      ]),
      publishedAt: publishedAt,
      prerelease: map['prerelease'] == true,
      build: _optionalInteger(map, const ['build', 'build_number', 'buildNumber']),
      assets: assets,
    );
  }

}

int _integer(Map<String, dynamic> map, List<String> keys) {
  return _optionalInteger(map, keys) ?? 0;
}

int? _optionalInteger(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

String _string(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value != null && value is! Map && value is! List) {
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
  }
  return '';
}

String _fileNameFromUrl(String url) {
  final path = Uri.tryParse(url)?.pathSegments;
  if (path == null || path.isEmpty) return 'deer-update';
  return path.last.isEmpty ? 'deer-update' : path.last;
}
