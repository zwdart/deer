import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/rss_models.dart';
import '../../state/rss_controller.dart';
import '../adaptive.dart';
import '../theme.dart';
import 'dialogs.dart';

enum RssFeedAction { sync, readAll, edit, organize, pause, clear, delete }

enum RssFolderAction { rename, members, delete }

enum RssArticleAction { star, unread, original, copy, share, delete }

enum RssMoreAction {
  newFolder,
  importOpml,
  importCsv,
  exportOpml,
  exportCsv,
  markAllRead,
  clearHistory,
  backup,
  settings,
}

/// 桌面用对话框、移动端用底部抽屉，承载资讯模块的二级表单。
Future<T?> showRssSheet<T>({
  required BuildContext context,
  String? title,
  required Widget child,
}) {
  if (AppPlatform.isDesktop) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null) ...[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Flexible(child: SingleChildScrollView(child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final viewInsets = MediaQuery.of(sheetContext).viewInsets.bottom;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.86,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null) ...[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Flexible(child: SingleChildScrollView(child: child)),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

// ==================== 添加订阅 ====================

Future<String?> showAddFeedSheet(BuildContext context, RssController rss) async {
  final title = await showRssSheet<String>(
    context: context,
    title: tr('添加订阅源'),
    child: _AddFeedView(rss: rss),
  );
  if (title != null && context.mounted) {
    showAppSnack(context, trf('已添加「%s」', [title]));
  }
  return title;
}

class _AddFeedView extends StatefulWidget {
  final RssController rss;

  const _AddFeedView({required this.rss});

  @override
  State<_AddFeedView> createState() => _AddFeedViewState();
}

class _AddFeedViewState extends State<_AddFeedView> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _title = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit(String url, String name) async {
    if (_busy) return;
    final value = url.trim();
    if (value.isEmpty) return;
    setState(() => _busy = true);
    final feed = await widget.rss.addFeed(value, title: name.trim());
    if (!mounted) return;
    if (feed == null) {
      setState(() => _busy = false);
      final message = widget.rss.error ?? tr('添加失败，请检查地址');
      widget.rss.clearError();
      showAppSnack(context, message);
      return;
    }
    Navigator.pop(context, feed.title);
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _url,
          autofocus: true,
          keyboardType: TextInputType.url,
          minLines: 1,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: tr('RSS 地址'),
            hintText: 'https://example.com/feed.xml',
            hintStyle: TextStyle(color: c.faint),
          ),
          onSubmitted: (value) => _submit(value, _title.text),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _title,
          decoration: InputDecoration(labelText: tr('名称（可选）')),
          onSubmitted: (value) => _submit(_url.text, value),
        ),
        const SizedBox(height: 16),
        Text(
          tr('或从推荐列表选择'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in RssController.presets)
              ActionChip(
                label: Text(preset.$1),
                onPressed: _busy
                    ? null
                    : () {
                        _url.text = preset.$2;
                        _title.text = preset.$1;
                        _submit(preset.$2, preset.$1);
                      },
              ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : () => _submit(_url.text, _title.text),
          icon: _busy
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(_busy ? tr('正在抓取') : tr('添加并订阅')),
        ),
      ],
    );
  }
}

// ==================== 订阅源 ====================

