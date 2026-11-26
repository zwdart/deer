import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../core/rss_models.dart';

class ParsedFeed {
  final String title;
  final String siteUrl;
  final String imageUrl;
  final String feedType;
  final List<RssArticle> articles;

  const ParsedFeed({
    this.title = '',
    this.siteUrl = '',
    this.imageUrl = '',
    this.feedType = 'rss2',
    this.articles = const [],
  });
}

/// 解析 RSS 1.0 / RSS 2.0 / Atom / JSON Feed。
///
/// zebra 原版用 `findElements('content:encoded')` 取命名空间标签，
/// xml 包按 local name 匹配，这些回退分支实际永远命中不了，正文因此丢失。
/// 这里统一按 local name + 可选前缀匹配。
class RssParser {
  RssParser._();

  static const int maxArticlesPerFeed = 400;

  static ParsedFeed? parse(String body, {int feedId = 0, String? baseUrl}) {
    final text = body.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('{') || text.startsWith('[')) {
      return _parseJsonFeed(text, feedId);
    }
    try {
      final document = XmlDocument.parse(text);
      // 只认三种根元素：把网页、网关错误页当成空订阅源会让同步看起来成功。
      switch (document.rootElement.name.local) {
        case 'feed':
          return _parseAtom(document, feedId, baseUrl);
        case 'RDF':
          return _parseRss1(document, feedId, baseUrl);
        case 'rss':
          return _parseRss2(document, feedId, baseUrl);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  // ==================== XML ====================

  static XmlElement? _channel(XmlDocument document) {
    final rss = _first(document.findAllElements('rss'));
    return rss == null ? null : _first(rss.findAllElements('channel'));
  }

  static T? _first<T>(Iterable<T> items) {
    for (final item in items) {
      return item;
    }
    return null;
  }

  static ParsedFeed _parseRss2(XmlDocument document, int feedId, String? baseUrl) {
    final channel = _channel(document);
    final articles = <RssArticle>[];
    for (final item in document.findAllElements('item')) {
      final article = _articleFromItem(
        item,
        feedId: feedId,
        baseUrl: baseUrl,
        guid: _text(item, 'guid') ?? _text(item, 'link') ?? '',
        content: _text(item, 'encoded') ?? _text(item, 'description') ?? '',
        summary: _text(item, 'description') ?? '',
        author: _text(item, 'creator') ?? _text(item, 'author') ?? '',
        published: _text(item, 'pubDate') ?? _text(item, 'date') ?? '',
        mediaImage: _mediaImage(item),
      );
      if (article != null) articles.add(article);
      if (articles.length >= maxArticlesPerFeed) break;
    }
    return ParsedFeed(
      title: _text(channel, 'title') ?? '',
      siteUrl: _text(channel, 'link') ?? '',
      imageUrl: _channelImage(channel),
      feedType: 'rss2',
      articles: articles,
    );
  }

  static ParsedFeed _parseRss1(XmlDocument document, int feedId, String? baseUrl) {
    final channel = _first(document.findAllElements('channel'));
    final articles = <RssArticle>[];
    for (final item in document.findAllElements('item')) {
      final about = item.getAttribute('rdf:about') ??
          item.getAttribute('about',
                  namespaceUri: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#') ??
          '';
      final article = _articleFromItem(
        item,
        feedId: feedId,
        baseUrl: baseUrl,
        guid: about.isNotEmpty ? about : (_text(item, 'link') ?? ''),
        content: _text(item, 'encoded') ?? _text(item, 'description') ?? '',
        summary: _text(item, 'description') ?? '',
        author: _text(item, 'creator') ?? '',
        published: _text(item, 'date') ?? '',
        mediaImage: _mediaImage(item),
      );
      if (article != null) articles.add(article);
      if (articles.length >= maxArticlesPerFeed) break;
    }
    return ParsedFeed(
      title: _text(channel, 'title') ?? '',
      siteUrl: _text(channel, 'link') ?? '',
      feedType: 'rss1',
      articles: articles,
    );
  }

  static ParsedFeed _parseAtom(XmlDocument document, int feedId, String? baseUrl) {
    final feed = document.rootElement;
    final articles = <RssArticle>[];
    for (final entry in document.findAllElements('entry')) {
      final links = entry.children.whereType<XmlElement>().where(
            (e) => e.name.local == 'link',
          );
      String? alternate;
      String? enclosureImage;
      for (final link in links) {
        final rel = link.getAttribute('rel') ?? 'alternate';
        final href = link.getAttribute('href');
        if (href == null || href.isEmpty) continue;
        if (alternate == null && rel == 'alternate') alternate = href;
        if (enclosureImage == null &&
            rel == 'enclosure' &&
            _isImage(link.getAttribute('type'))) {
          enclosureImage = href;
        }
      }
      final article = _articleFromItem(
        entry,
        feedId: feedId,
        baseUrl: baseUrl,
        guid: _text(entry, 'id') ?? '',
        content: _text(entry, 'content') ?? _text(entry, 'summary') ?? '',
        summary: _text(entry, 'summary') ?? '',
        author: _nestedText(entry, 'author', 'name') ?? _text(entry, 'author') ?? '',
        published: _text(entry, 'published') ?? _text(entry, 'updated') ?? '',
        linkOverride: alternate,
        mediaImage: _mediaImage(entry) ?? enclosureImage,
      );
      if (article != null) articles.add(article);
      if (articles.length >= maxArticlesPerFeed) break;
    }
    return ParsedFeed(
      title: _text(feed, 'title') ?? '',
      siteUrl: _atomLink(feed),
      imageUrl: _text(feed, 'logo') ?? _text(feed, 'icon') ?? '',
      feedType: 'atom',
      articles: articles,
    );
  }

  static String _atomLink(XmlElement parent) {
    String? alternate;
    String? first;
    for (final link in parent.children.whereType<XmlElement>()) {
      if (link.name.local != 'link') continue;
      final value = link.getAttribute('href') ?? link.innerText.trim();
      if (value.isEmpty) continue;
      first ??= value;
      if ((link.getAttribute('rel') ?? 'alternate') == 'alternate') {
        alternate = value;
        break;
      }
    }
    return alternate ?? first ?? '';
  }

  static String _channelImage(XmlElement? channel) {
    if (channel == null) return '';
    return _text(_first(channel.findElements('image')), 'url') ??
        _text(channel, 'logo') ??
        '';
  }

  /// 按 local name 匹配，命名空间前缀（content:/dc:/media:）因此不再需要硬编码。
  static String? _text(XmlElement? parent, String local) {
    if (parent == null) return null;
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.local == local) {
        final value = child.innerText.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static String? _nestedText(
      XmlElement? parent, String outer, String inner) {
    if (parent == null) return null;
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.local != outer) continue;
      final value = _text(child, inner);
      if (value != null) return value;
    }
    return null;
  }

  static String? _mediaImage(XmlElement item) {
    for (final child in item.children.whereType<XmlElement>()) {
      final local = child.name.local;
      if (local != 'thumbnail' && local != 'content') continue;
      final url = child.getAttribute('url');
      if (url == null || url.isEmpty) continue;
      final medium = child.getAttribute('medium') ?? '';
      final type = child.getAttribute('type') ?? '';
      if (local == 'content' &&
          medium != 'image' &&
          !_isImage(type) &&
          !_looksLikeImage(url)) {
        continue;
      }
      return url;
    }
    return null;
  }

  // ==================== 条目组装 ====================

  static RssArticle? _articleFromItem(
    XmlElement item, {
    required int feedId,
    required String? baseUrl,
    required String guid,
    required String content,
    required String summary,
    required String author,
    required String published,
    String? mediaImage,
    String? linkOverride,
  }) {
    final title = _text(item, 'title') ?? '';
    final link = _resolve(
        linkOverride ?? _text(item, 'link') ?? '', baseUrl);
    final id = guid.isNotEmpty ? guid : (link.isNotEmpty ? link : title);
    if (id.isEmpty && title.isEmpty) return null;

    var image = mediaImage;
    if (image == null || image.isEmpty) {
      for (final child in item.children.whereType<XmlElement>()) {
        if (child.name.local != 'enclosure') continue;
        final url = child.getAttribute('url') ?? '';
        if (url.isEmpty) continue;
        if (_isImage(child.getAttribute('type')) || _looksLikeImage(url)) {
          image = url;
          break;
        }
      }
    }
    if (image == null || image.isEmpty) image = firstImageOf(content);

    final plain = plainText(summary.isNotEmpty ? summary : content);
    return RssArticle(
      feedId: feedId,
      guid: id.length > 500 ? id.substring(0, 500) : id,
      title: cleanTitle(title),
      link: link,
      author: plainText(author),
      summary: _clip(plain, 400),
      content: content,
      imageUrl: _resolve(image ?? '', baseUrl),
      publishedAt: parseDate(published),
    );
  }

  // ==================== JSON Feed ====================

  static ParsedFeed? _parseJsonFeed(String body, int feedId) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final items = decoded['items'];
      final articles = <RssArticle>[];
      if (items is List) {
        for (final raw in items) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);
          final html = _string(map['content_html']);
          final text = _string(map['content_text']);
          final url = _string(map['url']);
          final content = html.isNotEmpty ? html : text;
          final image = _string(map['image']).isNotEmpty
              ? _string(map['image'])
              : _string(map['banner_image']);
          final author = map['author'];
          articles.add(RssArticle(
            feedId: feedId,
            guid: url.isNotEmpty ? url : _string(map['id']),
            title: cleanTitle(_string(map['title'])),
            link: url,
            author: author is Map
                ? _string(author['name'])
                : _string(map['author']),
            summary: _clip(plainText(_string(map['summary']).isNotEmpty
                ? _string(map['summary'])
                : (text.isNotEmpty ? text : content)), 400),
            content: content,
            imageUrl: image.isNotEmpty ? image : firstImageOf(content) ?? '',
            publishedAt: parseDate(_string(map['date_published'])),
          ));
          if (articles.length >= maxArticlesPerFeed) break;
        }
      }
      return ParsedFeed(
        title: _string(decoded['title']),
        siteUrl: _string(decoded['home_page_url']),
        imageUrl: _string(decoded['favicon']),
        feedType: 'json',
        articles: articles,
      );
    } catch (_) {
      return null;
    }
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  // ==================== 工具 ====================

  static bool _isImage(String? mime) =>
      mime != null && mime.toLowerCase().startsWith('image/');

  static bool _looksLikeImage(String url) => RegExp(
        r'\.(jpe?g|png|gif|webp|avif|bmp|svg)([?#]|$)',
        caseSensitive: false,
      ).hasMatch(url);

  static String _resolve(String url, String? baseUrl) {
    if (url.isEmpty || baseUrl == null || baseUrl.isEmpty) return url;
    final base = Uri.tryParse(baseUrl);
    final uri = Uri.tryParse(url);
    if (base == null || uri == null) return url;
    if (uri.hasScheme) return url;
    return base.resolveUri(uri).toString();
  }

  static String cleanTitle(String value) =>
      plainText(value).replaceAll(RegExp(r'\s+'), ' ').trim();

  /// 去标签、解实体、压缩空白，供信息流摘要使用。
  static String plainText(String input) {
    if (input.isEmpty) return '';
    var text = input;
    final markup = input.contains('<') || input.contains('&');
    if (markup) {
      try {
        text = html_parser.parse(input).documentElement?.text ?? input;
      } catch (_) {
        text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
      }
    }
    text = text
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[\t\r]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r' {2,}'), ' ');
    return text.trim();
  }

  static String? firstImageOf(String html) {
    if (html.isEmpty || !html.contains('<img')) return null;
    final match = RegExp(r"""<img[^>]+src\s*=\s*["']([^"']+)["']""",
            caseSensitive: false)
        .firstMatch(html);
    final src = match?.group(1)?.trim();
    return (src == null || src.isEmpty) ? null : src;
  }

  static String _clip(String value, int max) {
    if (value.length <= max) return value;
    return '${value.substring(0, max).trimRight()}…';
  }

  static const _monthNames = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// 同时支持 ISO-8601、RFC 822 和中文源常见的 `2026-07-21 10:00:00`。
  static DateTime? parseDate(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.toLocal();

    final clean = value.replaceFirst(RegExp(r'^\s*\w+\s*,\s*'), '');
    final match = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})\w*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([A-Za-z]{2,4}|[+-]\d{4})?',
    ).firstMatch(clean);
    if (match == null) return null;

    final month = _monthNames[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    var year = int.parse(match.group(3)!);
    if (year < 100) year += year < 70 ? 2000 : 1900;

    final date = DateTime(
      year,
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.tryParse(match.group(6) ?? '0') ?? 0,
    );
    final zone = match.group(7);
    if (zone == null) return date;
    if (zone.length == 4) {
      final sign = zone.startsWith('-') ? -1 : 1;
      final digits = zone.substring(1);
      final offset = Duration(
        hours: int.parse(digits.substring(0, 2)),
        minutes: int.parse(digits.substring(2)),
      );
      return date
          .subtract(Duration(milliseconds: sign * offset.inMilliseconds))
          .toLocal();
    }
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      date.hour,
      date.minute,
      date.second,
    ).toLocal();
  }
}
