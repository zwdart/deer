import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/rss_models.dart';
import '../../state/rss_controller.dart';
import '../adaptive.dart';
import '../dialogs/dialogs.dart';
import '../dialogs/rss_dialogs.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/rss_cards.dart';

/// 资讯标签页：信息流 + 订阅卡片两套视图。
/// 主按钮只保留搜索、刷新和添加订阅，其余操作收进右上角弹层。
class RssScreen extends StatefulWidget {
  const RssScreen({super.key});

  @override
  State<RssScreen> createState() => _RssScreenState();
}

class _RssScreenState extends State<RssScreen> {
  final ScrollController _scroller = ScrollController();
  final TextEditingController _search = TextEditingController();
  bool _showFeeds = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scroller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroller
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_showFeeds || !_scroller.hasClients) return;
    final position = _scroller.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      context.read<RssController>().loadMore();
    }
  }

  void _exitSearch(RssController rss) {
    setState(() => _searching = false);
    _search.clear();
    rss.openScope(RssScope.all);
  }

  Future<void> _openArticle(RssController rss, RssArticle article) async {
    if (article.id == null) return;
    if (rss.settings.markReadOnOpen && !article.isRead) {
      await rss.setRead(article, read: true);
    }
    if (!mounted) return;
    await openRssReader(context, article);
  }

  Future<void> _more(RssController rss) async {
    final action = await showRssMoreMenu(context, rss);
    if (action == RssMoreAction.settings && mounted) {
      openSettingsScreen(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssController>();
    final c = appColors(context);
    final inSubScope = rss.scope == RssScope.feed ||
        rss.scope == RssScope.folder ||
        rss.scope == RssScope.search;
    final scopeChipsVisible = !inSubScope && !_showFeeds && !_searching;

    return Scaffold(
      appBar: DchatAppBar(
        automaticallyImplyLeading: false,
        leading: inSubScope
            ? IconButton(
                tooltip: tr('ui.back_2'),
                onPressed: () =>
                    _searching ? _exitSearch(rss) : rss.openScope(RssScope.all),
                icon: Icon(adaptiveBackIcon, size: 21),
              )
            : null,
        title: Text(
          inSubScope ? rss.scopeTitle : tr('rss.news'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconAction(
            icon: _searching ? Icons.close : Icons.search,
            tooltip: _searching ? tr('system.close_search') : tr('rss.search_saved_articles'),
            onPressed: () => _searching ? _exitSearch(rss) : setState(() => _searching = true),
          ),
          IconAction(
            icon: rss.syncing ? Icons.sync : Icons.refresh,
            tooltip: tr('rss.sync_all_feeds'),
            onPressed: rss.syncing ? null : () => rss.syncAll(),
          ),
          IconAction(
            icon: Icons.more_horiz,
            tooltip: tr('ui.more'),
            onPressed: () => _more(rss),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            54 + (_searching ? 58 : 0) + (scopeChipsVisible ? 44 : 0),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: tr('ui.search_titles_and_text'),
                        prefixIcon: const Icon(Icons.search, size: 19),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => rss.openScope(RssScope.all),
                        ),
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isEmpty) return;
                        setState(() => _showFeeds = false);
                        rss.search(value);
                      },
                    ),
                  ),
                Row(
                  children: [
                    AdaptiveSegmentedControl(
                      segments: [
                        AdaptiveSegment('stream', tr('rss.stream')),
                        AdaptiveSegment('feeds', tr('rss.feeds')),
                      ],
                      selected: _showFeeds ? 'feeds' : 'stream',
                      onChanged: (value) =>
                          setState(() => _showFeeds = value == 'feeds'),
                    ),
                    const Spacer(),
                    Text(
                      _showFeeds
                          ? trf('rss.arg_0__feeds', [rss.feeds.length])
                          : trf('ui.arg_0__unread', [rss.totalUnread]),
                      style: TextStyle(fontSize: 11.5, color: c.faint),
                    ),
                  ],
                ),
                if (scopeChipsVisible) ...[
                  const SizedBox(height: 10),
                  ScopeChips(
                    scope: rss.scope,
                    totalUnread: rss.totalUnread,
                    starredTotal: rss.starredTotal,
                    onChanged: (scope) => rss.openScope(scope),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: _ConstrainedColumn(child: _showFeeds ? _buildFeeds(rss) : _buildStream(rss)),
      floatingActionButton: _showFeeds || rss.feeds.isEmpty
          ? FloatingActionButton.extended(
              heroTag: 'rss-add-feed',
              onPressed: () => showAddFeedSheet(context, rss),
              icon: const Icon(Icons.add),
              label: Text(tr('rss.add_feed')),
            )
          : null,
    );
  }

  Widget _buildStream(RssController rss) {
    if (rss.error != null) {
      final message = rss.error!;
      rss.clearError();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showAppSnack(context, message);
      });
    }
    if (rss.articles.isEmpty) {
      return rss.loading
          ? const Center(child: CircularProgressIndicator())
          : _EmptyByScope(rss: rss);
    }
    return RefreshIndicator(
      onRefresh: () => rss.syncAll(),
      child: CustomScrollView(
        controller: _scroller,
        slivers: [
          const SliverPadding(padding: EdgeInsets.only(top: 10)),
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            sliver: SliverToBoxAdapter(child: SyncBanner()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final article = rss.articles[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ArticleFlowCard(
                      article: article,
                      feed: _feedOf(rss, article),
                      showImage: rss.settings.showImages,
                      onTap: () => _openArticle(rss, article),
                      onLongPress: () => showArticleMenu(context, rss, article),
                    ),
                  );
                },
                childCount: rss.articles.length,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _streamFooter(rss: rss)),
        ],
      ),
    );
  }

  Widget _streamFooter({required RssController rss}) {
    final c = appColors(context);
    return SizedBox(
      height: 92,
      child: Center(
        child: rss.loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : (rss.hasMore
                ? TextButton(
                    onPressed: () => rss.loadMore(),
                    child: Text(tr('ui.load_more')),
                  )
                : Text(
                    tr('ui.that_s_everything'),
                    style: TextStyle(fontSize: 12, color: c.faint),
                  )),
      ),
    );
  }

  FeedSource? _feedOf(RssController rss, RssArticle article) {
    for (final feed in rss.feeds) {
      if (feed.id == article.feedId) return feed;
    }
    return null;
  }

  Widget _buildFeeds(RssController rss) {
    final c = appColors(context);
    final folders = rss.folders;
    return RefreshIndicator(
      onRefresh: () => rss.syncAll(),
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverToBoxAdapter(child: SyncBanner()),
          ),
          if (folders.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: tr('rss.folders'),
                trailing: TextButton.icon(
                  onPressed: () => _newFolder(rss),
                  icon: const Icon(Icons.add, size: 17),
                  label: Text(tr('ui.new')),
                ),
              ),
            ),
            _cardsGrid(
              count: folders.length,
              builder: (context, index) => FolderCard(
                folder: folders[index],
                onTap: () => rss.openScope(RssScope.folder, folderId: folders[index].id),
                onMenu: () => showFolderMenu(context, rss, folders[index]),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: tr('rss.feed'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    trf('ui.arg_0__items', [rss.feeds.length]),
                    style: TextStyle(fontSize: 11.5, color: c.faint),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () => rss.syncAll(),
                    child: Text(tr('rss.sync_all')),
                  ),
                ],
              ),
            ),
          ),
          if (rss.feeds.isEmpty)
            const SliverToBoxAdapter(
              child: SizedBox(height: 120),
            )
          else
            _cardsGrid(
              count: rss.feeds.length + 1,
              builder: (context, index) {
                if (index == rss.feeds.length) return const _AddFeedTile();
                final feed = rss.feeds[index];
                return SubscriptionCard(
                  feed: feed,
                  onTap: () => rss.openScope(RssScope.feed, feedId: feed.id),
                  onMenu: () => showFeedMenu(context, rss, feed),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  Future<void> _newFolder(RssController rss) async {
    final name = await promptText(context, title: tr('rss.new_folder'), label: tr('ui.name'));
    if (name != null && name.isNotEmpty) await rss.createFolder(name);
  }

  Widget _cardsGrid({
    required int count,
    required Widget Function(BuildContext context, int index) builder,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent:
              MediaQuery.sizeOf(context).width < 480 ? 400 : 300,
          mainAxisExtent: 116,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(builder, childCount: count),
      ),
    );
  }
}

/// 桌面端限制列宽，移动端铺满。
class _ConstrainedColumn extends StatelessWidget {
  final Widget child;

  const _ConstrainedColumn({required this.child});

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.isDesktop) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: child,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 6),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class _AddFeedTile extends StatelessWidget {
  const _AddFeedTile();

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final rss = context.read<RssController>();
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showAddFeedSheet(context, rss),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, size: 22, color: c.accent),
              const SizedBox(height: 8),
              Text(
                tr('rss.add_a_feed'),
                style: TextStyle(fontSize: 12.5, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyByScope extends StatelessWidget {
  final RssController rss;

  const _EmptyByScope({required this.rss});

  @override
  Widget build(BuildContext context) {
    if (rss.feeds.isEmpty) {
      return EmptyState(
        icon: Icons.rss_feed_outlined,
        title: tr('rss.no_feeds_yet'),
        message: tr('rss.add_an_rss_or_atom_url_everything_stays_on_this_device'),
        action: FilledButton.icon(
          onPressed: () => showAddFeedSheet(context, rss),
          icon: const Icon(Icons.add),
          label: Text(tr('rss.add_a_feed')),
        ),
      );
    }
    switch (rss.scope) {
      case RssScope.unread:
        return EmptyState(
          icon: Icons.done_all,
          title: tr('ui.all_read'),
          message: tr('rss.sync_again_to_pick_up_new_articles'),
          action: OutlinedButton.icon(
            onPressed: () => rss.syncAll(),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(tr('rss.sync_now')),
          ),
        );
      case RssScope.starred:
        return EmptyState(
          icon: Icons.star_border,
          title: tr('rss.nothing_starred'),
          message: tr('rss.long_press_an_article_and_choose_star_to_keep_it_here'),
        );
      case RssScope.search:
        return EmptyState(
          icon: Icons.search_off,
          title: tr('ui.nothing_found'),
          message: tr('rss.search_covers_articles_already_on_this_device'),
        );
      case RssScope.feed:
      case RssScope.folder:
        return EmptyState(
          icon: Icons.article_outlined,
          title: tr('rss.nothing_here_yet'),
          message: tr('ui.pull_to_refresh_or_use_the_refresh_button_above'),
          action: FilledButton.icon(
            onPressed: () => rss.syncAll(),
            icon: const Icon(Icons.refresh),
            label: Text(tr('rss.sync_now')),
          ),
        );
      case RssScope.all:
        return EmptyState(
          icon: Icons.article_outlined,
          title: tr('rss.no_articles_yet'),
          message: tr('rss.use_refresh_above_or_long_press_a_feed_card_to_sync_it_alone'),
          action: FilledButton.icon(
            onPressed: () => rss.syncAll(),
            icon: const Icon(Icons.refresh),
            label: Text(tr('rss.sync_now')),
          ),
        );
    }
  }
}
