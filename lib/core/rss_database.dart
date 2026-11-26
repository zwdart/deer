import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'helpers.dart';
import 'rss_models.dart';

/// 信息流的查询条件。订阅源、文件夹、收藏、未读、搜索共用同一套 SQL 路径。
class RssFilter {
  final int? feedId;
  final List<int>? feedIds;
  final bool? starred;
  final bool? unread;
  final String? keyword;

  const RssFilter({
    this.feedId,
    this.feedIds,
    this.starred,
    this.unread,
    this.keyword,
  });

  RssFilter copyWith({
    Object? feedId = _sentinel,
    Object? feedIds = _sentinel,
    Object? starred = _sentinel,
    Object? unread = _sentinel,
    Object? keyword = _sentinel,
  }) {
    return RssFilter(
      feedId: feedId == _sentinel ? this.feedId : feedId as int?,
      feedIds: feedIds == _sentinel ? this.feedIds : feedIds as List<int>?,
      starred: starred == _sentinel ? this.starred : starred as bool?,
      unread: unread == _sentinel ? this.unread : unread as bool?,
      keyword: keyword == _sentinel ? this.keyword : keyword as String?,
    );
  }

  static const Object _sentinel = Object();
}

class RssDatabase {
  final String path;
  Database? _db;

  RssDatabase(this.path);

  static const listColumns =
      'id, feed_source_id, guid, title, link, author, summary, image_url, '
      'published_at, sort_at, created_at, is_read, is_starred';

  Future<void> open() async {
    if (_db != null) return;
    await Directory(p.dirname(path)).create(recursive: true);
    _db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
        await db.execute('PRAGMA busy_timeout = 5000');
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async => _create(db),
      onOpen: (db) async => _create(db),
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db == null) return;
    try {
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
    await db.close();
  }