Future<void> showFeedMenu(
  BuildContext context,
  RssController rss,
  FeedSource feed,
) async {
  final id = feed.id;
  if (id == null) return;
  final action = await showAdaptiveActionSheet<RssFeedAction>(
    context,
    title: feed.title,
    message: feed.hostName,
    actions: [
      AdaptiveSheetAction(
        value: RssFeedAction.sync,
        label: tr('立即同步'),
        icon: Icons.refresh,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.readAll,
        label: tr('全部标记已读'),
        icon: Icons.done_all,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.organize,
        label: tr('加入收藏夹'),
        icon: Icons.folder_outlined,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.edit,
        label: tr('编辑订阅源'),
        icon: Icons.edit_outlined,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.pause,
        label: feed.syncEnabled ? tr('暂停同步') : tr('恢复同步'),
        icon: feed.syncEnabled ? Icons.pause_circle_outline : Icons.play_circle_outline,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.clear,
        label: tr('清空文章'),
        icon: Icons.cleaning_services_outlined,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.delete,
        label: tr('取消订阅'),
        icon: Icons.delete_outline,
        destructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case RssFeedAction.sync:
      await rss.syncOne(id);
    case RssFeedAction.readAll:
      await rss.markFeedRead(id);
    case RssFeedAction.edit:
      await showRssSheet<void>(
        context: context,
        title: tr('编辑订阅源'),
        child: _FeedEditorView(rss: rss, feed: feed),
      );
    case RssFeedAction.organize:
      await showRssSheet<void>(
        context: context,
        title: trf('「%s」所在收藏夹', [feed.title]),
        child: _FeedFoldersView(rss: rss, feed: feed),
      );
    case RssFeedAction.pause:
      await rss.setFeedSyncEnabled(feed, !feed.syncEnabled);
    case RssFeedAction.clear:
      final ok = await confirmAction(
        context,
        title: tr('清空文章'),
        message: trf('要清空「%s」的本地文章吗？下次同步会重新抓取。', [feed.title]),
      );
      if (ok) await rss.clearFeedArticles(id);
    case RssFeedAction.delete:
      final ok = await confirmAction(
        context,
        title: tr('取消订阅'),
        message: trf('移除「%s」及其本地文章？', [feed.title]),
        destructive: true,
      );
      if (ok) {
        await rss.deleteFeed(id);
        if (context.mounted) showAppSnack(context, tr('已取消订阅'));
      }
  }
}

class _FeedEditorView extends StatefulWidget {
  final RssController rss;
  final FeedSource feed;

  const _FeedEditorView({required this.rss, required this.feed});

  @override
  State<_FeedEditorView> createState() => _FeedEditorViewState();
}

class _FeedEditorViewState extends State<_FeedEditorView> {
  late final TextEditingController _title =
      TextEditingController(text: widget.feed.title);
  late final TextEditingController _url =
      TextEditingController(text: widget.feed.url);
  late final TextEditingController _site =
      TextEditingController(text: widget.feed.siteUrl);
  late String _type = widget.feed.feedType;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    _site.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final feed = widget.feed;
    final name = _title.text.trim();
    final link = _url.text.trim();
    if (name.isNotEmpty) feed.title = name;
    if (link.isNotEmpty) feed.url = link;
    feed.siteUrl = _site.text.trim();
    feed.feedType = _type;
    await widget.rss.updateFeed(feed);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    const options = <String, String>{
      'rss2': 'RSS 2.0',
      'rss1': 'RSS 1.0',
      'atom': 'Atom',
      'json': 'JSON Feed',
    };
    final error = widget.feed.lastSyncError ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _title,
          decoration: InputDecoration(labelText: tr('名称')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          minLines: 1,
          maxLines: 2,
          decoration: InputDecoration(labelText: tr('订阅地址')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _site,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: tr('站点地址（可选）')),
        ),
        const SizedBox(height: 14),
        Text(
          tr('格式'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in options.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _type == entry.key,
                onSelected: (_) => setState(() => _type = entry.key),
              ),
          ],
        ),
        if (error.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '${tr('上次同步失败')}：$error',
            style: TextStyle(fontSize: 12, color: c.danger, height: 1.4),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(onPressed: _save, child: Text(tr('保存'))),
      ],
    );
  }
}

/// 勾选一个订阅源归属的收藏夹。
class _FeedFoldersView extends StatefulWidget {
  final RssController rss;
  final FeedSource feed;

  const _FeedFoldersView({required this.rss, required this.feed});

  @override
  State<_FeedFoldersView> createState() => _FeedFoldersViewState();
}

