import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/rss_models.dart';
import '../../state/rss_controller.dart';
import '../adaptive.dart';
import '../dialogs/rss_dialogs.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/rss_cards.dart';
import '../widgets/rss_html_body.dart';

/// 新闻客户端风格的文章详情：封面、标题、出处、正文列、底部操作条。
class RssReaderScreen extends StatefulWidget {
  final RssArticle article;

  const RssReaderScreen({super.key, required this.article});

  @override
  State<RssReaderScreen> createState() => _RssReaderScreenState();
}

class _RssReaderScreenState extends State<RssReaderScreen> {
  final ScrollController _scroller = ScrollController();
  RssArticle? _full;

  /// 阅读进度用 ValueNotifier 单独驱动那根 2px 进度条。
  /// 之前用 setState，每滚动 1% 就重建整个页面（含全文 HTML 重新解析排版），
  /// 长文下滚动会明显掉帧。
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _scroller.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroller
      ..removeListener(_onScroll)
      ..dispose();
    _progress.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroller.hasClients) return;
    final max = _scroller.position.maxScrollExtent;
    final next = max <= 0 ? 1.0 : (_scroller.position.pixels / max).clamp(0.0, 1.0);
    if ((next - _progress.value).abs() < 0.01) return;
    _progress.value = next;
  }

  Future<void> _load() async {
    final rss = context.read<RssController>();
    final id = widget.article.id;
    if (id == null) return;
    final fresh = await rss.article(id);
    if (!mounted) return;
    setState(() => _full = fresh);
    if (fresh != null && !fresh.isRead) {
      await rss.setRead(fresh, read: true);
    }
  }

  Future<void> _openFeed(RssController rss) async {
    final feed = _feed(rss);
    if (feed?.id == null) return;
    Navigator.pop(context);
    await rss.openScope(RssScope.feed, feedId: feed!.id);
  }

  FeedSource? _feed(RssController rss) {
    for (final feed in rss.feeds) {
      if (feed.id == widget.article.feedId) return feed;
    }
    return null;
  }

  /// 收藏状态以 controller 里的文章列表为准：setStarred 用 copyWith 生成新对象，
  /// [_full] 持有的还是旧实例，直接读会显示过期状态。
  bool _starred(RssController rss) {
    final article = _full ?? widget.article;
    final id = article.id;
    if (id == null) return article.isStarred;
    for (final a in rss.articles) {
      if (a.id == id) return a.isStarred;
    }
    return article.isStarred;
  }

  @override
  Widget build(BuildContext context) {
    // 只订阅真正影响本页渲染的字段，不再 watch 整个 RssController。
    // 后台同步每抓完一个源都会 notifyListeners，全量 watch 会让详情页反复整页重建。
    final rss = context.read<RssController>();
    final (fontSize, lineHeight, showImages, contentWidth) =
        context.select<RssController, (int, double, bool, int)>(
      (r) => (
        r.settings.fontSize,
        r.settings.lineHeight,
        r.settings.showImages,
        r.settings.contentWidth,
      ),
    );
    final c = appColors(context);
    final article = _full ?? widget.article;
    // feed 的标题 / 站点 / 收藏状态作为触发条件；对象本身用 read 取最新值。
    final (_, feedSiteUrl, isStarred) =
        context.select<RssController, (String, String, bool)>((r) {
      final f = _feed(r);
      return (f?.title ?? '', f?.siteUrl ?? '', _starred(r));
    });
    final feed = _feed(rss);
    // 正文可能是几十万字符，只取一次，避免 build 里重复 trim 复制大字符串。
    final body = _body(article);
    final imageUrl = article.imageUrl;

    return Scaffold(
      appBar: DeerAppBar(
        toolbarHeight: 46,
        titleWidget: feed == null
            ? Text(
                tr('ui.article'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              )
            : FeedLine(feed: feed, onTap: () => _openFeed(rss)),
        actions: [
          IconAction(
            icon: isStarred ? Icons.star : Icons.star_border,
            tooltip: isStarred ? tr('rss.unstar') : tr('rss.star'),
            color: isStarred ? c.accent : null,
            onPressed: () => rss.toggleStar(article),
          ),
          IconAction(
            icon: Icons.text_format,
            tooltip: tr('ui.type_and_display'),
            onPressed: () => _showTypographySheet(context, rss),
          ),
          IconAction(
            icon: Icons.more_horiz,
            tooltip: tr('ui.more'),
            onPressed: () async {
              final action = await showArticleMenu(context, rss, article);
              if (!context.mounted) return;
              // 删除或标为未读后留在详情页没有意义，回到列表。
              if (action == RssArticleAction.delete ||
                  action == RssArticleAction.unread) {
                Navigator.pop(context);
              }
            },
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _progress,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 2,
              backgroundColor: c.border,
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                controller: _scroller,
                padding: EdgeInsets.zero,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentWidth.toDouble()),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showImages && imageUrl.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          DetailImage(
                            url: imageUrl,
                            radius: 0,
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                article.title.isEmpty ? tr('ui.untitled') : article.title,
                                style: TextStyle(
                                  fontSize: 23,
                                  height: 1.32,
                                  fontWeight: FontWeight.w700,
                                  color: c.text,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _MetaLine(article: article, feed: feed),
                              const SizedBox(height: 16),
                              if (body.trim().isEmpty)
                                Text(
                                  tr('ui.this_item_only_has_a_summary'),
                                  style: TextStyle(
                                    fontSize: fontSize - 1.0,
                                    color: c.muted,
                                    height: 1.6,
                                  ),
                                )
                              else
                                RssHtmlBody(
                                  html: body,
                                  baseUrl: article.link.isNotEmpty
                                      ? article.link
                                      : (feedSiteUrl.isEmpty ? null : feedSiteUrl),
                                  fontSize: fontSize.toDouble(),
                                  lineHeight: lineHeight,
                                  showImages: showImages,
                                ),
                            ],
                          ),
                        ),
                        if (article.link.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                            child: OutlinedButton.icon(
                              onPressed: () => openInBrowser(context, article.link),
                              icon: const Icon(Icons.open_in_new, size: 17),
                              label: Text(tr('ui.read_original')),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _body(RssArticle article) {
    if (article.content.trim().isNotEmpty) return article.content;
    return article.summary;
  }
}

class _MetaLine extends StatelessWidget {
  final RssArticle article;
  final FeedSource? feed;

  const _MetaLine({required this.article, required this.feed});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final parts = <String>[
      if (feed != null && feed!.title.isNotEmpty) feed!.title,
      if (article.author.trim().isNotEmpty) article.author.trim(),
      feedTimeLabel(article.sortAt),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final part in parts)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: c.panel,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.border),
            ),
            child: Text(
              part,
              style: TextStyle(fontSize: 11.5, color: c.muted),
            ),
          ),
      ],
    );
  }
}

