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
                hintText: L10n.instance.tr('chat.search_chats'),
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
            ),
          ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.forum_outlined,
                  title: query.isEmpty
                      ? L10n.instance.tr('chat.no_chats_yet')
                      : L10n.instance.tr('chat.no_matching_chats'),
                  message: query.isEmpty
                      ? L10n.instance.tr('chat.open_discover_to_find_contacts_on_your_lan_or_create_a_group_with_the_button_below')
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
            ? '${L10n.instance.tr('ui.draft')}：${conversation.draft}'
            : L10n.instance.tr('chat.no_messages_yet'))
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
    if (m.recalled) return L10n.instance.tr('chat.message_unsent');
    switch (m.kind) {
      case MessageKind.image:
        return L10n.instance.tr('image.image_2');
      case MessageKind.file:
        return '${L10n.instance.tr('ui.file_2')} ${m.file?.name ?? ''}';
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
              ? L10n.instance.tr('chat.unpin')
              : L10n.instance.tr('chat.pin_chat'),
        ),
        AdaptiveSheetAction(
          value: 'mute',
          icon: conversation.muted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: conversation.muted
              ? L10n.instance.tr('chat.unmute')
              : L10n.instance.tr('chat.mute_chat'),
        ),
        AdaptiveSheetAction(
          value: 'clear',
          icon: Icons.cleaning_services_outlined,
          label: L10n.instance.tr('chat.clear_chat_history'),
        ),
        AdaptiveSheetAction(
          value: 'delete',
          icon: Icons.delete_outline,
          label: L10n.instance.tr('chat.delete_chat'),
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
          title: L10n.instance.tr('chat.clear_chat_history_2'),
          message: L10n.instance.tr('chat.messages_on_this_device_will_be_deleted_and_cannot_be_recovered'),
          confirm: L10n.instance.tr('ui.clear_3'),
          destructive: true,
        )) {
          controller.clearHistory(conversation.id);
        }
        break;
      case 'delete':
        if (await confirmAction(
          context,
          title: L10n.instance.tr('chat.delete_chat_2'),
          message: L10n.instance.tr('chat.chats_and_messages_on_this_device_will_be_deleted'),
          confirm: L10n.instance.tr('ui.delete'),
          destructive: true,
        )) {
          controller.deleteConversation(conversation.id);
        }
        break;
    }
  }
}