class _FeedFoldersViewState extends State<_FeedFoldersView> {
  Set<int> _selected = {};
  Set<int> _initial = {};
  List<RssFolder> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.feed.id;
    if (id != null) {
      final members = await widget.rss.foldersOfFeed(id);
      _initial = members.map((f) => f.id!).toSet();
      _selected = {..._initial};
    }
    if (!mounted) return;
    setState(() {
      _folders = widget.rss.folders;
      _loading = false;
    });
  }

  Future<void> _createFolder() async {
    final name = await promptText(
      context,
      title: tr('新建收藏夹'),
      label: tr('名称'),
    );
    if (name == null || name.isEmpty) return;
    final folder = await widget.rss.createFolder(name);
    final folderId = folder?.id;
    if (folderId == null || !mounted) return;
    setState(() {
      _folders = widget.rss.folders;
      _selected = {..._selected, folderId};
    });
  }

  Future<void> _save() async {
    final feedId = widget.feed.id;
    if (feedId == null) return;
    for (final folder in _folders) {
      final folderId = folder.id;
      if (folderId == null) continue;
      final want = _selected.contains(folderId);
      final had = _initial.contains(folderId);
      if (want && !had) {
        await widget.rss.addFeedToFolder(feedId, folderId);
      } else if (!want && had) {
        await widget.rss.removeFeedFromFolder(feedId, folderId);
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    if (_loading) return const SizedBox(height: 60);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_folders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              tr('还没有收藏夹，先创建一个来归类订阅源。'),
              style: TextStyle(fontSize: 13, color: c.muted, height: 1.4),
            ),
          )
        else
          for (final folder in _folders)
            CheckboxListTile(
              value: _selected.contains(folder.id),
              onChanged: (value) => setState(() {
                final id = folder.id;
                if (id == null) return;
                if (value ?? false) {
                  _selected = {..._selected, id};
                } else {
                  _selected = {..._selected}..remove(id);
                }
              }),
              title: Text(folder.name),
              subtitle: Text(
                trf('%d 个订阅', [folder.sourceCount]),
                style: TextStyle(fontSize: 11.5, color: c.faint),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _createFolder,
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: Text(tr('新建收藏夹')),
        ),
        const SizedBox(height: 14),
        FilledButton(onPressed: _save, child: Text(tr('保存'))),
      ],
    );
  }
}

// ==================== 收藏夹 ====================

Future<void> showFolderMenu(
  BuildContext context,
  RssController rss,
  RssFolder folder,
) async {
  final id = folder.id;
  if (id == null) return;
  final action = await showAdaptiveActionSheet<RssFolderAction>(
    context,
    title: folder.name,
    actions: [
      AdaptiveSheetAction(
        value: RssFolderAction.members,
        label: tr('管理成员'),
        icon: Icons.group_outlined,
      ),
      AdaptiveSheetAction(
        value: RssFolderAction.rename,
        label: tr('重命名'),
        icon: Icons.edit_outlined,
      ),
      AdaptiveSheetAction(
        value: RssFolderAction.delete,
        label: tr('删除收藏夹'),
        icon: Icons.delete_outline,
        destructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case RssFolderAction.members:
      await showRssSheet<void>(
        context: context,
        title: trf('管理「%s」', [folder.name]),
        child: _FolderMembersView(rss: rss, folder: folder),
      );
    case RssFolderAction.rename:
      final name = await promptText(
        context,
        title: tr('重命名收藏夹'),
        label: tr('名称'),
        initial: folder.name,
      );
      if (name != null && name.isNotEmpty) {
        await rss.renameFolder(id, name, folder.description);
      }
    case RssFolderAction.delete:
      final ok = await confirmAction(
        context,
        title: tr('删除收藏夹'),
        message: trf('删除「%s」不会移除其中的订阅源。', [folder.name]),
        destructive: true,
      );
      if (ok) await rss.deleteFolder(id);
  }
}

class _FolderMembersView extends StatefulWidget {
  final RssController rss;
  final RssFolder folder;

  const _FolderMembersView({required this.rss, required this.folder});

  @override
  State<_FolderMembersView> createState() => _FolderMembersViewState();
}

class _FolderMembersViewState extends State<_FolderMembersView> {
  Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final members = await widget.rss.folderSources(widget.folder.id!);
    if (!mounted) return;
    setState(() => _selected = members.map((s) => s.id!).toSet());
  }

  Future<void> _save() async {
    await widget.rss.setFolderMembers(widget.folder.id!, _selected);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final feeds = widget.rss.feeds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (feeds.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              tr('还没有订阅源可以加入。'),
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
          )
        else
          for (final feed in feeds)
            CheckboxListTile(
              value: _selected.contains(feed.id),
              onChanged: (value) => setState(() {
                final id = feed.id;
                if (id == null) return;
                if (value ?? false) {
                  _selected = {..._selected, id};
                } else {
                  _selected = {..._selected}..remove(id);
                }
              }),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(feed.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                feed.hostName,
                style: TextStyle(fontSize: 11.5, color: c.faint),
              ),
            ),
        const SizedBox(height: 14),
        FilledButton(onPressed: _save, child: Text(tr('保存'))),
      ],
    );
  }
}

