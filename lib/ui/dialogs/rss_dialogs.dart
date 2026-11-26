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
    title: tr('rss.add_a_feed'),
    child: _AddFeedView(rss: rss),
  );
  if (title != null && context.mounted) {
    showAppSnack(context, trf('ui.added__arg_0', [title]));
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
      final message = widget.rss.error ?? tr('device.could_not_add_it_check_the_url');
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
            labelText: tr('rss.feed_url'),
            hintText: 'https://example.com/feed.xml',
            hintStyle: TextStyle(color: c.faint),
          ),
          onSubmitted: (value) => _submit(value, _title.text),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _title,
          decoration: InputDecoration(labelText: tr('ui.name_optional')),
          onSubmitted: (value) => _submit(_url.text, value),
        ),
        const SizedBox(height: 16),
        Text(
          tr('rss.or_pick_one_from_the_suggestions'),
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
            for (final preset in RssController.recommended)
              ActionChip(
                label: Text(preset.name),
                onPressed: _busy
                    ? null
                    : () {
                        _url.text = preset.url;
                        _title.text = preset.name;
                        _submit(preset.url, preset.name);
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
          label: Text(_busy ? tr('ui.fetching') : tr('rss.add_and_subscribe')),
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
        label: tr('rss.sync_now'),
        icon: Icons.refresh,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.readAll,
        label: tr('ui.mark_everything_read'),
        icon: Icons.done_all,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.organize,
        label: tr('rss.add_to_folder'),
        icon: Icons.folder_outlined,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.edit,
        label: tr('rss.edit_feed'),
        icon: Icons.edit_outlined,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.pause,
        label: feed.syncEnabled ? tr('rss.pause_syncing') : tr('rss.resume_syncing'),
        icon: feed.syncEnabled ? Icons.pause_circle_outline : Icons.play_circle_outline,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.clear,
        label: tr('rss.clear_articles'),
        icon: Icons.cleaning_services_outlined,
      ),
      AdaptiveSheetAction(
        value: RssFeedAction.delete,
        label: tr('rss.unsubscribe'),
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
        title: tr('rss.edit_feed'),
        child: _FeedEditorView(rss: rss, feed: feed),
      );
    case RssFeedAction.organize:
      await showRssSheet<void>(
        context: context,
        title: trf('rss.folders_with__arg_0', [feed.title]),
        child: _FeedFoldersView(rss: rss, feed: feed),
      );
    case RssFeedAction.pause:
      await rss.setFeedSyncEnabled(feed, !feed.syncEnabled);
    case RssFeedAction.clear:
      final ok = await confirmAction(
        context,
        title: tr('rss.clear_articles'),
        message: trf('rss.clear_saved_articles_from__arg_0__the_next_sync_refetches_them', [feed.title]),
      );
      if (ok) await rss.clearFeedArticles(id);
    case RssFeedAction.delete:
      final ok = await confirmAction(
        context,
        title: tr('rss.unsubscribe'),
        message: trf('rss.remove__arg_0__and_its_saved_articles', [feed.title]),
        destructive: true,
      );
      if (ok) {
        await rss.deleteFeed(id);
        if (context.mounted) showAppSnack(context, tr('rss.unsubscribed'));
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
          decoration: InputDecoration(labelText: tr('ui.name')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          minLines: 1,
          maxLines: 2,
          decoration: InputDecoration(labelText: tr('rss.feed_address')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _site,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: tr('device.site_url_optional')),
        ),
        const SizedBox(height: 14),
        Text(
          tr('ui.format'),
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
            '${tr('rss.last_sync_failed')}：$error',
            style: TextStyle(fontSize: 12, color: c.danger, height: 1.4),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(onPressed: _save, child: Text(tr('ui.save'))),
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
      title: tr('rss.new_folder'),
      label: tr('ui.name'),
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
              tr('rss.no_folders_yet_create_one_to_group_your_feeds'),
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
                trf('rss.arg_0__feeds', [folder.sourceCount]),
                style: TextStyle(fontSize: 11.5, color: c.faint),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _createFolder,
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: Text(tr('rss.new_folder')),
        ),
        const SizedBox(height: 14),
        FilledButton(onPressed: _save, child: Text(tr('ui.save'))),
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
        label: tr('chat.manage_feeds'),
        icon: Icons.group_outlined,
      ),
      AdaptiveSheetAction(
        value: RssFolderAction.rename,
        label: tr('ui.rename_2'),
        icon: Icons.edit_outlined,
      ),
      AdaptiveSheetAction(
        value: RssFolderAction.delete,
        label: tr('rss.delete_folder'),
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
        title: trf('ui.manage__arg_0', [folder.name]),
        child: _FolderMembersView(rss: rss, folder: folder),
      );
    case RssFolderAction.rename:
      final name = await promptText(
        context,
        title: tr('rss.rename_folder'),
        label: tr('ui.name'),
        initial: folder.name,
      );
      if (name != null && name.isNotEmpty) {
        await rss.renameFolder(id, name, folder.description);
      }
    case RssFolderAction.delete:
      final ok = await confirmAction(
        context,
        title: tr('rss.delete_folder'),
        message: trf('rss.removing__arg_0__keeps_its_feeds', [folder.name]),
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
              tr('rss.there_are_no_feeds_to_add_yet'),
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
        FilledButton(onPressed: _save, child: Text(tr('ui.save'))),
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
        label: article.isStarred ? tr('rss.unstar') : tr('rss.star'),
        icon: article.isStarred ? Icons.star : Icons.star_border,
      ),
      AdaptiveSheetAction(
        value: RssArticleAction.unread,
        label: tr('ui.mark_unread'),
        icon: Icons.mark_email_unread_outlined,
      ),
      AdaptiveSheetAction(
        value: RssArticleAction.copy,
        label: tr('ui.copy_link'),
        icon: Icons.copy,
      ),
      AdaptiveSheetAction(
        value: RssArticleAction.share,
        label: tr('share.share_2'),
        icon: Icons.share_outlined,
      ),
      AdaptiveSheetAction(
        value: RssArticleAction.original,
        label: tr('ui.open_in_browser_2'),
        icon: Icons.open_in_new,
      ),
      AdaptiveSheetAction(
        value: RssArticleAction.delete,
        label: tr('ui.delete'),
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
        title: tr('rss.delete_article'),
        message: tr('rss.it_only_comes_back_after_the_next_sync'),
        destructive: true,
      );
      if (ok) await rss.deleteArticle(article);
  }
  return action;
}

