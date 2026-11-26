import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/helpers.dart';
import '../core/i18n.dart';
import '../core/paths.dart';
import '../core/rss_database.dart';
import '../core/rss_models.dart';
import '../core/rss_settings.dart';
import '../rss/rss_fetcher.dart';
import '../rss/rss_importer.dart';
import '../rss/rss_parser.dart';

enum RssScope { all, unread, starred, feed, folder, search }

/// 本地 RSS 的唯一状态入口：订阅源、收藏夹、信息流、同步。
/// 所有数据都在本机 SQLite，抓取只走用户自己添加的地址。
class RssController extends ChangeNotifier {
  static const int pageSize = 24;
  static const int _syncBatchSize = 4;
  static const int _failureBackoff = 3;

  final AppPaths paths;
  final RssDatabase db;
  final RssSettingsStore store;

  RssController(this.paths)
      : db = RssDatabase(paths.rssDatabasePath),
        store = RssSettingsStore(paths.rssSettingsPath);

  RssSettings settings = RssSettings();

  List<FeedSource> feeds = [];
  List<RssFolder> folders = [];
  List<RssArticle> articles = [];

  RssScope scope = RssScope.all;
  int? scopeFeedId;
  int? scopeFolderId;
  String keyword = '';

  bool loading = false;
  bool syncing = false;
  bool hasMore = true;
  int totalUnread = 0;
  int starredTotal = 0;
  int syncDone = 0;
  int syncTotal = 0;
  String? syncTarget;
  String? error;

  int? _cursorSortAt;
  int? _cursorId;
  final Map<int, int> _failures = {};
  final Map<int, List<FeedSource>> _folderMembers = {};
  int _cycle = 0;
  Timer? _timer;
  bool _disposed = false;

  /// 内置精选，仅在「推荐」页和「添加订阅」里作为候选，不会自动写入数据库或联网。
  static const List<RecommendedFeed> recommended = [
    RecommendedFeed(
      '虎嗅网',
      'https://rss.huxiu.com',
      category: '商业科技',
      description: '聚焦科技与商业的深度报道和观点。',
    ),
    RecommendedFeed(
      '钛媒体',
      'https://www.tmtpost.com/feed',
      category: '商业科技',
      description: 'TMT 领域的产业资讯、公司动态与评论。',
    ),
    RecommendedFeed(
      '美团技术团队',
      'https://tech.meituan.com/rss.xml',
      category: '技术博客',
      description: '一线工程师分享的架构、算法与工程实践。',
    ),
    RecommendedFeed(
      '阮一峰的网络日志',
      'https://www.ruanyifeng.com/blog/atom.xml',
      category: '技术博客',
      description: '每周分享科技、编程与互联网的观察。',
    ),
    RecommendedFeed(
      '别的',
      'https://www.biede.com/feed/',
      category: '独立博客',
      description: '关于产品、设计与互联网的独立观察。',
    ),
    RecommendedFeed(
      'Nature',
      'https://www.nature.com/nature.rss',
      category: '科学',
      description: '国际顶级科学期刊的最新研究摘要。',
    ),
    RecommendedFeed(
      'Hacker News',
      'https://news.ycombinator.com/rss',
      category: '英文资讯',
      description: '全球开发者关注的技术社区热帖。',
    ),
    RecommendedFeed(
      'The Verge',
      'https://www.theverge.com/rss/index.xml',
      category: '英文资讯',
      description: '消费科技、数码产品与行业新闻。',
    ),
  ];

  bool get disposed => _disposed;

  FeedSource? get currentFeed {
    final id = scopeFeedId;
    if (id == null) return null;
    for (final feed in feeds) {
      if (feed.id == id) return feed;
    }
    return null;
  }

