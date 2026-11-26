import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/rss_models.dart';
import '../../state/rss_controller.dart';
import '../theme.dart';

/// 订阅源头像：优先用站点自带的 icon，缺失时退化成名称首字母。
class FeedAvatar extends StatelessWidget {
  final FeedSource feed;
  final double size;

  const FeedAvatar({super.key, required this.feed, this.size = 38});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final clipRRect = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: SizedBox(
        width: size,
        height: size,
        child: feed.iconUrl.isEmpty
            ? null
            : CachedNetworkImage(
                imageUrl: feed.iconUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: c.panel),
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
      ),
    );
    if (feed.iconUrl.isNotEmpty) return clipRRect;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: avatarColor(feed.hostName.isEmpty ? feed.title : feed.hostName, c)
            .withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: c.border),
      ),
      alignment: Alignment.center,
      child: Text(
        feed.avatarText,
        style: TextStyle(
          fontSize: size * 0.44,
          fontWeight: FontWeight.w700,
          color: avatarColor(feed.hostName.isEmpty ? feed.title : feed.hostName, c),
        ),
      ),
    );
  }
}

class RemoteImage extends StatelessWidget {
  final String url;
  final double height;
  final double radius;

  const RemoteImage({
    super.key,
    required this.url,
    this.height = 74,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(height: height, color: c.panel),
        errorWidget: (_, _, _) => Container(height: height, color: c.panel),
      ),
    );
  }
}

/// 详情页专用图片组件：完整显示（按比例自适应宽度），支持右键保存到本地。
class DetailImage extends StatefulWidget {
  final String url;
  final double radius;

  const DetailImage({
    super.key,
    required this.url,
    this.radius = 12,
  });

  @override
  State<DetailImage> createState() => _DetailImageState();
}

class _DetailImageState extends State<DetailImage> {
  bool _saving = false;

  Future<void> _saveImage() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode != 200 || !mounted) {
        _showSnack(tr('image.download_failed'));
        return;
      }
      final bytes = response.bodyBytes;
      final ext = _guessExt(response.headers['content-type'], widget.url);
      final dir = await _targetDir();
      if (dir == null || !mounted) {
        _showSnack(tr('image.cannot_locate_dir'));
        return;
      }
      final fileName = 'dchat_img_${DateTime.now().millisecondsSinceEpoch}$ext';
      final savePath = path.join(dir, fileName);
      await File(savePath).writeAsBytes(bytes);
      if (!mounted) return;
      _showSnack(trf('image.saved_to_path', [savePath]));
    } catch (e) {
      if (mounted) _showSnack(tr('image.save_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: CachedNetworkImage(
        imageUrl: widget.url,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        placeholder: (_, _) => Container(
          height: 160,
          color: c.panel,
          alignment: Alignment.center,
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
          ),
        ),
        errorWidget: (_, _, _) => Container(
          height: 160,
          color: c.panel,
          alignment: Alignment.center,
          child: Icon(Icons.broken_image_outlined, color: c.muted, size: 32),
        ),
      ),
    );

    return GestureDetector(
      onSecondaryTapDown: (details) {
        showMenu(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: [
            PopupMenuItem(
              value: 'save',
              enabled: !_saving,
              child: Row(
                children: [
                  Icon(Icons.download, size: 18, color: c.text),
                  const SizedBox(width: 8),
                  Text(_saving ? tr('image.saving') : tr('image.save_image')),
                ],
              ),
            ),
          ],
        ).then((value) {
          if (value == 'save') _saveImage();
        });
      },
      child: image,
    );
  }
}

String _guessExt(String? contentType, String url) {
  if (contentType != null) {
    final lower = contentType.toLowerCase();
    if (lower.contains('image/png')) return '.png';
    if (lower.contains('image/jpeg') || lower.contains('image/jpg')) return '.jpg';
    if (lower.contains('image/gif')) return '.gif';
    if (lower.contains('image/webp')) return '.webp';
    if (lower.contains('image/bmp')) return '.bmp';
  }
  final uri = Uri.tryParse(url);
  if (uri != null) {
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    if (seg != null) {
      final dot = seg.lastIndexOf('.');
      if (dot > 0 && dot < seg.length - 1) {
        final ext = seg.substring(dot).toLowerCase();
        if (ext.length <= 6) return ext;
      }
    }
  }
  return '.png';
}

Future<String?> _targetDir() async {
  try {
    final dir = await getDownloadsDirectory();
    if (dir != null) return dir.path;
  } catch (_) {}
  try {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  } catch (_) {
    return null;
  }
}

