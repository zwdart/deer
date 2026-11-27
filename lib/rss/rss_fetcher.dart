import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class FeedResponse {
  final bool notModified;
  final String? body;
  final String? error;
  final String? etag;
  final String? contentType;

  const FeedResponse._({
    this.notModified = false,
    this.body,
    this.error,
    this.etag,
    this.contentType,
  });

  factory FeedResponse.notModifiedResponse() =>
      const FeedResponse._(notModified: true);

  factory FeedResponse.of(String body, {String? etag, String? contentType}) =>
      FeedResponse._(
          body: body, etag: etag, contentType: contentType);

  factory FeedResponse.failed(String error) =>
      FeedResponse._(error: error);
}

/// 直接抓取用户自己添加的 RSS 源，不经过任何中间服务器。
class RssFetcher {
  RssFetcher._();

  static const int maxBytes = 4 * 1024 * 1024;
  static const Duration timeout = Duration(seconds: 15);
  static const String userAgent =
      'Mozilla/5.0 (compatible; dchat-rss/1.0; +https://dart.xin)';

  // ---------------------------------------------------------------------------
  // 证书信任：Windows 系统 CA 库缺部分根证书（如 Starfield / StartSSL），
  // 导致 https://rss.huxiu.com 等少数合法源报 CERTIFICATE_VERIFY_FAILED。
  // 这里内嵌一份 Mozilla 的公共 CA 包 assets/cacert.pem，完全替代系统信任库，
  // 保证所有桌面平台行为一致。详见 README 注释：cacert.pem 取自
  // https://curl.se/ca/cacert.pem，118 个根证书、约 196KB。
  static SecurityContext? _trust;
  static Future<SecurityContext> _loadTrust() async {
    if (_trust != null) return _trust!;
    final bytes = await rootBundle.load('assets/cacert.pem');
    // 完全替换系统信任库 —— 只信我们包里的 CA，避免 Windows CryptoAPI 上
    // 某些老机器缺中间证书 / 信任过期的情况。
    final ctx = SecurityContext()
      ..setTrustedCertificatesBytes(bytes.buffer.asUint8List());
    _trust = ctx;
    return ctx;
  }

  static Future<FeedResponse> fetch(
    String url, {
    String? etag,
    DateTime? ifModifiedSince,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return FeedResponse.failed('不支持的地址');
    }
    final context = await _loadTrust();
    final client = IOClient(HttpClient(context: context)..userAgent = userAgent);
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers['Accept'] =
            'application/rss+xml, application/atom+xml, application/xml+xml, application/xml, text/xml, application/json;q=0.9, */*;q=0.8';
      if (etag != null && etag.isNotEmpty) request.headers['If-None-Match'] = etag;
      if (ifModifiedSince != null) {
        request.headers['If-Modified-Since'] = formatHttpDate(ifModifiedSince);
      }

      final streamed = await client.send(request).timeout(timeout);
      final status = streamed.statusCode;
      final headers = streamed.headers;
      if (status == 304) return FeedResponse.notModifiedResponse();

      final bytes = <int>[];
      var overflow = false;
      await for (final chunk in streamed.stream) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) {
          overflow = true;
          break;
        }
      }
      if (overflow) return FeedResponse.failed('响应内容过大');
      if (status < 200 || status >= 300) {
        return FeedResponse.failed('HTTP $status');
      }
      return FeedResponse.of(
        decodeBody(Uint8List.fromList(bytes), headers['content-type']),
        etag: headers['etag'],
        contentType: headers['content-type'],
      );
    } catch (error) {
      return FeedResponse.failed('$error');
    } finally {
      client.close();
    }
  }

  /// 依次尝试 Content-Type 声明、XML 声明中的 encoding，最后退回 UTF-8。
  /// gb2312/gbk 等 Dart 内置不支持的标签由 charset 包补齐。
  static String decodeBody(Uint8List bytes, String? contentType) {
    final label = _charsetFromHeader(contentType) ?? _charsetFromXml(bytes);
    Encoding? encoding;
    if (label != null) {
      try {
        encoding = Charset.getByName(label);
      } catch (_) {
        encoding = null;
      }
    }
    encoding ??= _detect(bytes) ?? utf8;
    try {
      return encoding.decode(bytes);
    } catch (_) {}
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static Encoding? _detect(Uint8List bytes) {
    // 全量扫描几 MB 的响应体太慢，头部采样足够区分 gbk / utf8。
    final sample = bytes.length > 8192 ? bytes.sublist(0, 8192) : bytes;
    try {
      return Charset.detect(sample);
    } catch (_) {
      return null;
    }
  }

  static String? _charsetFromHeader(String? contentType) {
    if (contentType == null) return null;
    final match =
        RegExp(r'charset\s*=\s*"?([^"\s;]+)"?', caseSensitive: false)
            .firstMatch(contentType);
    return match?.group(1)?.toLowerCase().trim();
  }

  static String? _charsetFromXml(Uint8List bytes) {
    final preview = String.fromCharCodes(bytes.take(256));
    final match =
        RegExp(r'''encoding\s*=\s*["']([^"']+)["']''').firstMatch(preview);
    return match?.group(1)?.toLowerCase().trim();
  }
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// If-Modified-Since 要求 RFC 1123，SQLite 的时间戳直接塞进去永远不会命中 304。
String formatHttpDate(DateTime time) {
  final utc = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${_weekdays[utc.weekday - 1]}, ${two(utc.day)} ${_months[utc.month - 1]} '
      '${utc.year} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT';
}
