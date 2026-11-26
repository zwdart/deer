import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/helpers.dart';
import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../state/chat_controller.dart';
import '../../state/chats_view_model.dart';
import '../adaptive.dart';
import '../dialogs/dialogs.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    final vm = context.watch<ChatsViewModel>();
    final list = vm.filtered(c);
    final query = vm.query;

    return Column(
      children: [
        if (vm.searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: vm.searchController,
              autofocus: true,
              onChanged: vm.setQuery,
              decoration: InputDecoration(
                hintText: L10n.instance.tr('搜索会话'),
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
            ),
          ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.forum_outlined,
                  title: query.isEmpty
                      ? L10n.instance.tr('还没有会话')
                      : L10n.instance.tr('没有匹配的会话'),
                  message: query.isEmpty
                      ? L10n.instance.tr('打开“设备”发现局域网内的联系人，或点击右下角创建群聊。')
                      : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 100),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final conv = list[index];
                    return _ConversationTile(
                      controller: c,
                      conversation: conv,
                      onTap: () => openChatScreen(context, conv.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 从任意入口创建群聊：拉取候选设备、弹草稿框，成功后进入会话。
Future<void> createGroupFlow(BuildContext context, ChatController c) async {
  final candidates = c.sortedPeers().where((p) => p.id != c.profile.id).toList();
  final draft = await showGroupDraftDialog(context, candidates: candidates);
  if (draft == null || !context.mounted) return;
  final conv = c.createGroup(draft.name, draft.members);
  await openChatScreen(context, conv.id);
}


class _ConversationTile extends StatelessWidget {
  final ChatController controller;
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.controller,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final peer = conversation.kind == ConvKind.direct
        ? controller.peers[conversation.peerId]
        : null;
    final isGroup = conversation.kind == ConvKind.group;
    final title = controller.conversationTitle(conversation);
    final last = conversation.last;
    final preview = last == null
        ? (conversation.draft.isNotEmpty
            ? '${L10n.instance.tr('草稿')}：${conversation.draft}'
            : L10n.instance.tr('还没有消息'))
        : _previewText(last);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: () => _showMenu(context),
        onSecondaryTap: () => _showMenu(context),
        child: Container(
          color: conversation.pinned
              ? c.accent.withValues(alpha: 0.055)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PeerAvatar(
                name: title,
                avatar: isGroup ? '' : (peer?.avatar ?? ''),
                status: peer?.status ?? Presence.offline,
                showStatus: !isGroup && peer != null,
                isGroup: isGroup,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (conversation.pinned)
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Icon(Icons.push_pin,
                                size: 13, color: c.faint),
                          ),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: conversation.unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: c.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeText(last?.sentAt ?? conversation.updatedAt),
                          style: TextStyle(fontSize: 11, color: c.faint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (conversation.muted)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.notifications_off_outlined,
                                size: 13, color: c.faint),
                          ),
                        if (last != null && last.mine && !isGroup)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              last.read
                                  ? Icons.done_all
                                  : last.delivered
                                      ? Icons.done_all
                                      : Icons.done,
                              size: 14,
                              color: last.read ? c.accent : c.faint,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: conversation.unread > 0
                                  ? c.muted
                                  : c.faint,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        UnreadBadge(
                          count: conversation.unread,
                          muted: conversation.muted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewText(Message m) {
    if (m.recalled) return L10n.instance.tr('消息已撤回');
    switch (m.kind) {
      case MessageKind.image:
        return L10n.instance.tr('[图片]');
      case MessageKind.file:
        return '${L10n.instance.tr('[文件]')} ${m.file?.name ?? ''}';
      case MessageKind.system:
        return m.text;
      case MessageKind.text:
        return m.text.replaceAll('\n', ' ');
    }
  }

  String _timeText(DateTime time) {
    final now = DateTime.now();
    if (sameDay(time, now)) {
      return formatClock(time);
    }
    if (time.year == now.year) {
      return '${time.month}/${time.day}';
    }
    return '${time.year}/${time.month}/${time.day}';
  }

  Future<void> _showMenu(BuildContext context) async {
    final action = await showAdaptiveActionSheet<String>(
      context,
      title: controller.conversationTitle(conversation),
      actions: [
        AdaptiveSheetAction(
          value: 'pin',
          icon: conversation.pinned ? Icons.push_pin_outlined : Icons.push_pin,
          label: conversation.pinned
              ? L10n.instance.tr('取消置顶')
              : L10n.instance.tr('置顶会话'),
        ),
        AdaptiveSheetAction(
          value: 'mute',
          icon: conversation.muted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: conversation.muted
              ? L10n.instance.tr('取消免打扰')
              : L10n.instance.tr('消息免打扰'),
        ),
        AdaptiveSheetAction(
          value: 'clear',
          icon: Icons.cleaning_services_outlined,
          label: L10n.instance.tr('清空聊天记录'),
        ),
        AdaptiveSheetAction(
          value: 'delete',
          icon: Icons.delete_outline,
          label: L10n.instance.tr('删除会话'),
          destructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'pin':
        controller.togglePinned(conversation.id);
        break;
      case 'mute':
        controller.toggleMuted(conversation.id);
        break;
      case 'clear':
        if (await confirmAction(
          context,
          title: L10n.instance.tr('清空聊天记录？'),
          message: L10n.instance.tr('本机上的消息将被删除，无法恢复。'),
          confirm: L10n.instance.tr('清空'),
          destructive: true,
        )) {
          controller.clearHistory(conversation.id);
        }
        break;
      case 'delete':
        if (await confirmAction(
          context,
          title: L10n.instance.tr('删除会话？'),
          message: L10n.instance.tr('本机上的会话和消息将被删除。'),
          confirm: L10n.instance.tr('删除'),
          destructive: true,
        )) {
          controller.deleteConversation(conversation.id);
        }
        break;
    }
  }
}