// ==================== 文章 ====================

/// 返回执行过的动作，详情页可据此决定是否退出。
Future<RssArticleAction?> showArticleMenu(
  BuildContext context,
  RssController rss,
  RssArticle article,
) async {
  final action = await showAdaptiveActionSheet<RssArticleAction>(
    context,
    title: article.title,
    actions: [
      AdaptiveSheetAction(
        value: RssArticleAction.star,
        label: article.isStarred ? tr('取消收藏') : tr('收藏'),
        icon: article.isStarred ? Icons.star : Icons.star_border,
      ),
      AdaptiveSheetAction(
        value: RssArticleAction.unread,
        label: tr('标记为未读'),
        icon: Icons.mark_email_unread_outlined,
      ),
      AdaptiveSheetAction(
        value: RssArticleAction.copy,
        label: tr('复制链接'),
        icon: Icons.copy,
      ),
      AdaptiveSheetAction(
        value: RssArticleAction.share,
        label: tr('分享'),
        icon: Icons.share_outlined,
      ),
      AdaptiveSheetAction(
        value: RssArticleAction.original,
        label: tr('在浏览器打开'),
        icon: Icons.open_in_new,
      ),
      AdaptiveSheetAction(
        value: RssArticleAction.delete,
        label: tr('删除'),
        icon: Icons.delete_outline,
        destructive: true,
      ),
    ],
  );
  if (action == null) return null;
  if (!context.mounted) return action;
  switch (action) {
    case RssArticleAction.star:
      await rss.toggleStar(article);
    case RssArticleAction.unread:
      await rss.setRead(article, read: false);
    case RssArticleAction.copy:
      await Clipboard.setData(
        ClipboardData(text: article.link.isEmpty ? article.title : article.link),
      );
    case RssArticleAction.share:
      await SharePlus.instance.share(
        ShareParams(
          text: article.link.isEmpty
              ? article.title
              : '${article.title}\n${article.link}',
        ),
      );
    case RssArticleAction.original:
      await openInBrowser(context, article.link);
    case RssArticleAction.delete:
      final ok = await confirmAction(
        context,
        title: tr('删除文章'),
        message: tr('删除后需要从订阅源重新抓取才会回来。'),
        destructive: true,
      );
      if (ok) await rss.deleteArticle(article);
  }
  return action;
}

