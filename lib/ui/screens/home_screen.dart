import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../state/chat_controller.dart';
import '../../state/chats_view_model.dart';
import '../../state/home_view_model.dart';
import '../adaptive.dart';
import '../dialogs/dialogs.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'comm_screen.dart';
import 'recommended_feeds_screen.dart';
import 'rss_screen.dart';
import 'share_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _pages = [
    RssScreen(),
    RecommendedFeedsScreen(),
    CommScreen(),
    ShareScreen(),
  ];

  static List<_NavItem> _items() => [
        _NavItem(Icons.newspaper_outlined, Icons.newspaper,
            L10n.instance.tr('rss.news')),
        _NavItem(Icons.explore_outlined, Icons.explore,
            L10n.instance.tr('rss.discover')),
        _NavItem(Icons.forum_outlined, Icons.forum, L10n.instance.tr('chat.messages_2')),
        _NavItem(Icons.folder_shared_outlined, Icons.folder_shared,
            L10n.instance.tr('share.share')),
      ];

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeViewModel>();
    final chats = context.read<ChatsViewModel>();
    // 语言切换后标签需要立即重算，HomeScreen 本身不会随 MaterialApp 重建。
    return ListenableBuilder(
      listenable: L10n.instance,
      builder: (context, _) {
        final items = _items();
        final body = _ShortcutHost(
          chats: chats,
          home: home,
          child: AppPlatform.isDesktop
              ? _DesktopShell(home: home, items: items)
              : _MobileShell(home: home, items: items, pages: _pages),
        );
        return _ToastHost(
          child: _SettingsRouteHost(home: home, child: body),
        );
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavItem(this.icon, this.selectedIcon, this.label);
}

class _MobileShell extends StatelessWidget {
  final HomeViewModel home;
  final List<_NavItem> items;
  final List<Widget> pages;

  const _MobileShell({
    required this.home,
    required this.items,
    required this.pages,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: home.index, children: pages),
      bottomNavigationBar: AppPlatform.isIOS
          ? CupertinoTabBar(
              currentIndex: home.index,
              onTap: home.select,
              activeColor: appColors(context).accent,
              items: [
                for (final item in items)
                  BottomNavigationBarItem(
                    icon: Icon(item.icon),
                    activeIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ),
              ],
            )
          : NavigationBar(
              selectedIndex: home.index,
              onDestinationSelected: home.select,
              destinations: [
                for (final item in items)
                  NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: item.label,
                  ),
              ],
            ),
    );
  }
}

class _DesktopShell extends StatelessWidget {
  final HomeViewModel home;
  final List<_NavItem> items;