/// 信息流卡片：标题 + 摘要 + 出处，配图在右侧缩略。
class ArticleFlowCard extends StatelessWidget {
  final RssArticle article;
  final FeedSource? feed;
  final bool showImage;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ArticleFlowCard({
    super.key,
    required this.article,
    required this.feed,
    required this.showImage,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final title = article.title.isEmpty ? tr('ui.untitled') : article.title;
    final hasImage = showImage && article.imageUrl.isNotEmpty;
    return Material(
      color: c.panel,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!article.isRead)
                          Padding(
                            padding: const EdgeInsets.only(right: 6, top: 5),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: c.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.32,
                              fontWeight: FontWeight.w600,
                              color: article.isRead ? c.muted : c.text,
                            ),
                          ),
                        ),
                        if (article.isStarred) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.star, size: 15, color: c.accent),
                        ],
                      ],
                    ),
                    if (article.summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        article.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: c.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (feed != null) ...[
                          FeedAvatar(feed: feed!, size: 16),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: Text(
                              feed!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: c.faint),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          feedTimeLabel(article.sortAt),
                          style: TextStyle(fontSize: 11.5, color: c.faint),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ],
                ),
              ),
              if (hasImage) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 104,
                  child: RemoteImage(url: article.imageUrl, height: 74),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 订阅卡片：名称、未读数、同步状态，二级操作收进右下角菜单。
class SubscriptionCard extends StatelessWidget {
  final FeedSource feed;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  const SubscriptionCard({
    super.key,
    required this.feed,
    required this.onTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final failed = feed.lastSyncError != null && feed.lastSyncError!.isNotEmpty;
    return Material(
      color: c.panel,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: feed.syncEnabled ? c.border : c.border.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FeedAvatar(feed: feed, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feed.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: feed.syncEnabled ? c.text : c.faint,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          feed.hostName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: c.faint),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tr('rss.feed_actions'),
                    onPressed: onMenu,
                    icon: const Icon(Icons.more_horiz, size: 19),
                    visualDensity: VisualDensity.compact,
                    color: c.muted,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (feed.unreadCount > 0)
                    UnreadPill(count: feed.unreadCount)
                  else
                    Text(
                      tr('ui.no_unread'),
                      style: TextStyle(fontSize: 11.5, color: c.faint),
                    ),
                  const Spacer(),
                  if (failed)
                    Icon(Icons.error_outline, size: 14, color: c.danger),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FolderCard extends StatelessWidget {
  final RssFolder folder;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  const FolderCard({
    super.key,
    required this.folder,
    required this.onTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Material(
      color: c.panel,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.folder_open, size: 19, color: c.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('rss.folder_actions'),
                    onPressed: onMenu,
                    icon: const Icon(Icons.more_horiz, size: 19),
                    visualDensity: VisualDensity.compact,
                    color: c.muted,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    trf('rss.arg_0__feeds', [folder.sourceCount]),
                    style: TextStyle(fontSize: 11.5, color: c.faint),
                  ),
                  const SizedBox(width: 8),
                  if (folder.unreadCount > 0)
                    UnreadPill(count: folder.unreadCount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UnreadPill extends StatelessWidget {
  final int count;

  const UnreadPill({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        trf('ui.arg_0__unread', [count]),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: c.accent,
        ),
      ),
    );
  }
}

/// 顶部范围切换：全部 / 待读 / 收藏
class ScopeChips extends StatelessWidget {
  final RssScope scope;
  final int totalUnread;
  final int starredTotal;
  final ValueChanged<RssScope> onChanged;

  const ScopeChips({
    super.key,
    required this.scope,
    required this.totalUnread,
    required this.starredTotal,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    Widget chip(RssScope value, String label, int count) {
      final selected = scope == value;
      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c.accent : c.panel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? c.accent : c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? c.onAccent : c.muted,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? c.onAccent : c.faint,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(RssScope.all, tr('ui.all'), 0),
        chip(RssScope.unread, tr('ui.to_read'), totalUnread),
        chip(RssScope.starred, tr('rss.star'), starredTotal),
      ],
    );
  }
}

/// 详情页顶栏的订阅信息，点击可回到该订阅源的信息流。
class FeedLine extends StatelessWidget {
  final FeedSource? feed;
  final VoidCallback? onTap;

  const FeedLine({super.key, required this.feed, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    if (feed == null) return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FeedAvatar(feed: feed!, size: 22),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                feed!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 同步进行中时在列表顶部显示的细进度条。
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final rss = context.watch<RssController>();
    if (!rss.syncing) return const SizedBox.shrink();
    final progress = rss.syncTotal == 0 ? null : rss.syncDone / rss.syncTotal;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rss.syncTarget == null
                  ? tr('rss.syncing')
                  : trf('ui.arg_0___arg_1___arg_2_3', [rss.syncTarget!, rss.syncDone, rss.syncTotal]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
          if (progress != null)
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(fontSize: 11.5, color: c.faint),
            ),
        ],
      ),
    );
  }
}

String feedTimeLabel(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.isNegative || diff.inMinutes < 1) return tr('ui.just_now');
  if (diff.inMinutes < 60) return trf('ui.arg_0__min_ago', [diff.inMinutes]);
  if (diff.inHours < 24) return trf('ui.arg_0__hr_ago', [diff.inHours]);
  if (diff.inDays < 7) return trf('ui.arg_0__days_ago', [diff.inDays]);
  if (time.year == now.year) {
    return L10n.instance.english
        ? '${time.month}/${time.day}'
        : '${time.month}月${time.day}日';
  }
  return '${time.year}/${time.month}/${time.day}';
}