Future<void> _showTypographySheet(BuildContext context, RssController rss) async {
  await showRssSheet<void>(
    context: context,
    title: tr('ui.type_and_display'),
    child: _TypographyView(rss: rss),
  );
}

class _TypographyView extends StatelessWidget {
  final RssController rss;

  const _TypographyView({required this.rss});

  @override
  Widget build(BuildContext context) {
    // 弹框是独立路由，不会跟随详情页的 watch 重建，需要自己监听设置变化。
    return ListenableBuilder(
      listenable: rss,
      builder: (context, _) {
        final settings = rss.settings;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(tr('ui.text_size'),
                    style: TextStyle(
                        fontSize: 13, color: appColors(context).muted)),
                const Spacer(),
                Text('${settings.fontSize}',
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
            Slider(
              value: settings.fontSize.toDouble(),
              min: 14,
              max: 24,
              divisions: 10,
              label: '${settings.fontSize}',
              onChanged: (value) =>
                  rss.update((s) => s.fontSize = value.round()),
            ),
            Row(
              children: [
                Text(tr('ui.line_height'),
                    style: TextStyle(
                        fontSize: 13, color: appColors(context).muted)),
                const Spacer(),
                Text(settings.lineHeight.toStringAsFixed(2),
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
            Slider(
              value: settings.lineHeight,
              min: 1.4,
              max: 2.2,
              divisions: 8,
              label: settings.lineHeight.toStringAsFixed(2),
              onChanged: (value) => rss.update((s) => s.lineHeight = value),
            ),
            SwitchListTile(
              value: settings.showImages,
              onChanged: (value) => rss.update((s) => s.showImages = value),
              title: Text(tr('image.show_images')),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: settings.markReadOnOpen,
              onChanged: (value) =>
                  rss.update((s) => s.markReadOnOpen = value),
              title: Text(tr('ui.mark_read_on_open')),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        );
      },
    );
  }
}
