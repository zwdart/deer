import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../state/chat_controller.dart';
import '../../state/chats_view_model.dart';
import '../../state/home_view_model.dart';
import '../adaptive.dart';
import '../dialogs/dialogs.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'chats_screen.dart';
import 'discover_screen.dart';

/// 「消息」菜单：把会话与设备合并成一个入口，用分段控件切换两个子页。
class CommScreen extends StatefulWidget {
  const CommScreen({super.key});

  @override
  State<CommScreen> createState() => _CommScreenState();
}

class _CommScreenState extends State<CommScreen> {
  HomeViewModel? _home;
  int _segment = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final home = context.read<HomeViewModel>();
    if (!identical(home, _home)) {
      _home?.commSegment.removeListener(_onSegment);
      _home = home;
      home.commSegment.addListener(_onSegment);
      _segment = home.commSegment.value;
    }
  }

  @override
  void dispose() {
    _home?.commSegment.removeListener(_onSegment);
    super.dispose();
  }

  void _onSegment() {
    final value = _home?.commSegment.value ?? 0;
    if (value != _segment && mounted) setState(() => _segment = value);
  }

  void _selectSegment(int value) {
    if (_segment == value) return;
    setState(() => _segment = value);
    _home?.commSegment.value = value;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    final vm = context.watch<ChatsViewModel>();
    final home = context.read<HomeViewModel>();
    final colors = appColors(context);

    return Scaffold(
      appBar: DchatAppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            GestureDetector(
              onTap: home.openSettings,
              child: PeerAvatar(
                name: c.profile.name,
                avatar: c.profile.avatar,
                status: c.profile.status,
                size: 36,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('dchat'),
                  Text(
                    _networkLine(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_segment == 0) ...[
            IconAction(
              icon: vm.searching ? Icons.close : Icons.search,
              tooltip: vm.searching
                  ? L10n.instance.tr('system.close_search')
                  : L10n.instance.tr('ui.search'),
              onPressed: vm.toggleSearch,
            ),
            _StatusMenu(controller: c),
          ] else ...[
            IconAction(
              icon: Icons.add_link,
              tooltip: L10n.instance.tr('device.connect_by_address'),
              onPressed: () => connectByAddress(context, c),
            ),
            IconAction(
              icon: Icons.refresh,
              tooltip: L10n.instance.tr('device.restart_discovery'),
              onPressed: () async {
                await c.restartNetwork();
                if (context.mounted) {
                  showAppSnack(context, L10n.instance.tr('device.searching_the_lan_again'));
                }
              },
            ),
          ],
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AdaptiveSegmentedControl(
                segments: [
                  AdaptiveSegment('chats', L10n.instance.tr('chat.chats')),
                  AdaptiveSegment('devices', L10n.instance.tr('device.devices_2')),
                ],
                selected: _segment == 0 ? 'chats' : 'devices',
                onChanged: (value) => _selectSegment(value == 'devices' ? 1 : 0),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'comm-create-group',
        tooltip: L10n.instance.tr('chat.new_group_3'),
        onPressed: () => createGroupFlow(context, c),
        child: const Icon(Icons.group_add_outlined),
      ),
      body: IndexedStack(
        index: _segment,
        children: const [ChatsScreen(), DiscoverScreen()],
      ),
    );
  }

  String _networkLine(ChatController c) {
    final count = c.peers.values.where((p) => p.connected).length;
    if (!c.ready) return L10n.instance.tr('ui.starting');
    if (c.settings.discovery) {
      return count == 0
          ? L10n.instance.tr('device.auto_discovery_on')
          : '$count ${L10n.instance.tr('device.devices_online')}';
    }
    return count == 0
        ? L10n.instance.tr('device.auto_discovery_off_2')
        : '$count ${L10n.instance.tr('device.devices_connected')}';
  }
}

class _StatusMenu extends StatelessWidget {
  final ChatController controller;

  const _StatusMenu({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return PopupMenuButton<Presence>(
      tooltip: L10n.instance.tr('ui.my_status'),
      initialValue: controller.profile.status,
      onSelected: controller.setStatus,
      itemBuilder: (context) => [
        for (final p in presenceOptions)
          PopupMenuItem(
            value: p,
            child: Row(
              children: [
                StatusDot(status: p, size: 9),
                const SizedBox(width: 10),
                Text(L10n.instance.tr(presenceLabelKey(p))),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusDot(status: controller.profile.status, size: 8),
            const SizedBox(width: 5),
            Text(
              L10n.instance.tr(presenceLabelKey(controller.profile.status)),
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}