Future<void> openInBrowser(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    if (context.mounted) showAppSnack(context, tr('没有可用的原文链接'));
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

// ==================== 更多菜单 ====================

Future<RssMoreAction?> showRssMoreMenu(
  BuildContext context,
  RssController rss,
) async {
  final action = await showAdaptiveActionSheet<RssMoreAction>(
    context,
    title: tr('资讯工具'),
    actions: [
      AdaptiveSheetAction(
        value: RssMoreAction.newFolder,
        label: tr('新建收藏夹'),
        icon: Icons.create_new_folder_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.importOpml,
        label: tr('导入 OPML'),
        icon: Icons.file_download_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.importCsv,
        label: tr('导入 CSV'),
        icon: Icons.file_download_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.exportOpml,
        label: tr('导出 OPML'),
        icon: Icons.file_upload_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.exportCsv,
        label: tr('导出 CSV'),
        icon: Icons.file_upload_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.markAllRead,
        label: tr('全部标记已读'),
        icon: Icons.done_all,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.clearHistory,
        label: tr('清理历史文章'),
        icon: Icons.cleaning_services_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.backup,
        label: tr('立即备份订阅'),
        icon: Icons.backup_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.settings,
        label: tr('资讯设置'),
        icon: Icons.tune,
      ),
    ],
  );
  if (action == null) return null;
  if (!context.mounted) return action;
  switch (action) {
    case RssMoreAction.newFolder:
      final name = await promptText(context, title: tr('新建收藏夹'), label: tr('名称'));
      if (name != null && name.isNotEmpty) await rss.createFolder(name);
    case RssMoreAction.importOpml:
      await _importFile(context, rss, false);
    case RssMoreAction.importCsv:
      await _importFile(context, rss, true);
    case RssMoreAction.exportOpml:
      final opml = await rss.exportOpml();
      if (!context.mounted) break;
      await _exportFile(context, rss, opml, 'dchat_rss.opml');
    case RssMoreAction.exportCsv:
      final csvText = await rss.exportCsv();
      if (!context.mounted) break;
      await _exportFile(context, rss, csvText, 'dchat_rss.csv');
    case RssMoreAction.markAllRead:
      final ok = await confirmAction(
        context,
        title: tr('全部标记已读'),
        message: trf('把 %d 条未读全部标为已读？', [rss.totalUnread]),
      );
      if (ok) await rss.markAllRead();
    case RssMoreAction.clearHistory:
      await _clearHistory(context, rss);
    case RssMoreAction.backup:
      await rss.backupNow();
      if (context.mounted) showAppSnack(context, tr('备份已写入本地目录'));
    case RssMoreAction.settings:
      break;
  }
  return action;
}

Future<void> _importFile(
  BuildContext context,
  RssController rss,
  bool csv,
) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: csv ? const ['csv'] : const ['opml', 'xml'],
  );
  final path = picked.isEmpty ? null : picked.first.path;
  if (path == null) return;
  String text;
  try {
    text = await File(path).readAsString();
  } catch (e) {
    if (context.mounted) showAppSnack(context, trf('读取文件失败：%s', ['$e']));
    return;
  }
  final (added, folders) =
      csv ? await rss.importCsv(text) : await rss.importOpml(text);
  if (!context.mounted) return;
  showAppSnack(context, trf('新增 %d 个订阅、%d 个收藏夹', [added, folders]));
}

Future<void> _exportFile(
  BuildContext context,
  RssController rss,
  String content,
  String filename,
) async {
  final bytes = utf8.encode(content);
  Uri? target;
  try {
    target = await FilePicker.saveFile(
      fileName: filename,
      bytes: bytes,
      mimeType: filename.endsWith('.csv') ? 'text/csv' : 'text/x-opml',
      dialogTitle: tr('导出订阅源'),
    );
  } catch (_) {
    target = null;
  }
  String saved;
  if (target == null) {
    saved = await rss.writeExport(filename, content);
  } else {
    saved = target.path;
    try {
      await File(saved).writeAsString(content);
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('写入失败：%s', ['$e']));
      return;
    }
  }
  if (context.mounted) showAppSnack(context, '${tr('已导出到')}$saved');
}

Future<void> _clearHistory(BuildContext context, RssController rss) async {
  final option = await showAdaptiveActionSheet<String>(
    context,
    title: tr('清理历史文章'),
    message: tr('只删除本地已抓取的文章，订阅关系保留。'),
    actions: [
      AdaptiveSheetAction(value: '7', label: tr('保留最近 7 天')),
      AdaptiveSheetAction(value: '30', label: tr('保留最近 30 天')),
      AdaptiveSheetAction(value: 'all', label: tr('全部清空'), destructive: true),
    ],
  );
  if (option == null) return;
  if (option != 'all') {
    final days = int.parse(option);
    final removed = await rss.clearHistory(
      before: DateTime.now().subtract(Duration(days: days)),
    );
    if (context.mounted) showAppSnack(context, trf('已清理 %d 条', [removed]));
    return;
  }
  if (!context.mounted) return;
  final ok = await confirmAction(
    context,
    title: tr('全部清空'),
    message: tr('会删除所有本地文章，下次同步会重新抓取。'),
    destructive: true,
  );
  if (!ok) return;
  final removed = await rss.clearHistory();
  if (context.mounted) showAppSnack(context, trf('已清理 %d 条', [removed]));
}