  RssFolder? get currentFolder {
    final id = scopeFolderId;
    if (id == null) return null;
    for (final folder in folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  String get scopeTitle {
    switch (scope) {
      case RssScope.all:
        return tr('ui.everything');
      case RssScope.unread:
        return tr('ui.to_read');
      case RssScope.starred:
        return tr('rss.star');
      case RssScope.feed:
        return currentFeed?.title ?? tr('rss.feed');
      case RssScope.folder:
        return currentFolder?.name ?? tr('rss.folders');
      case RssScope.search:
        return trf('ui.search__arg_0', [keyword]);
    }
  }

  // ==================== 生命周期 ====================

  Future<void> init() async {
    try {
      await db.open();
    } catch (e) {
      error = trf('rss.could_not_open_the_news_database__arg_0', ['$e']);
      return;
    }
    settings = await store.load();
    if (settings.keepDays > 0) {
      await db.clearHistory(
        before: DateTime.now().subtract(Duration(days: settings.keepDays)),
      );
    }
    await refreshCounters();
    await loadFeeds();
    await loadFolders();
    await openScope(RssScope.all);
    _applyTimer();
    unawaited(_maybeAutoBackup());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(db.close());
    super.dispose();
  }

  void _applyTimer() {
    _timer?.cancel();
    _timer = null;
    if (!settings.autoSync) return;
    _timer = Timer.periodic(
      Duration(minutes: settings.syncIntervalMinutes),
      (_) => syncAll(),
    );
  }

  // ==================== 读取 ====================

  Future<void> loadFeeds() async {
    feeds = await db.feedSources();
    notifyListeners();
  }

  Future<void> loadFolders() async {
    folders = await db.folders();
    notifyListeners();
  }

  Future<void> refreshCounters() async {
    totalUnread = await db.totalUnread();
    starredTotal = await db.starredCount();
    notifyListeners();
  }

  RssFilter get _scopeFilter {
    switch (scope) {
      case RssScope.all:
        return const RssFilter();
      case RssScope.unread:
        return const RssFilter(unread: true);
      case RssScope.starred:
        return const RssFilter(starred: true);
      case RssScope.feed:
        return RssFilter(feedId: scopeFeedId);
      case RssScope.folder:
        return RssFilter(
            feedIds: feedsForFolder(scopeFolderId).map((f) => f.id!).toList());
      case RssScope.search:
        return RssFilter(keyword: keyword);
    }
  }

  List<FeedSource> feedsForFolder(int? folderId) {
    if (folderId == null) return feeds;
    final ids = <int>{};
    for (final folder in folders) {
      if (folder.id != folderId) continue;
      // folderSources 只在打开收藏夹时按需查询，这里用缓存的成员列表
      for (final feed in _folderMembers[folderId] ?? const <FeedSource>[]) {
        ids.add(feed.id!);
      }
    }
    return feeds.where((f) => ids.contains(f.id)).toList();
  }

  Future<void> openScope(RssScope next, {int? feedId, int? folderId}) async {
    scope = next;
    scopeFeedId = feedId;
    scopeFolderId = folderId;
    if (next != RssScope.search) keyword = '';
    if (next == RssScope.folder && folderId != null) {
      _folderMembers[folderId] = await db.folderSources(folderId);
    }
    loading = true;
    error = null;
    articles = [];
    _cursorSortAt = null;
    _cursorId = null;
    hasMore = true;
    notifyListeners();
    await _fetchPage();
    loading = false;
    notifyListeners();
  }

  Future<void> reload() async {
    _cursorSortAt = null;
    _cursorId = null;
    hasMore = true;
    await _fetchPage();
    notifyListeners();
  }

  Future<void> _fetchPage() async {
    final page = await _query(limit: pageSize);
    articles = page;
    _advanceCursor(page);
  }

  Future<void> loadMore() async {
    if (!hasMore || loading) return;
    loading = true;
    notifyListeners();
    final more = await _query(limit: pageSize);
    if (more.isEmpty) {
      hasMore = false;
    } else {
      articles = [...articles, ...more];
      _advanceCursor(more);
    }
    loading = false;
    notifyListeners();
  }

  Future<List<RssArticle>> _query({required int limit}) {
    return db.articles(
      _scopeFilter,
      limit: limit,
      beforeSortAt: _cursorSortAt,
      beforeId: _cursorId,
      oldestFirst: !settings.newestFirst,
    );
  }

  void _advanceCursor(List<RssArticle> page) {
    hasMore = page.length >= pageSize;
    if (page.isEmpty) return;
    final last = page.last;
    _cursorSortAt = last.sortAt.millisecondsSinceEpoch;
    _cursorId = last.id;
  }

  Future<void> search(String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    keyword = text;
    await openScope(RssScope.search);
  }

  // ==================== 同步 ====================

  /// 拉取单个源。返回新增条数。
  Future<int> syncFeed(FeedSource source) async {
    final id = source.id;
    if (id == null) return 0;
    final result = await RssFetcher.fetch(
      source.url,
      ifModifiedSince: source.lastSyncedAt,
    );
    if (result.notModified) {
      await db.noteSyncResult(id);
      _failures[id] = 0;
      return 0;
    }
    final body = result.body;
    if (result.error != null || body == null) {
      await db.noteSyncResult(id, error: result.error ?? '未知错误');
      _failures[id] = (_failures[id] ?? 0) + 1;
      return 0;
    }

    final parsed = RssParser.parse(body, feedId: id, baseUrl: source.url);
    if (parsed == null) {
      await db.noteSyncResult(id, error: tr('rss.could_not_parse_the_feed'));
      _failures[id] = (_failures[id] ?? 0) + 1;
      return 0;
    }

    var added = 0;
    // 旧→新写入，未读计数与入库顺序一致
    for (final article in parsed.articles.reversed) {
      if (await db.insertArticle(article)) added++;
    }

    if (source.iconUrl.isEmpty && parsed.imageUrl.isNotEmpty) {
      source.iconUrl = parsed.imageUrl;
      await db.updateFeedSource(source);
    }
    if (source.siteUrl.isEmpty && parsed.siteUrl.isNotEmpty) {
      source.siteUrl = parsed.siteUrl;
      await db.updateFeedSource(source);
    }
    if (source.feedType != parsed.feedType && parsed.feedType.isNotEmpty) {
      source.feedType = parsed.feedType;
      await db.updateFeedSource(source);
    }

    await db.noteSyncResult(id);
    _failures[id] = 0;
    return added;
  }

  Future<void> syncOne(int feedId) async {
    if (syncing) return;
    final matches = feeds.where((f) => f.id == feedId);
    if (matches.isEmpty) return;
    final source = matches.first;
    syncing = true;
    syncTarget = source.title;
    syncDone = 0;
    syncTotal = 1;
    notifyListeners();
    try {
      await syncFeed(source);
    } catch (e) {
      error = trf('rss.sync_failed__arg_0', ['$e']);
    }
    syncing = false;
    syncTarget = null;
    await loadFeeds();
    await refreshCounters();
    await reload();
    notifyListeners();
  }

  /// 同步所有启用的源。连续失败达到阈值的源降频到每三轮一次。
  Future<void> syncAll({List<int>? only}) async {
    if (syncing) return;
    final candidates = feeds
        .where((f) => f.syncEnabled && f.id != null)
        .where((f) => only == null || only.contains(f.id))
        .where((f) => (_failures[f.id] ?? 0) < _failureBackoff || _cycle % 3 == 0)
        .toList();
    if (candidates.isEmpty) return;

    _cycle++;
    syncing = true;
    error = null;
    syncDone = 0;
    syncTotal = candidates.length;
    syncTarget = tr('rss.syncing');
    notifyListeners();

    for (var i = 0; i < candidates.length; i += _syncBatchSize) {
      final batch = candidates.sublist(
        i,
        (i + _syncBatchSize).clamp(0, candidates.length),
      );
      await Future.wait(batch.map((source) async {
        try {
          await syncFeed(source);
        } catch (e) {
          debugPrint('rss sync ${source.url} failed: $e');
        }
        syncDone++;
        notifyListeners();
      }));
    }

    syncing = false;
    syncTarget = null;
    await loadFeeds();
    await refreshCounters();
    await reload();
    if (scope == RssScope.folder && scopeFolderId != null) {
      _folderMembers[scopeFolderId!] = await db.folderSources(scopeFolderId!);
    }
    notifyListeners();
  }

  // ==================== 订阅源 ====================

  /// 添加并立即抓取一次；URL 已存在时返回 null 并给出提示。
  Future<FeedSource?> addFeed(String url, {String title = ''}) async {
    var clean = url.trim();
    if (clean.isEmpty) return null;
    if (!clean.contains('://')) clean = 'https://$clean';
    final existing = await db.feedSourceByUrl(clean);
    if (existing != null) {
      error = tr('rss.this_feed_is_already_added');
      notifyListeners();
      return null;
    }
    final source = FeedSource(
      title: title.trim().isEmpty ? _titleFromUrl(clean) : title.trim(),
      url: clean,
      siteUrl: _originOf(clean),
    );
    final id = await db.insertFeedSource(source);
    if (id == null || id == 0) {
      error = tr('device.could_not_add_it_check_the_url');
      notifyListeners();
      return null;
    }
    final saved = await db.feedSource(id);
    if (saved == null) return null;
    feeds = [...feeds, saved];
    notifyListeners();
    try {
      await syncFeed(saved);
    } catch (e) {
      debugPrint('rss initial sync failed: $e');
    }
    await loadFeeds();
    await refreshCounters();
    return await db.feedSource(id);
  }

  Future<void> updateFeed(FeedSource source) async {
    await db.updateFeedSource(source);
    await loadFeeds();
    notifyListeners();
  }

  Future<void> setFeedSyncEnabled(FeedSource source, bool enabled) async {
    final id = source.id;
    if (id == null) return;
    await db.setSyncEnabled(id, enabled);
    await loadFeeds();
    notifyListeners();
  }

  Future<void> deleteFeed(int id) async {
    await db.deleteFeedSource(id);
    if (scopeFeedId == id) {
      await openScope(RssScope.all);
    }
    await loadFeeds();
    await loadFolders();
    await refreshCounters();
    notifyListeners();
  }

  Future<void> reorderFeeds(List<int> ids) async {
    await db.reorderFeedSources(ids);
    await loadFeeds();
    notifyListeners();
  }

  // ==================== 收藏夹 ====================

  Future<RssFolder?> createFolder(String name, {String description = ''}) async {
    final title = name.trim();
    if (title.isEmpty) return null;
    final folder = RssFolder(name: title, description: description.trim());
    folder.id = await db.insertFolder(folder);
    await loadFolders();
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(int id, String name, String description) async {
    await db.updateFolder(RssFolder(id: id, name: name, description: description));
    await loadFolders();
    notifyListeners();
  }

  Future<void> deleteFolder(int id) async {
    await db.deleteFolder(id);
    _folderMembers.remove(id);
    if (scope == RssScope.folder && scopeFolderId == id) {
      await openScope(RssScope.all);
    }
    await loadFolders();
    await refreshCounters();
    notifyListeners();
  }

  Future<List<FeedSource>> folderSources(int folderId) =>
      db.folderSources(folderId);

  Future<void> setFolderMembers(int folderId, Set<int> sourceIds) async {
    final current = await db.folderSources(folderId);
    final currentIds = current.map((s) => s.id).toSet();
    for (final feed in current.where((s) => !sourceIds.contains(s.id))) {
      await db.removeSourceFromFolder(folderId, feed.id!);
    }
    for (final id in sourceIds.where((id) => !currentIds.contains(id))) {
      await db.addSourceToFolder(folderId, id);
    }
    _folderMembers[folderId] = await db.folderSources(folderId);
    await loadFolders();
    if (scope == RssScope.folder && scopeFolderId == folderId) await reload();
    notifyListeners();
  }

  Future<void> addFeedToFolder(int feedId, int folderId) async {
    await db.addSourceToFolder(folderId, feedId);
    _folderMembers[folderId] = await db.folderSources(folderId);
    await loadFolders();
    notifyListeners();
  }

  Future<void> removeFeedFromFolder(int feedId, int folderId) async {
    await db.removeSourceFromFolder(folderId, feedId);
    _folderMembers.remove(folderId);
    await loadFolders();
    notifyListeners();
  }

  Future<List<RssFolder>> foldersOfFeed(int feedId) => db.foldersOfSource(feedId);

  // ==================== 文章 ====================

  Future<RssArticle?> article(int id) => db.article(id);

  Future<void> setRead(RssArticle article, {required bool read}) async {
    final id = article.id;
    if (id == null) return;
    await db.markRead(id, read: read);
    articles = [
      for (final a in articles)
        if (a.id == id) a.copyWith(isRead: read) else a,
    ];
    await loadFeeds();
    totalUnread = await db.totalUnread();
    notifyListeners();
  }

  Future<void> setStarred(RssArticle article, {required bool starred}) async {
    final id = article.id;
    if (id == null) return;
    await db.setStarred(id, starred: starred);
    articles = [
      for (final a in articles)
        if (a.id == id) a.copyWith(isStarred: starred) else a,
    ];
    if (scope == RssScope.starred && !starred) {
      articles.removeWhere((a) => a.id == id);
    }
    starredTotal = await db.starredCount();
    notifyListeners();
  }

  Future<void> toggleStar(RssArticle article) =>
      setStarred(article, starred: !article.isStarred);

  Future<void> deleteArticle(RssArticle article) async {
    final id = article.id;
    if (id == null) return;
    await db.deleteArticle(id);
    articles.removeWhere((a) => a.id == id);
    await loadFeeds();
    totalUnread = await db.totalUnread();
    starredTotal = await db.starredCount();
    notifyListeners();
  }

  Future<void> markFeedRead(int feedId) async {
    await db.markFeedRead(feedId);
    await loadFeeds();
    if (scope == RssScope.unread) {
      articles.removeWhere((a) => a.feedId == feedId);
    } else {
      articles = [
        for (final a in articles)
          if (a.feedId == feedId) a.copyWith(isRead: true) else a,
      ];
    }
    totalUnread = await db.totalUnread();
    notifyListeners();
  }

  Future<void> markAllRead() async {
    for (final feed in feeds.where((f) => f.unreadCount > 0)) {
      await db.markFeedRead(feed.id!);
    }
    await loadFeeds();
    if (scope == RssScope.unread) {
      articles = [];
    } else {
      articles = [for (final a in articles) a.copyWith(isRead: true)];
    }
    totalUnread = 0;
    notifyListeners();
  }

  Future<void> clearFeedArticles(int feedId) async {
    await db.clearFeedArticles(feedId);
    await loadFeeds();
    if (scopeFeedId == feedId || scope == RssScope.all) {
      await reload();
    } else {
      articles.removeWhere((a) => a.feedId == feedId);
    }
    totalUnread = await db.totalUnread();
    notifyListeners();
  }

  Future<int> clearHistory({DateTime? before}) async {
    final removed = await db.clearHistory(before: before);
    totalUnread = await db.totalUnread();
    await loadFeeds();
    await reload();
    notifyListeners();
    return removed;
  }

  // ==================== 导入导出 ====================

  Future<String> exportOpml() async {
    final members = <int, List<FeedSource>>{};
    for (final folder in folders) {
      members[folder.id!] = await db.folderSources(folder.id!);
    }
    return RssExchange.exportOpml(feeds, folders, members);
  }

  Future<String> exportCsv() async {
    final folderOf = <String, String>{};
    for (final folder in folders) {
      for (final source in await db.folderSources(folder.id!)) {
        folderOf[source.url] = folder.name;
      }
    }
    return RssExchange.exportCsv(feeds, folderOf: folderOf);
  }

  Future<String> writeExport(String filename, String content) async {
    final dir = Directory(paths.rssExportDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, _safeName(filename)));
    await file.writeAsString(content);
    return file.path;
  }

  /// 返回 (新增订阅数, 新建收藏夹数)
  Future<(int, int)> importOpml(String text) async {
    final parsed = RssExchange.parseOpml(text);
    return _applyImport(parsed.sources, parsed.folders);
  }

  Future<(int, int)> importCsv(String text) async {
    final sources = RssExchange.parseCsv(text);
    return _applyImport(sources, const []);
  }

  Future<(int, int)> _applyImport(
    List<FeedSource> sources,
    List<OpmlFolder> folderDefs,
  ) async {
    final idByUrl = <String, int>{};
    var added = 0;
    for (final source in sources) {
      final existing = await db.feedSourceByUrl(source.url);
      if (existing != null) {
        idByUrl[source.url] = existing.id!;
        continue;
      }
      final id = await db.insertFeedSource(source);
      if (id == null || id == 0) continue;
      idByUrl[source.url] = id;
      added++;
    }

    var createdFolders = 0;
    for (final def in folderDefs) {
      final ids = def.urls.map((u) => idByUrl[u]).whereType<int>().toList();
      if (ids.isEmpty) continue;
      RssFolder? folder;
      for (final f in folders) {
        if (f.name == def.name) {
          folder = f;
          break;
        }
      }
      if (folder == null) {
        final folderId = await db.insertFolder(RssFolder(name: def.name));
        if (folderId == 0) continue;
        folder = RssFolder(id: folderId, name: def.name);
        folders = [...folders, folder];
        createdFolders++;
      }
      for (final id in ids) {
        await db.addSourceToFolder(folder.id!, id);
      }
    }

    await loadFeeds();
    await loadFolders();
    await refreshCounters();
    notifyListeners();
    return (added, createdFolders);
  }

  Future<void> backupNow() async {
    final dir = Directory(paths.rssBackupDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final members = <int, List<FeedSource>>{};
    for (final folder in folders) {
      members[folder.id!] = await db.folderSources(folder.id!);
    }
    final file = File(p.join(dir.path, 'rss_$stamp.opml'));
    await file.writeAsString(RssExchange.exportOpml(feeds, folders, members));

    final backups = (await dir.list().where((e) => e is File).toList())
        .where((e) => p.basename(e.path).startsWith('rss_') && e.path.endsWith('.opml'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in backups.skip(3)) {
      try {
        await File(old.path).delete();
      } catch (_) {}
    }
    await store.save(settings, backupAt: DateTime.now());
  }

  Future<void> _maybeAutoBackup() async {
    if (!settings.autoBackup) return;
    final last = store.lastBackupAt;
    if (last != null && DateTime.now().difference(last).inDays < 7) return;
    try {
      await backupNow();
    } catch (e) {
      debugPrint('rss backup failed: $e');
    }
  }

  // ==================== 设置 ====================

  Future<void> update(void Function(RssSettings) edit) async {
    edit(settings);
    await store.save(settings);
    _applyTimer();
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  static String _titleFromUrl(String url) {
    final host = urlHost(url);
    if (host.isEmpty) return url;
    return host.replaceFirst('www.', '');
  }

  static String _originOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '';
    return '${uri.scheme}://${uri.host}';
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
}
