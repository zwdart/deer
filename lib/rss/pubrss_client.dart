import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../core/rss_models.dart';

/// 公共 RSS 源随机接口客户端。
///
/// 对接 `GET /open/v1/pubrss-sources`，HMAC-SHA256 签名，返回管理员维护的公共 RSS 源池随机结果。
/// 文档见 `docs/pubrss-api.md`。
class PubrssClient {
  static const String _base = 'https://www.dart.xin';
  static const String _path = '/open/v1/pubrss-sources';

  // 公开 AppKey / AppSecret（deer 项目专用）。后续如需替换只改此处。
  static const String _appKey = 'ak-zrss-LDHTWrG9SAzLZPNB8FbqGYCmSvt55gto';
  static const String _appSecret =
      'sk-zrss-nwbPt7Z7j7DiWvZsTLMHug4sVBsZWGR3HWN8mJeorcKyTpRv';

  /// 拉取一批随机公共 RSS 源；`count` 1–100，默认 12。
  ///
  /// 内部自建临时 http.Client，用完即关，无需外部管理生命周期。
  /// 返回 [PubrssResult]：items 一定有（可能为空列表），introTitle / introBody
  /// 只有后端在 `data` 里返回了才会填，否则为 null —— 调用方应 fallback 到本地文案。
  Future<PubrssResult> fetchSources({int count = 12}) async {
    final client = http.Client();
    try {
      return await _fetchWith(client);
    } finally {
      client.close();
    }
  }

  Future<PubrssResult> _fetchWith(http.Client client) async {
    final uri = Uri.parse('$_base$_path');
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final nonce = _randomNonce();

    // payload = HTTP_METHOD + lastPathSegment + APP_KEY + TIMESTAMP + APP_SECRET + NONCE
    const method = 'GET';
    const lastSeg = 'pubrss-sources';
    final payload = '$method$lastSeg$_appKey$timestamp$_appSecret$nonce';
    final signature = _hmacSha256Hex(_appSecret, payload);

    final headers = {
      'X-App-Key': _appKey,
      'X-Timestamp': timestamp,
      'X-Nonce': nonce,
      'X-Signature': signature,
      'Accept': 'application/json',
    };

    final response = await client.get(uri, headers: headers).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw PubrssException('HTTP ${response.statusCode}: ${response.body}');
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    final code = body['code'];
    if (code != 0) {
      throw PubrssException(
          'API code=$code message=${body['message'] ?? ''}');
    }

    final data = body['data'] as Map<String, dynamic>? ?? const {};
    final items = data['items'] as List<dynamic>? ?? const [];
    final feeds = items
        .whereType<Map<String, dynamic>>()
        .map(RecommendedFeed.fromJson)
        // 接口偶尔返回空 title 或空 url，过滤掉避免后续 addFeed 炸掉
        .where((f) => f.name.isNotEmpty && f.url.isNotEmpty)
        .toList();

    // 介绍字段是可选扩展：后端暂未返回时为 null，客户端 fallback 到本地 i18n。
    // 后端以后只需在 data 里补 intro_title / intro_body 两个字段即可自动生效。
    String? pick(String key) {
      final v = data[key];
      if (v is String) {
        final s = v.trim();
        if (s.isNotEmpty) return s;
      }
      return null;
    }

    return PubrssResult(
      items: feeds,
      introTitle: pick('intro_title'),
      introBody: pick('intro_body'),
    );
  }

  // ---- helpers ----

  static String _hmacSha256Hex(String key, String message) {
    final hmac = Hmac(sha256, utf8.encode(key));
    final digest = hmac.convert(utf8.encode(message));
    return digest.toString(); // crypto.HexCodec 输出已是小写十六进制
  }

  static final _rng = Random.secure();
  static String _randomNonce() {
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// 接口返回的完整结果：RSS 源列表 + 可选介绍文案（后端未返回时为 null）。
class PubrssResult {
  final List<RecommendedFeed> items;
  final String? introTitle;
  final String? introBody;

  const PubrssResult({
    required this.items,
    this.introTitle,
    this.introBody,
  });
}

class PubrssException implements Exception {
  final String message;
  PubrssException(this.message);
  @override
  String toString() => 'PubrssException: $message';
}