  const _DesktopShell({required this.home, required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _DesktopMenuBar(),
          Expanded(
            child: Row(
              children: [
                _SideRail(home: home, items: items),
                Container(
                  width: 1,
                  color: appColors(context).border,
                ),
                Expanded(
                  child: IndexedStack(
                    index: home.index,
                    children: HomeScreen._pages,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  final HomeViewModel home;
  final List<_NavItem> items;

  const _SideRail({required this.home, required this.items});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final chat = context.watch<ChatController>();
    return Container(
      width: 210,
      color: c.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                PeerAvatar(
                  name: chat.profile.name,
                  avatar: chat.profile.avatar,
                  status: chat.profile.status,
                  size: 38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chat.profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        L10n.instance.tr(presenceLabelKey(chat.profile.status)),
                        style: TextStyle(fontSize: 11, color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          for (var i = 0; i < items.length; i++)
            _RailButton(
              item: items[i],
              selected: home.index == i,
              badge: i == 0 ? chat.totalUnread : 0,
              onTap: () => home.select(i),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _RailButton(
              item: _NavItem(
                Icons.settings_outlined,
                Icons.settings,
                L10n.instance.tr('settings.settings'),
              ),
              selected: false,
              badge: 0,
              onTap: home.openSettings,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'dchat · ${chat.localIps.isEmpty ? '' : chat.localIps.first}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: c.faint),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _RailButton({
    required this.item,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? c.accent.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                size: 19,
                color: selected ? c.accent : c.muted,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? c.accent : c.text,
                  ),
                ),
              ),
              if (badge > 0)
                UnreadBadge(count: badge, muted: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopMenuBar extends StatelessWidget {
  const _DesktopMenuBar();

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final chat = context.watch<ChatController>();
    final home = context.read<HomeViewModel>();
    final chats = context.read<ChatsViewModel>();
    return Container(
      height: 34,
      color: c.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'dchat',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.accent,
              ),
            ),
          ),
          MenuBar(
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(c.sidebar),
              elevation: const WidgetStatePropertyAll(0),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            children: [
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: () {
                      home.openChats();
                      chats.toggleSearch();
                    },
                    child: Text(L10n.instance.tr('chat.search_chats_ctrl_f')),
                  ),
                  MenuItemButton(
                    onPressed: home.openSettings,
                    child: Text(L10n.instance.tr('settings.settings_ctrl')),
                  ),
                ],
                child: Text(L10n.instance.tr('ui.files')),
              ),
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: home.openDevices,
                    child: Text(L10n.instance.tr('device.discover')),
                  ),
                  MenuItemButton(
                    onPressed: home.openShare,
                    child: Text(L10n.instance.tr('share.file_sharing')),
                  ),
                ],
                child: Text(L10n.instance.tr('chat.chats')),
              ),
              SubmenuButton(
                menuChildren: [
                  for (final presence in presenceOptions)
                    MenuItemButton(
                      onPressed: () => chat.setStatus(presence),
                      child: Row(
                        children: [
                          StatusDot(status: presence, size: 8),
                          const SizedBox(width: 8),
                          Text(L10n.instance.tr(presenceLabelKey(presence))),
                        ],
                      ),
                    ),
                ],
                child: Text(L10n.instance.tr('ui.status')),
              ),
              SubmenuButton(
                menuChildren: [
                  MenuItemButton(
                    onPressed: home.openSettings,
                    child: Text(L10n.instance.tr('system.about_dchat')),
                  ),
                ],
                child: Text(L10n.instance.tr('system.help')),
              ),
            ],
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              chat.ready ? L10n.instance.tr('device.lan_direct') : L10n.instance.tr('ui.starting'),
              style: TextStyle(fontSize: 11, color: c.faint),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutHost extends StatelessWidget {
  final ChatsViewModel chats;
  final HomeViewModel home;
  final Widget child;

  const _ShortcutHost({
    required this.chats,
    required this.home,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
            home.openChats();
            chats.toggleSearch();
          },
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
            home.openChats();
            chats.toggleSearch();
          },
          const SingleActivator(LogicalKeyboardKey.comma, control: true):
              home.openSettings,
          const SingleActivator(LogicalKeyboardKey.comma, meta: true):
              home.openSettings,
          const SingleActivator(LogicalKeyboardKey.digit1, control: true):
              () => home.select(0),
          const SingleActivator(LogicalKeyboardKey.digit1, meta: true):
              () => home.select(0),
          const SingleActivator(LogicalKeyboardKey.digit2, control: true):
              () => home.select(1),
          const SingleActivator(LogicalKeyboardKey.digit2, meta: true):
              () => home.select(1),
          const SingleActivator(LogicalKeyboardKey.digit3, control: true):
              () => home.select(2),
          const SingleActivator(LogicalKeyboardKey.digit3, meta: true):
              () => home.select(2),
          const SingleActivator(LogicalKeyboardKey.digit4, control: true):
              () => home.select(3),
          const SingleActivator(LogicalKeyboardKey.digit4, meta: true):
              () => home.select(3),
          const SingleActivator(LogicalKeyboardKey.escape): chats.closeSearch,
        },
        child: child,
      ),
    );
  }
}

/// 设置页改成员工页面后，托盘、快捷键这些拿不到 BuildContext 的入口统一发信号，由这里入栈。
class _SettingsRouteHost extends StatefulWidget {
  final HomeViewModel home;
  final Widget child;

  const _SettingsRouteHost({required this.home, required this.child});

  @override
  State<_SettingsRouteHost> createState() => _SettingsRouteHostState();
}

class _SettingsRouteHostState extends State<_SettingsRouteHost> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.home.settingsRequests.addListener(_push);
  }

  @override
  void dispose() {
    widget.home.settingsRequests.removeListener(_push);
    super.dispose();
  }

  Future<void> _push() async {
    if (_open || !mounted) return;
    _open = true;
    await openSettingsScreen(context);
    if (!mounted) return;
    _open = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ToastHost extends StatefulWidget {
  final Widget child;

  const _ToastHost({required this.child});

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost> {
  ChatController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ChatController>();
    if (!identical(controller, _controller)) {
      _controller?.toastNotifier.removeListener(_onToast);
      _controller = controller;
      controller.toastNotifier.addListener(_onToast);
    }
  }

  void _onToast() {
    final message = _controller?.toastNotifier.value;
    if (message == null || message.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showAppSnack(context, message);
    });
  }

  @override
  void dispose() {
    _controller?.toastNotifier.removeListener(_onToast);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
