import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'update_models.dart';
import 'update_platform.dart';

typedef UpdateProgress = void Function(int received, int total);

/// Downloads release metadata from GitHub (or a compatible server) and
/// compares it with the version reported by `package_info_plus`.
///
/// The feed URL is intentionally a constructor parameter. To switch from
/// GitHub to a self-hosted update server, only change [feedUrl] (and optionally
/// [authorization]); the JSON parser already accepts both field sets.
class UpdateService {
  static const String githubLatestRelease =
      'https://api.github.com/repos/zwdart/deer/releases/latest';
  static const String githubReleases =
      'https://api.github.com/repos/zwdart/deer/releases';

  final String feedUrl;
  final String userAgent;
  final String? authorization;
  final Duration timeout;

  UpdateService({
    this.feedUrl = githubLatestRelease,
    this.userAgent = 'deer-updater',
    this.authorization,
    this.timeout = const Duration(seconds: 15),
  });

  /// Fetches and parses the latest release.
  Future<UpdateRelease> fetchLatest() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(Uri.parse(feedUrl)).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      if (authorization != null && authorization!.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, authorization!);
      }
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UpdateException(
          _httpError(response.statusCode, body),
        );
      }
      final decoded = jsonDecode(body);
      return UpdateFeedParser.parseRelease(decoded);
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw const UpdateException('检查更新超时，请稍后重试');
    } on SocketException {
      throw const UpdateException('无法连接更新服务器，请检查网络');
    } on HttpException {
      throw const UpdateException('更新服务器返回了无效的响应');
    } on FormatException {
      throw const UpdateException('更新接口返回的 JSON 无法解析');
    } finally {
      client.close(force: true);
    }
  }

  /// Checks the latest release against a local version.
  ///
  /// [platform] is required by callers so that every platform gets a distinct,
  /// testable asset selection path. Pass [architecture] when a release contains
  /// multiple builds for the same platform (for example `x64` and `arm64`).
  Future<UpdateCheckResult> check({
    required String localVersion,
    String? localBuild,
    UpdatePlatform? platform,
    String? architecture,
  }) async {
    final release = await fetchLatest();
    final target = platform ?? UpdatePlatform.current;
    final local = AppVersion.parse(
      localVersion,
      build: int.tryParse(localBuild ?? ''),
    );
    final remote = AppVersion.parse(release.version, build: release.build);
    final asset = selectAsset(
      release.assets,
      target,
      architecture: architecture,
    );
    return UpdateCheckResult(
      localVersion: local,
      remoteVersion: remote,
      release: release,
      asset: asset,
      platform: target,
    );
  }

  static UpdateAsset? selectAsset(
    List<UpdateAsset> assets,
    UpdatePlatform platform, {
    String? architecture,
  }) {
    if (assets.isEmpty) return null;

    final extensions = platform.extensions;
    final nameHints = platform.nameHints;
    final archHints = platform.architectureHints;
    final wantedArch = _architectureTokens(architecture);
    const otherArches = [
      'arm64',
      'aarch64',
      'armv7',
      'arm',
      'x64',
      'x86_64',
      'amd64',
      'x86',
    ];

    int? scoreFor(UpdateAsset asset) {
      final name = asset.name.toLowerCase();
      final url = asset.url.toLowerCase();
      final probe = '$name $url';

      var extensionIndex = -1;
      for (var i = 0; i < extensions.length; i++) {
        if (probe.contains(extensions[i])) {
          extensionIndex = i;
          break;
        }
      }
      if (extensionIndex < 0) return null;

      var score = 1000 - extensionIndex * 20;
      for (final hint in nameHints) {
        if (name.contains(hint)) {
          score += 220;
          break;
        }
      }
      for (final hint in archHints) {
        if (name.contains(hint)) {
          score += 35;
          break;
        }
      }
      if (wantedArch.isNotEmpty) {
        if (wantedArch.any(name.contains)) {
          score += 300;
        } else if (otherArches.any(name.contains)) {
          score -= 120;
        }
      }
      if (name.contains('debug') ||
          name.contains('symbols') ||
          name.contains('sha256') ||
          name.contains('.sig') ||
          name.contains('.txt')) {
        score -= 900;
      }
      return score;
    }

    final scored = <(UpdateAsset, int)>[];
    for (final asset in assets) {
      final score = scoreFor(asset);
      if (score != null) scored.add((asset, score));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      return a.$1.name.compareTo(b.$1.name);
    });
    return scored.first.$1;
  }

  static Set<String> _architectureTokens(String? architecture) {
    final value = architecture?.toLowerCase().trim() ?? '';
    if (value.isEmpty) return const {};
    if (value.contains('arm') || value == 'aarch64') {
      return {'arm64', 'aarch64'};
    }
    if (value.contains('x86') || value.contains('x64') || value == 'amd64') {
      return {'x64', 'x86_64', 'amd64'};
    }
    return {value};
  }

  /// Saves an update package under the platform downloads directory.
  Future<File> download(
    UpdateAsset asset, {
    Directory? directory,
    UpdateProgress? onProgress,
  }) async {
    final targetDirectory = directory ?? await defaultDownloadDirectory();
    await targetDirectory.create(recursive: true);
    final file = await _uniqueFile(targetDirectory, _safeFileName(asset.name));

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = false;
    IOSink? sink;
    var completed = false;
    try {
      final request = await client
          .getUrl(_resolve(asset.url))
          .timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UpdateException('下载失败：HTTP ${response.statusCode}');
      }
      final total = response.contentLength > 0 ? response.contentLength : asset.size;
      sink = file.openWrite();
      var received = 0;
      var lastNotified = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        final shouldNotify = onProgress != null &&
            (received - lastNotified >= 256 * 1024 ||
                (total > 0 && received >= total));
        if (shouldNotify) {
          lastNotified = received;
          onProgress(received, total);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      onProgress?.call(received, total);
      completed = true;
      return file;
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw const UpdateException('下载超时，请稍后重试');
    } on SocketException {
      throw const UpdateException('下载失败，请检查网络连接');
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
      if (!completed) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  static Future<Directory> defaultDownloadDirectory() async {
    Directory? root;
    try {
      root = await getDownloadsDirectory();
    } catch (_) {}
    if (root == null) {
      try {
        root = await getExternalStorageDirectory();
      } catch (_) {}
    }
    root ??= await getApplicationDocumentsDirectory();
    return Directory(p.join(root.path, 'deer-updates'));
  }

  /// Opens an installer/archive. iOS cannot install unsigned packages, so it
  /// opens the system share sheet instead.
  Future<void> openDownloaded(File file) async {
    if (Platform.isLinux && file.path.toLowerCase().endsWith('.appimage')) {
      try {
        await Process.run('chmod', ['+x', file.path]);
      } catch (_) {}
    }
    if (Platform.isIOS) {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'deer'),
      );
      return;
    }
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw UpdateException(result.message.isEmpty ? '无法打开安装包' : result.message);
    }
  }

  Uri _resolve(String url) {
    final uri = Uri.parse(url);
    if (uri.hasScheme) return uri;
    return Uri.parse(feedUrl).resolveUri(uri);
  }

  static String _safeFileName(String name) {
    var value = p.basename(name.trim());
    if (value.isEmpty || value == '.' || value == '..') value = 'deer-update';
    value = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    if (value.length > 140) {
      final ext = p.extension(value);
      value = value.substring(0, 140 - ext.length) + ext;
    }
    return value;
  }

  static Future<File> _uniqueFile(Directory directory, String name) async {
    final ext = _compoundExtension(name);
    final base = ext.isEmpty ? name : name.substring(0, name.length - ext.length);
    var file = File(p.join(directory.path, name));
    var index = 1;
    while (await file.exists()) {
      file = File(p.join(directory.path, '$base ($index)$ext'));
      index++;
    }
    return file;
  }

  static String _compoundExtension(String name) {
    final lower = name.toLowerCase();
    for (final ext in const ['.tar.gz', '.tar.xz', '.pkg.tar.zst']) {
      if (lower.endsWith(ext)) return name.substring(name.length - ext.length);
    }
    return p.extension(name);
  }

  static String _httpError(int status, String body) {
    if (status == 403 && body.toLowerCase().contains('rate limit')) {
      return 'GitHub API 访问频率受限，请稍后重试或使用浏览器打开';
    }
    if (status == 404) return '没有找到发布版本';
    return '更新服务器返回错误：HTTP $status';
  }
}
