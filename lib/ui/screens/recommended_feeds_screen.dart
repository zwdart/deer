import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/rss_models.dart';
import '../../rss/pubrss_client.dart';
import '../../state/rss_controller.dart';
import '../adaptive.dart';
import '../dialogs/dialogs.dart';
import '../theme.dart';

/// 「推荐」菜单：优先从服务端公共池随机拉一批 RSS/Atom 订阅源，离线时用本地精选兜底。
/// 顶部介绍信息改为 AppBar 上的「说明」按钮点击弹框，不再常驻。
class RecommendedFeedsScreen extends StatefulWidget {
  const RecommendedFeedsScreen({super.key});

  @override
  State<RecommendedFeedsScreen> createState() => _RecommendedFeedsScreenState();
}

class _RecommendedFeedsScreenState extends State<RecommendedFeedsScreen> {
  String? _category;
  final Set<String> _busy = {};

  // 状态机：loading（首次/刷新中）、loaded、error（回退本地）
  bool _loading = true;
  bool _offlineFallback = false;
  final List<RecommendedFeed> _items = [];

  // 接口可选返回的介绍文案；为 null 时 _showIntro() fallback 到本地 i18n。
  String? _introTitle;
  String? _introBody;

  static String _normalize(String url) {
    var s = url.trim().toLowerCase();
    if (s.startsWith('https://')) s = s.substring(8);
    if (s.startsWith('http://')) s = s.substring(7);
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  bool _subscribed(RssController rss, RecommendedFeed feed) {
    final target = _normalize(feed.url);
    for (final f in rss.feeds) {
      if (_normalize(f.url) == target) return true;
    }
    return false;
  }

  Future<void> _subscribe(RssController rss, RecommendedFeed feed) async {
    if (_busy.contains(feed.url) || _subscribed(rss, feed)) return;
    setState(() => _busy.add(feed.url));
    final result = await rss.addFeed(feed.url, title: feed.name);
    if (!mounted) return;
    setState(() => _busy.remove(feed.url));
    if (result == null) {
      final message = rss.error ?? tr('device.could_not_add_it_check_the_url');
      rss.clearError();
      showAppSnack(context, message);
    } else {
      showAppSnack(context, trf('rss.subscribed_to__arg_0', [feed.name]));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final result = await PubrssClient().fetchSources();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _introTitle = result.introTitle;
        _introBody = result.introBody;
        _offlineFallback = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(RssController.recommended);
        _introTitle = null;
        _introBody = null;
        _offlineFallback = true;
        _loading = false;
      });
    }
  }

  Set<String> get _categories => {
        for (final f in _items)
          if (f.category.isNotEmpty) f.category,
      };

  List<RecommendedFeed> get _visible => _category == null
      ? _items
      : _items.where((f) => f.category == _category).toList();

  void _showIntro() {
    // 接口有返回就用接口的；没返回（或离线 fallback 模式）用本地写死的 i18n 文案。
    final title = _introTitle ?? tr('rss.intro_title');
    final body = _introBody ?? tr('rss.intro_body');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('ui.ok')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssController>();
    final c = appColors(context);

    return Scaffold(
      appBar: DchatAppBar(
        title: Text(
          tr('rss.recommended'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: tr('ui.info'),
            icon: const Icon(Icons.info_outline),
            onPressed: _showIntro,
          ),
          IconButton(
            tooltip: tr('rss.change_batch'),
            icon: _loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.accent,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              // loading 指示 + 离线/错误 banner
              if (_offlineFallback)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: c.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_off, color: c.danger, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tr('rss.server_failed'),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: c.muted,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: Text(tr('rss.retry')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_loading && _items.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              if (!_loading || _items.isNotEmpty) ...[
                // 分类 chips
                if (_categories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _FilterChip(
                              label: tr('ui.all'),
                              selected: _category == null,
                              onTap: () => setState(() => _category = null),
                            ),
                            for (final category in _categories) ...[
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: tr(category),
                                selected: _category == category,
                                onTap: () => setState(() => _category = category),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: MediaQuery.sizeOf(context).width < 480
                          ? 420
                          : 360,
                      mainAxisExtent: 190,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final feed = _visible[index];
                        return _RecommendCard(
                          feed: feed,
                          subscribed: _subscribed(rss, feed),
                          busy: _busy.contains(feed.url),
                          onSubscribe: () => _subscribe(rss, feed),
                        );
                      },
                      childCount: _visible.length,
                    ),
                  ),
                ),
                if (_visible.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Column(
                        children: [
                          Icon(Icons.search_off, size: 34, color: c.faint),
                          const SizedBox(height: 10),
                          Text(
                            tr('rss.no_recommendations_in_this_category_yet'),
                            style: TextStyle(fontSize: 13, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.accent : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? c.onAccent : c.muted,
          ),
        ),
      ),
    );
  }
}

class _RecommendCard extends StatelessWidget {
  final RecommendedFeed feed;
  final bool subscribed;
  final bool busy;
  final VoidCallback onSubscribe;

  const _RecommendCard({
    required this.feed,
    required this.subscribed,
    required this.busy,
    required this.onSubscribe,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final tint = avatarColor(feed.name, c);
    return Material(
      color: c.panel,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: subscribed || busy ? null : onSubscribe,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tint.withValues(alpha: 0.28)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initial(feed.name),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: tint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          feed.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: c.text,
                          ),
                        ),
                        if (feed.category.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            tr(feed.category),
                            style: TextStyle(fontSize: 11.5, color: c.faint),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (subscribed)
                    Icon(Icons.check_circle, size: 18, color: c.accent),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  feed.description.isEmpty
                      ? tr('rss.add_an_rss_or_atom_url_everything_stays_on_this_device')
                      : tr(feed.description),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: c.muted),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      feed.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.faint),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SubscribeButton(
                    subscribed: subscribed,
                    busy: busy,
                    onPressed: onSubscribe,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initial(String name) {
    for (final r in name.trim().runes) {
      final ch = String.fromCharCode(r);
      if (ch.trim().isNotEmpty) return ch.toUpperCase();
    }
    return '?';
  }
}

class _SubscribeButton extends StatelessWidget {
  final bool subscribed;
  final bool busy;
  final VoidCallback onPressed;

  const _SubscribeButton({
    required this.subscribed,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (subscribed) {
      return OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.check, size: 15),
        label: Text(tr('rss.subscribed'), style: const TextStyle(fontSize: 12)),
      );
    }
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: busy
          ? const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add, size: 15),
      label: Text(
        busy ? tr('rss.subscribing') : tr('rss.subscribe'),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