Future<void> openInBrowser(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    if (context.mounted) showAppSnack(context, tr('ui.no_source_link_available'));
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
    title: tr('rss.news_tools'),
    actions: [
      AdaptiveSheetAction(
        value: RssMoreAction.newFolder,
        label: tr('rss.new_folder'),
        icon: Icons.create_new_folder_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.importOpml,
        label: tr('rss.import_opml'),
        icon: Icons.file_download_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.importCsv,
        label: tr('ui.import_csv'),
        icon: Icons.file_download_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.exportOpml,
        label: tr('rss.export_opml'),
        icon: Icons.file_upload_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.exportCsv,
        label: tr('ui.export_csv'),
        icon: Icons.file_upload_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.markAllRead,
        label: tr('ui.mark_everything_read'),
        icon: Icons.done_all,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.clearHistory,
        label: tr('rss.clean_up_articles'),
        icon: Icons.cleaning_services_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.backup,
        label: tr('rss.back_up_now'),
        icon: Icons.backup_outlined,
      ),
      AdaptiveSheetAction(
        value: RssMoreAction.settings,
        label: tr('rss.news_settings'),
        icon: Icons.tune,
      ),
    ],
  );
  if (action == null) return null;
  if (!context.mounted) return action;
  switch (action) {
    case RssMoreAction.newFolder:
      final name = await promptText(context, title: tr('rss.new_folder'), label: tr('ui.name'));
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
        title: tr('ui.mark_everything_read'),
        message: trf('ui.mark__arg_0__unread_articles_as_read', [rss.totalUnread]),
      );
      if (ok) await rss.markAllRead();
    case RssMoreAction.clearHistory:
      await _clearHistory(context, rss);
    case RssMoreAction.backup:
      await rss.backupNow();
      if (context.mounted) showAppSnack(context, tr('ui.backup_written_to_your_device'));
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
    if (context.mounted) showAppSnack(context, trf('ui.could_not_read_the_file__arg_0', ['$e']));
    return;
  }
  final (added, folders) =
      csv ? await rss.importCsv(text) : await rss.importOpml(text);
  if (!context.mounted) return;
  showAppSnack(context, trf('rss.added__arg_0__feeds_and__arg_1__folders', [added, folders]));
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
      dialogTitle: tr('rss.export_feeds'),
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
      if (context.mounted) showAppSnack(context, trf('ui.could_not_write__arg_0', ['$e']));
      return;
    }
  }
  if (context.mounted) showAppSnack(context, '${tr('ui.exported_to')}$saved');
}

Future<void> _clearHistory(BuildContext context, RssController rss) async {
  final option = await showAdaptiveActionSheet<String>(
    context,
    title: tr('rss.clean_up_articles'),
    message: tr('rss.deletes_synced_articles_but_keeps_the_subscription'),
    actions: [
      AdaptiveSheetAction(value: '7', label: tr('ui.keep_the_last_7_days')),
      AdaptiveSheetAction(value: '30', label: tr('ui.keep_the_last_30_days')),
      AdaptiveSheetAction(value: 'all', label: tr('ui.clear_all'), destructive: true),
    ],
  );
  if (option == null) return;
  if (option != 'all') {
    final days = int.parse(option);
    final removed = await rss.clearHistory(
      before: DateTime.now().subtract(Duration(days: days)),
    );
    if (context.mounted) showAppSnack(context, trf('ui.removed__arg_0__articles', [removed]));
    return;
  }
  if (!context.mounted) return;
  final ok = await confirmAction(
    context,
    title: tr('ui.clear_all'),
    message: tr('rss.deletes_every_saved_article_the_next_sync_fetches_them_again'),
    destructive: true,
  );
  if (!ok) return;
  final removed = await rss.clearHistory();
  if (context.mounted) showAppSnack(context, trf('ui.removed__arg_0__articles', [removed]));
}