  Future<void> _create(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS feed_sources (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  title           TEXT    NOT NULL DEFAULT '',
  url             TEXT    NOT NULL,
  site_url        TEXT    NOT NULL DEFAULT '',
  feed_type       TEXT    NOT NULL DEFAULT 'rss2',
  icon_url        TEXT    NOT NULL DEFAULT '',
  category        TEXT    NOT NULL DEFAULT '',
  sync_enabled    INTEGER NOT NULL DEFAULT 1,
  sort_order      INTEGER NOT NULL DEFAULT 0,
  unread_count    INTEGER NOT NULL DEFAULT 0,
  last_synced_at  INTEGER,
  last_sync_error TEXT,
  created_at      INTEGER NOT NULL
)''');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS feed_sources_url ON feed_sources(url)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS feed_sources_order ON feed_sources(sort_order, created_at)');

    await db.execute('''
CREATE TABLE IF NOT EXISTS articles (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  feed_source_id INTEGER NOT NULL,
  guid           TEXT    NOT NULL,
  title          TEXT    NOT NULL DEFAULT '',
  link           TEXT    NOT NULL DEFAULT '',
  author         TEXT    NOT NULL DEFAULT '',
  summary        TEXT    NOT NULL DEFAULT '',
  content        TEXT    NOT NULL DEFAULT '',
  image_url      TEXT    NOT NULL DEFAULT '',
  published_at   INTEGER,
  sort_at        INTEGER NOT NULL,
  created_at     INTEGER NOT NULL,
  is_read        INTEGER NOT NULL DEFAULT 0,
  is_starred     INTEGER NOT NULL DEFAULT 0,
  UNIQUE(feed_source_id, guid)
)''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS articles_sort ON articles(sort_at DESC, id DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS articles_feed ON articles(feed_source_id, sort_at DESC, id DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS articles_read ON articles(is_read)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS articles_starred ON articles(is_starred)');

    await db.execute('''
CREATE TABLE IF NOT EXISTS rss_folders (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL,
  description TEXT    NOT NULL DEFAULT '',
  created_at  INTEGER NOT NULL
)''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS rss_folder_items (
  folder_id INTEGER NOT NULL,
  source_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (folder_id, source_id),
  FOREIGN KEY (folder_id) REFERENCES rss_folders(id) ON DELETE CASCADE,
  FOREIGN KEY (source_id) REFERENCES feed_sources(id) ON DELETE CASCADE
)''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS folder_items_source ON rss_folder_items(source_id)');
  }

  // ==================== 订阅源 ====================

  Future<List<FeedSource>> feedSources() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.query('feed_sources',
        orderBy: 'sort_order ASC, created_at DESC, id DESC');
    return rows.map(FeedSource.fromMap).toList();
  }

  Future<FeedSource?> feedSource(int id) async {
    final db = _db;
    if (db == null) return null;
    final rows = await db.query('feed_sources', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return FeedSource.fromMap(rows.first);
  }

  Future<FeedSource?> feedSourceByUrl(String url) async {
    final db = _db;
    if (db == null) return null;
    final rows = await db
        .query('feed_sources', where: 'url = ?', whereArgs: [url], limit: 1);
    if (rows.isEmpty) return null;
    return FeedSource.fromMap(rows.first);
  }

  /// URL 上有唯一索引，重复添加时返回 null 而不是错误的 rowid。
  Future<int?> insertFeedSource(FeedSource source) async {
    final db = _db;
    if (db == null) return null;
    if (await feedSourceByUrl(source.url) != null) return null;
    return db.insert('feed_sources', source.toMap());
  }

  Future<void> updateFeedSource(FeedSource source) async {
    final db = _db;
    if (db == null || source.id == null) return;
    final map = source.toMap()
      ..remove('id')
      ..remove('unread_count')
      ..remove('created_at');
    await db.update('feed_sources', map,
        where: 'id = ?', whereArgs: [source.id]);
  }

  Future<void> deleteFeedSource(int id) async {
    final db = _db;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete('articles', where: 'feed_source_id = ?', whereArgs: [id]);
      await txn.delete('rss_folder_items', where: 'source_id = ?', whereArgs: [id]);
      await txn.delete('feed_sources', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> noteSyncResult(int id, {String? error}) async {
    final db = _db;
    if (db == null) return;
    await db.update(
      'feed_sources',
      {
        'last_synced_at': DateTime.now().millisecondsSinceEpoch,
        'last_sync_error': error,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 手工排序：按传入顺序写回 sort_order
  Future<void> reorderFeedSources(List<int> ids) async {
    final db = _db;
    if (db == null) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < ids.length; i++) {
        batch.update('feed_sources', {'sort_order': i},
            where: 'id = ?', whereArgs: [ids[i]]);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> setSyncEnabled(int id, bool enabled) async {
    final db = _db;
    if (db == null) return;
    await db.update('feed_sources', {'sync_enabled': enabled ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  // ==================== 文章 ====================

  /// [full] 为 true 时附带正文，供详情页使用；信息流只取轻量子集。
  Future<List<RssArticle>> articles(
    RssFilter filter, {
    int limit = 24,
    int? beforeSortAt,
    int? beforeId,
    bool oldestFirst = false,
  }) async {
    final db = _db;
    if (db == null) return [];
    final where = <String>[];
    final args = <Object?>[];

    if (filter.feedId != null) {
      where.add('feed_source_id = ?');
      args.add(filter.feedId);
    } else if (filter.feedIds != null) {
      if (filter.feedIds!.isEmpty) return [];
      where.add('feed_source_id IN (${List.filled(filter.feedIds!.length, '?').join(',')})');
      args.addAll(filter.feedIds!);
    }
    if (filter.starred != null) {
      where.add('is_starred = ?');
      args.add(filter.starred! ? 1 : 0);
    }
    if (filter.unread != null) {
      where.add('is_read = ?');
      args.add(filter.unread! ? 0 : 1);
    }
    final keyword = filter.keyword?.trim() ?? '';
    if (keyword.isNotEmpty) {
      where.add(
          "(title LIKE ? ESCAPE '\\' OR summary LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\')");
      final like = '%${escapeLike(keyword)}%';
      args.addAll([like, like, like]);
    }
    if (beforeSortAt != null && beforeId != null) {
      where.add(oldestFirst
          ? '(sort_at > ? OR (sort_at = ? AND id > ?))'
          : '(sort_at < ? OR (sort_at = ? AND id < ?))');
      args.addAll([beforeSortAt, beforeSortAt, beforeId]);
    }

    final sql = StringBuffer('SELECT $listColumns FROM articles');
    if (where.isNotEmpty) sql.write(' WHERE ${where.join(' AND ')}');
    sql.write(oldestFirst ? ' ORDER BY sort_at ASC, id ASC' : ' ORDER BY sort_at DESC, id DESC');
    sql.write(' LIMIT ?');
    args.add(limit);

    final rows = await db.rawQuery(sql.toString(), args);
    return rows.map(RssArticle.fromMap).toList();
  }

  Future<RssArticle?> article(int id) async {
    final db = _db;
    if (db == null) return null;
    final rows = await db.query('articles', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return RssArticle.fromMap(rows.first);
  }

  Future<bool> hasArticle(int feedId, String guid) async {
    final db = _db;
    if (db == null) return false;
    final rows = await db.rawQuery(
      'SELECT 1 FROM articles WHERE feed_source_id = ? AND guid = ? LIMIT 1',
      [feedId, guid],
    );
    return rows.isNotEmpty;
  }

  /// 按 (feed_source_id, guid) 去重写入，同时维护订阅源未读计数。
  /// 返回 true 表示确实是新文章。
  Future<bool> insertArticle(RssArticle article) async {
    final db = _db;
    if (db == null || article.feedId == 0) return false;
    final map = article.toMap();
    final id = await db.insert('articles', map,
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id == 0) return false;
    if (!article.isRead) {
      await db.rawUpdate(
        'UPDATE feed_sources SET unread_count = unread_count + 1 WHERE id = ?',
        [article.feedId],
      );
    }
    return true;
  }

  Future<void> markRead(int articleId, {bool read = true}) async {
    final db = _db;
    if (db == null) return;
    final rows = await db.query('articles',
        where: 'id = ?', whereArgs: [articleId], limit: 1);
    if (rows.isEmpty) return;
    final current = asBool(rows.first['is_read']);
    if (current == read) return;
    await db.update('articles', {'is_read': read ? 1 : 0},
        where: 'id = ?', whereArgs: [articleId]);
    await db.rawUpdate(
      'UPDATE feed_sources SET unread_count = MAX(0, unread_count ${read ? '- 1' : '+ 1'}) WHERE id = ?',
      [rows.first['feed_source_id']],
    );
  }

  Future<void> markFeedRead(int feedId) async {
    final db = _db;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE articles SET is_read = 1 WHERE feed_source_id = ? AND is_read = 0',
        [feedId],
      );
      await txn.rawUpdate(
        'UPDATE feed_sources SET unread_count = 0 WHERE id = ?',
        [feedId],
      );
    });
  }

  Future<void> setStarred(int articleId, {required bool starred}) async {
    final db = _db;
    if (db == null) return;
    await db.update('articles', {'is_starred': starred ? 1 : 0},
        where: 'id = ?', whereArgs: [articleId]);
  }

  Future<void> deleteArticle(int articleId) async {
    final db = _db;
    if (db == null) return;
    final rows = await db.query('articles',
        where: 'id = ?', whereArgs: [articleId], limit: 1);
    if (rows.isEmpty) return;
    await db.delete('articles', where: 'id = ?', whereArgs: [articleId]);
    if (!asBool(rows.first['is_read'])) {
      await db.rawUpdate(
        'UPDATE feed_sources SET unread_count = MAX(0, unread_count - 1) WHERE id = ?',
        [rows.first['feed_source_id']],
      );
    }
  }

  Future<void> clearFeedArticles(int feedId) async {
    final db = _db;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete('articles',
          where: 'feed_source_id = ?', whereArgs: [feedId]);
      await txn.rawUpdate(
          'UPDATE feed_sources SET unread_count = 0 WHERE id = ?', [feedId]);
    });
  }

  /// 清理历史文章，[before] 为 null 表示全部清空
  Future<int> clearHistory({int? feedId, DateTime? before}) async {
    final db = _db;
    if (db == null) return 0;
    final where = <String>[];
    final args = <Object?>[];
    if (feedId != null) {
      where.add('feed_source_id = ?');
      args.add(feedId);
    }
    if (before != null) {
      where.add('sort_at < ?');
      args.add(before.millisecondsSinceEpoch);
    }
    final clause = where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}';
    final affected = await db.rawQuery(
      'SELECT feed_source_id AS f, COUNT(*) AS c FROM articles$clause GROUP BY feed_source_id',
      args,
    );
    await db.delete('articles', where: where.isEmpty ? null : where.join(' AND '), whereArgs: args.isEmpty ? null : args);
    await db.transaction((txn) async {
      for (final row in affected) {
        await txn.rawUpdate(
          'UPDATE feed_sources SET unread_count = '
          '(SELECT COUNT(*) FROM articles WHERE feed_source_id = ? AND is_read = 0)',
          [row['f']],
        );
      }
    });
    return affected.fold<int>(0, (sum, r) => sum + asInt(r['c']));
  }

  Future<int> totalUnread() async {
    final db = _db;
    if (db == null) return 0;
    final rows = await db
        .rawQuery('SELECT COALESCE(SUM(unread_count), 0) AS n FROM feed_sources');
    return asInt(rows.isEmpty ? null : rows.first['n']);
  }

  Future<int> starredCount() async {
    final db = _db;
    if (db == null) return 0;
    final rows =
        await db.rawQuery('SELECT COUNT(*) AS n FROM articles WHERE is_starred = 1');
    return asInt(rows.isEmpty ? null : rows.first['n']);
  }

  Future<int> unreadCount(int feedId) async {
    final db = _db;
    if (db == null) return 0;
    final rows = await db
        .query('feed_sources', columns: ['unread_count'], where: 'id = ?', whereArgs: [feedId], limit: 1);
    return asInt(rows.isEmpty ? null : rows.first['unread_count']);
  }

  /// 信息流顶部统计：未读、收藏、文章总数
  Future<Map<String, int>> stats() async {
    final db = _db;
    if (db == null) return {};
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total, '
      'SUM(CASE WHEN is_read = 0 THEN 1 ELSE 0 END) AS unread, '
      'SUM(CASE WHEN is_starred = 1 THEN 1 ELSE 0 END) AS starred FROM articles',
    );
    final row = rows.isEmpty ? <String, Object?>{} : rows.first;
    return {
      'total': asInt(row['total']),
      'unread': asInt(row['unread']),
      'starred': asInt(row['starred']),
    };
  }

  Future<void> recountAllUnread() async {
    final db = _db;
    if (db == null) return;
    await db.rawUpdate(
      'UPDATE feed_sources SET unread_count = '
      '(SELECT COUNT(*) FROM articles WHERE articles.feed_source_id = feed_sources.id AND articles.is_read = 0)',
    );
  }

  // ==================== 收藏夹 ====================

  Future<List<RssFolder>> folders() async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.rawQuery('''
SELECT f.id, f.name, f.description, f.created_at,
       COUNT(DISTINCT i.source_id) AS source_count,
       COALESCE(SUM(s.unread_count), 0) AS unread_count
FROM rss_folders f
LEFT JOIN rss_folder_items i ON i.folder_id = f.id
LEFT JOIN feed_sources s ON s.id = i.source_id
GROUP BY f.id
ORDER BY f.created_at DESC, f.id DESC''');
    return rows.map(RssFolder.fromMap).toList();
  }

  Future<RssFolder?> folder(int id) async {
    final db = _db;
    if (db == null) return null;
    final rows = await db.rawQuery('''
SELECT f.id, f.name, f.description, f.created_at,
       COUNT(DISTINCT i.source_id) AS source_count,
       COALESCE(SUM(s.unread_count), 0) AS unread_count
FROM rss_folders f
LEFT JOIN rss_folder_items i ON i.folder_id = f.id
LEFT JOIN feed_sources s ON s.id = i.source_id
WHERE f.id = ?
GROUP BY f.id''', [id]);
    if (rows.isEmpty) return null;
    return RssFolder.fromMap(rows.first);
  }

  Future<int> insertFolder(RssFolder folder) {
    final db = _db;
    if (db == null) return Future.value(0);
    return db.insert('rss_folders', folder.toMap());
  }

  Future<void> updateFolder(RssFolder folder) async {
    final db = _db;
    if (db == null || folder.id == null) return;
    await db.update(
      'rss_folders',
      {'name': folder.name, 'description': folder.description},
      where: 'id = ?',
      whereArgs: [folder.id],
    );
  }

  Future<void> deleteFolder(int id) async {
    final db = _db;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete('rss_folder_items', where: 'folder_id = ?', whereArgs: [id]);
      await txn.delete('rss_folders', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<FeedSource>> folderSources(int folderId) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.rawQuery('''
SELECT s.* FROM feed_sources s
JOIN rss_folder_items i ON i.source_id = s.id
WHERE i.folder_id = ?
ORDER BY s.sort_order ASC, s.created_at DESC, s.id DESC''', [folderId]);
    return rows.map(FeedSource.fromMap).toList();
  }

  Future<void> addSourceToFolder(int folderId, int sourceId) async {
    final db = _db;
    if (db == null) return;
    await db.rawInsert(
      'INSERT OR IGNORE INTO rss_folder_items (folder_id, source_id, created_at) VALUES (?, ?, ?)',
      [folderId, sourceId, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> removeSourceFromFolder(int folderId, int sourceId) async {
    final db = _db;
    if (db == null) return;
    await db.delete('rss_folder_items',
        where: 'folder_id = ? AND source_id = ?', whereArgs: [folderId, sourceId]);
  }

  Future<List<RssFolder>> foldersOfSource(int sourceId) async {
    final db = _db;
    if (db == null) return [];
    final rows = await db.rawQuery('''
SELECT f.* FROM rss_folders f
JOIN rss_folder_items i ON i.folder_id = f.id
WHERE i.source_id = ?
ORDER BY f.name COLLATE NOCASE''', [sourceId]);
    return rows.map(RssFolder.fromMap).toList();
  }
}

/// LIKE 通配符转义，避免用户输入 % 或 _ 时命中全部记录。
String escapeLike(String input) =>
    input.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
