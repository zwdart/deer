import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../state/chat_controller.dart';
import '../adaptive.dart';
import '../dialogs/dialogs.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    final colors = appColors(context);
    final peers = c.sortedPeers().where((p) => p.id != c.profile.id).toList();

    return RefreshIndicator(
      onRefresh: c.restartNetwork,
      child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            _NetworkCard(controller: c),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  L10n.instance.tr('device.nearby_devices'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                const Spacer(),
                Text(
                  trf('ui.arg_0___arg_1__online', [
                  peers.where((p) => p.connected).length,
                  peers.length,
                ]),
                  style: TextStyle(fontSize: 11.5, color: colors.faint),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (peers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyState(
                  icon: Icons.devices_other,
                  title: L10n.instance.tr('device.no_devices_found'),
                  message: c.settings.discovery
                      ? L10n.instance.tr('device.make_sure_other_devices_are_on_the_same_lan_and_have_zchat_open')
                      : L10n.instance.tr('device.auto_discovery_is_off_enable_it_or_connect_manually_by_ip_address'),
                  action: c.settings.discovery
                      ? OutlinedButton.icon(
                          onPressed: () => connectByAddress(context, c),
                          icon: const Icon(Icons.add_link, size: 18),
                          label: Text(L10n.instance.tr('device.connect_manually')),
                        )
                      : FilledButton.icon(
                          onPressed: () => c.setDiscovery(true),
                          icon: const Icon(Icons.wifi_find, size: 18),
                          label: Text(L10n.instance.tr('device.enable_auto_discovery')),
                        ),
                ),
              )
            else
              for (final peer in peers)
                _PeerTile(
                  controller: c,
                  peer: peer,
                  onTap: () => _openPeer(context, c, peer),
                  onSecondaryTap: () => _openPeer(context, c, peer),
                ),
            const SizedBox(height: 22),
            SectionCard(
              title: L10n.instance.tr('ui.tip_2'),
              child: Text(
                L10n.instance.tr(
                  '设备之间通过 UDP 自动发现，聊天使用 TCP 直连，文件不经过云端。如果无法发现设备，请检查系统是否允许局域网访问。',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: colors.muted,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
  }

  Future<void> _openPeer(
    BuildContext context,
    ChatController c,
    Peer peer,
  ) async {
    final action = await showAdaptiveActionSheet<String>(
      context,
      title: peer.displayName,
      message: peer.connected
          ? '${peer.addr} · ${L10n.instance.tr(presenceLabelKey(peer.status))}'
          : L10n.instance.tr('ui.offline'),
      actions: [
        AdaptiveSheetAction(
          value: 'chat',
          icon: Icons.chat_bubble_outline,
          label: L10n.instance.tr('chat.send_message'),
        ),
        AdaptiveSheetAction(
          value: 'connect',
          icon: Icons.wifi_tethering,
          label: peer.connected
              ? L10n.instance.tr('device.refresh_connection')
              : L10n.instance.tr('device.connect_device'),
        ),
        AdaptiveSheetAction(
          value: 'alias',
          icon: Icons.edit_outlined,
          label: L10n.instance.tr('ui.edit_alias'),
        ),
        AdaptiveSheetAction(
          value: 'remove',
          icon: Icons.delete_outline,
          label: L10n.instance.tr('ui.remove_from_list'),
          destructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'chat':
        await _openChat(context, c, peer);
        break;
      case 'connect':
        try {
          await c.connectPeer(peer.id);
          if (context.mounted) showAppSnack(context, L10n.instance.tr('device.connecting'));
        } catch (e) {
          if (context.mounted) showAppSnack(context, '$e');
        }
        break;
      case 'alias':
        final name = await promptText(
          context,
          title: L10n.instance.tr('ui.edit_alias'),
          label: L10n.instance.tr('ui.alias_2'),
          initial: peer.alias,
        );
        if (name != null) c.setAlias(peer.id, name);
        break;
      case 'remove':
        if (await confirmAction(
          context,
          title: L10n.instance.tr('device.remove_this_device_from_the_list'),
          message: L10n.instance.tr('device.it_will_reappear_if_the_device_broadcasts_again'),
          confirm: L10n.instance.tr('ui.remove_3'),
          destructive: true,
        )) {
          c.removePeer(peer.id);
        }
        break;
    }
  }

  Future<void> _openChat(
    BuildContext context,
    ChatController c,
    Peer peer,
  ) async {
    try {
      if (!peer.connected) await c.connectPeer(peer.id);
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('device.could_not_connect__arg_0', ['$e']));
      return;
    }
    final conv = c.ensureDirect(peer);
    if (!context.mounted) return;
    await openChatScreen(context, conv.id);
  }
}

/// 通过 IP / IP:端口 手动连接设备，成功后直接进入会话。
Future<void> connectByAddress(BuildContext context, ChatController c) async {
  final input = await promptText(
    context,
    title: L10n.instance.tr('device.connect_by_address'),
    label: L10n.instance.tr('device.ip_or_ip_port'),
    confirm: L10n.instance.tr('device.connect'),
  );
  if (input == null || input.isEmpty || !context.mounted) return;
  try {
    final peer = await c.manualConnect(input);
    final conv = c.ensureDirect(peer);
    if (!context.mounted) return;
    await openChatScreen(context, conv.id);
  } catch (e) {
    if (context.mounted) showAppSnack(context, trf('device.connection_failed__arg_0', ['$e']));
  }
}

class _NetworkCard extends StatelessWidget {
  final ChatController controller;

  const _NetworkCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final ips = controller.localIps;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.accent.withValues(alpha: 0.16),
            c.accent.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.wifi_tethering, color: c.accent, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.settings.discovery ? L10n.instance.tr('device.lan_auto_discovery') : L10n.instance.tr('device.manual_connection_only'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ips.isEmpty
                      ? L10n.instance.tr('device.no_lan_address_available')
                      : trf('device.arg_0__port__arg_1', [ips.first, controller.settings.port]),
                  style: TextStyle(fontSize: 11.5, color: c.muted),
                ),
              ],
            ),
          ),
          AdaptiveSwitch(
            value: controller.settings.discovery,
            onChanged: controller.setDiscovery,
          ),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  final ChatController controller;
  final Peer peer;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;

  const _PeerTile({
    required this.controller,
    required this.peer,
    required this.onTap,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onSecondaryTap: onSecondaryTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              PeerAvatar(
                name: peer.displayName,
                avatar: peer.avatar,
                status: peer.status,
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            peer.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (peer.manual) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.bookmark_outline,
                              size: 13, color: c.faint),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      peer.signature.isNotEmpty
                          ? peer.signature
                          : peer.addr.isEmpty
                              ? L10n.instance.tr('device.address_unknown')
                              : peer.addr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    peer.connected
                        ? L10n.instance.tr(presenceLabelKey(peer.status))
                        : L10n.instance.tr('ui.offline'),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: peer.connected
                          ? presenceColor(peer.status, c)
                          : c.faint,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Icon(
                    peer.connected
                        ? Icons.chevron_right
                        : Icons.wifi_tethering,
                    size: 17,
                    color: c.faint,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
