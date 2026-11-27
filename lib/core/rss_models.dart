import 'helpers.dart';

/// 订阅源。全部数据只存在本机，来源是用户自己添加的 RSS/Atom 地址。
class FeedSource {
  int? id;
  String title;
  String url;
  String siteUrl;
  String feedType;
  String iconUrl;
  String category;
  bool syncEnabled;
  int sortOrder;
  int unreadCount;
  DateTime? lastSyncedAt;
  String? lastSyncError;
  DateTime createdAt;

  FeedSource({
    this.id,
    required this.title,
    required this.url,
    this.siteUrl = '',
    this.feedType = 'rss2',
    this.iconUrl = '',
    this.category = '',
    this.syncEnabled = true,
    this.sortOrder = 0,
    this.unreadCount = 0,
    this.lastSyncedAt,
    this.lastSyncError,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get feedTypeLabel {
    switch (feedType) {
      case 'rss1':
        return 'RSS 1.0';
      case 'atom':
        return 'Atom';
      case 'rss2':
      default:
        return 'RSS 2.0';
    }
  }

  /// 没有图标时用名称首字符渲染占位头像
  String get avatarText {
    final name = title.trim().isEmpty ? url : title.trim();
    for (final r in name.runes) {
      final c = String.fromCharCode(r);
      if (c.trim().isNotEmpty) return c.toUpperCase();
    }
    return '?';
  }

  String get hostName => urlHost(url).isEmpty ? url : urlHost(url);

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'url': url,
        'site_url': siteUrl,
        'feed_type': feedType,
        'icon_url': iconUrl,
        'category': category,
        'sync_enabled': syncEnabled ? 1 : 0,
        'sort_order': sortOrder,
        'unread_count': unreadCount,
        'last_synced_at': lastSyncedAt?.millisecondsSinceEpoch,
        'last_sync_error': lastSyncError,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory FeedSource.fromMap(Map<String, dynamic> m) => FeedSource(
        id: m['id'] as int?,
        title: asString(m['title']),
        url: asString(m['url']),
        siteUrl: asString(m['site_url']),
        feedType: asString(m['feed_type'], 'rss2'),
        iconUrl: asString(m['icon_url']),
        category: asString(m['category']),
        syncEnabled: asBool(m['sync_enabled'], true),
        sortOrder: asInt(m['sort_order']),
        unreadCount: asInt(m['unread_count']),
        lastSyncedAt: storedTime(m['last_synced_at']),
        lastSyncError:
            m['last_sync_error'] == null ? null : asString(m['last_sync_error']),
        createdAt: storedTime(m['created_at']) ?? DateTime.now(),
      );
}

/// 推荐订阅源：来自服务端公共池（[PubrssClient]）或本地内置 fallback。
class RecommendedFeed {
  final String name;
  final String url;
  final String category;
  final String description;

  /// 可选：网站首页、图标、标签（服务端接口返回）。
  final String siteUrl;
  final String iconUrl;
  final String tags;

  const RecommendedFeed(
    this.name,
    this.url, {
    this.category = '',
    this.description = '',
    this.siteUrl = '',
    this.iconUrl = '',
    this.tags = '',
  });

  String get host => urlHost(url).isEmpty ? url : urlHost(url);

  /// 服务端接口 `items[]` → RecommendedFeed
  factory RecommendedFeed.fromJson(Map<String, dynamic> json) {
    return RecommendedFeed(
      (json['title'] as String? ?? '').trim(),
      (json['url'] as String? ?? '').trim(),
      category: (json['category'] as String? ?? '').trim(),
      description: (json['description'] as String? ?? '').trim(),
      siteUrl: (json['site_url'] as String? ?? '').trim(),
      iconUrl: (json['icon_url'] as String? ?? '').trim(),
      tags: (json['tags'] as String? ?? '').trim(),
    );
  }
}

/// 一篇文章。列表查询不取 [summary]/[content] 之外的正文字段，见 [RssDatabase]。
class RssArticle {  int? id;
  int feedId;
  String guid;
  String title;
  String link;
  String author;

  /// 纯文本摘要，入库前已去掉 HTML 标签
  String summary;

  /// 原文 HTML，仅详情页读取
  String content;
  String imageUrl;
  DateTime? publishedAt;
  DateTime createdAt;
  bool isRead;
  bool isStarred;

  RssArticle({
    this.id,
    required this.feedId,
    this.guid = '',
    required this.title,
    this.link = '',
    this.author = '',
    this.summary = '',
    this.content = '',
    this.imageUrl = '',
    this.publishedAt,
    DateTime? createdAt,
    this.isRead = false,
    this.isStarred = false,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 排序键：优先发布时间，缺失时退回入库时间
  DateTime get sortAt => publishedAt ?? createdAt;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'feed_source_id': feedId,
        'guid': guid,
        'title': title,
        'link': link,
        'author': author,
        'summary': summary,
        'content': content,
        'image_url': imageUrl,
        'published_at': publishedAt?.millisecondsSinceEpoch,
        'sort_at': sortAt.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'is_read': isRead ? 1 : 0,
        'is_starred': isStarred ? 1 : 0,
      };

  RssArticle copyWith({bool? isRead, bool? isStarred}) => RssArticle(
        id: id,
        feedId: feedId,
        guid: guid,
        title: title,
        link: link,
        author: author,
        summary: summary,
        content: content,
        imageUrl: imageUrl,
        publishedAt: publishedAt,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        isStarred: isStarred ?? this.isStarred,
      );

  factory RssArticle.fromMap(Map<String, dynamic> m) => RssArticle(
        id: m['id'] as int?,
        feedId: asInt(m['feed_source_id']),
        guid: asString(m['guid']),
        title: asString(m['title']),
        link: asString(m['link']),
        author: asString(m['author']),
        summary: asString(m['summary']),
        content: asString(m['content']),
        imageUrl: asString(m['image_url']),
        publishedAt: storedTime(m['published_at']),
        createdAt: storedTime(m['created_at']) ?? DateTime.now(),
        isRead: asBool(m['is_read']),
        isStarred: asBool(m['is_starred']),
      );
}

class RssFolder {
  int? id;
  String name;
  String description;
  DateTime createdAt;
  int sourceCount;
  int unreadCount;

  RssFolder({
    this.id,
    required this.name,
    this.description = '',
    DateTime? createdAt,
    this.sourceCount = 0,
    this.unreadCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory RssFolder.fromMap(Map<String, dynamic> m) => RssFolder(
        id: m['id'] as int?,
        name: asString(m['name']),
        description: asString(m['description']),
        createdAt: storedTime(m['created_at']) ?? DateTime.now(),
        sourceCount: asInt(m['source_count']),
        unreadCount: asInt(m['unread_count']),
      );
}

/// SQLite 时间列存毫秒 int，历史/默认值可能是字符串，两种都要能吃下。
DateTime? storedTime(Object? value) {
  if (value == null) return null;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return parseTime(value);
}
