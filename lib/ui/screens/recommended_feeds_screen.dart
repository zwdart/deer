import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/rss_models.dart';
import '../../state/rss_controller.dart';
import '../theme.dart';
import '../adaptive.dart';
import '../dialogs/dialogs.dart';

/// 「推荐」菜单：精选 RSS / Atom 订阅源，卡片式浏览，一键订阅。
class RecommendedFeedsScreen extends StatefulWidget {
  const RecommendedFeedsScreen({super.key});

  @override
  State<RecommendedFeedsScreen> createState() => _RecommendedFeedsScreenState();
}

class _RecommendedFeedsScreenState extends State<RecommendedFeedsScreen> {
  String? _category;
  final Set<String> _busy = {};

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
      final message = rss.error ?? tr('添加失败，请检查地址');
      rss.clearError();
      showAppSnack(context, message);
    } else {
      showAppSnack(context, trf('已订阅「%s」', [feed.name]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssController>();
    final c = appColors(context);
    final categories = {
      for (final f in RssController.recommended)
        if (f.category.isNotEmpty) f.category,
    }.toList();
    final visible = _category == null
        ? RssController.recommended
        : RssController.recommended
            .where((f) => f.category == _category)
            .toList();

    return Scaffold(
      appBar: DchatAppBar(
        title: Text(
          tr('推荐订阅'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: const [SizedBox(width: 4)],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: CustomScrollView(
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(child: _HeroBanner(count: RssController.recommended.length)),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _FilterChip(
                          label: tr('全部'),
                          selected: _category == null,
                          onTap: () => setState(() => _category = null),
                        ),
                        for (final category in categories) ...[
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
                      final feed = visible[index];
                      return _RecommendCard(
                        feed: feed,
                        subscribed: _subscribed(rss, feed),
                        busy: _busy.contains(feed.url),
                        onSubscribe: () => _subscribe(rss, feed),
                      );
                    },
                    childCount: visible.length,
                  ),
                ),
              ),
              if (visible.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Column(
                      children: [
                        Icon(Icons.search_off, size: 34, color: c.faint),
                        const SizedBox(height: 10),
                        Text(
                          tr('这个分类下暂时没有推荐'),
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final int count;

  const _HeroBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.accent.withValues(alpha: 0.18),
            c.accent.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.rss_feed, color: c.accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('精选订阅源'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  trf('共 %d 个优质 RSS 与 Atom 源，点一下即可订阅，内容只保存在本机。', [count]),
                  style: TextStyle(fontSize: 12, color: c.muted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
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
                  tr(feed.description),
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
        label: Text(tr('已订阅'), style: const TextStyle(fontSize: 12)),
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
        busy ? tr('订阅中…') : tr('立即订阅'),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
