// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/legacy.dart' as tray;
import 'package:window_manager/window_manager.dart';

import '../core/i18n.dart';
import '../core/models.dart';
import '../state/chat_controller.dart';
import '../state/home_view_model.dart';
import '../ui/adaptive.dart';

class DesktopService with WindowListener, tray.TrayListener {
  final ChatController controller;
  final HomeViewModel home;

  bool _started = false;
  bool _quitting = false;
  HotKey? _showHotKey;
  int _lastUnread = -1;

  DesktopService({required this.controller, required this.home});

  static bool get supported => AppPlatform.isDesktop;

  Future<void> init() async {
    if (!supported || _started) return;
    _started = true;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1180, 780),
      minimumSize: Size(900, 620),
      center: true,
      title: 'deer',
      titleBarStyle: TitleBarStyle.normal,
      backgroundColor: Color(0xFF141416),
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    controller.addListener(_onControllerChanged);
    await _setupTray();
    await _setupHotKey();
  }

  Future<void> _setupTray() async {
    try {
      if (!tray.trayManager.isSupported) return;
      await tray.trayManager.setIcon('assets/icon.png', iconSize: 18);
      await tray.trayManager.setToolTip('deer');
      tray.trayManager.addListener(this);
      await refreshMenu();
    } catch (_) {}
  }

  Future<void> _setupHotKey() async {
    try {
      final modifier =
          Platform.isMacOS ? HotKeyModifier.meta : HotKeyModifier.control;
      _showHotKey = HotKey(
        key: PhysicalKeyboardKey.keyD,
        modifiers: [modifier, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );
      await hotKeyManager.register(
        _showHotKey!,
        keyDownHandler: (_) => showWindow(),
      );
    } catch (_) {
      _showHotKey = null;
    }
  }

  void _onControllerChanged() {
    final unread = controller.totalUnread;
    if (unread == _lastUnread) return;
    _lastUnread = unread;
    final label = unread > 0 ? 'deer · $unread' : 'deer';
    tray.trayManager.setToolTip(label);
    tray.trayManager.setTitle(Platform.isMacOS && unread > 0 ? '$unread' : '');
  }

  Future<void> refreshMenu() async {
    if (!supported) return;
    final menu = tray.Menu(
      items: [
        tray.MenuItem(
          key: 'open',
          label: L10n.instance.tr('ui.open_deer'),
          onClick: (_) => showWindow(),
        ),
        tray.MenuItem(
          key: 'devices',
          label: L10n.instance.tr('device.discover'),
          onClick: (_) {
            home.openDevices();
            showWindow();
          },
        ),
        tray.MenuItem(
          key: 'share',
          label: L10n.instance.tr('share.file_sharing'),
          onClick: (_) {
            home.openShare();
            showWindow();
          },
        ),
        tray.MenuItem(
          key: 'settings',
          label: L10n.instance.tr('settings.settings'),
          onClick: (_) {
            home.openSettings();
            showWindow();
          },
        ),
        tray.MenuItem.separator(),
        tray.MenuItem.submenu(
          key: 'status',
          label: L10n.instance.tr('ui.status'),
          submenu: tray.Menu(
            items: [
              for (final presence in presenceOptions)
                tray.MenuItem(
                  key: 'status_${presence.name}',
                  label: L10n.instance.tr(presenceLabelKey(presence)),
                  checked: controller.profile.status == presence,
                  onClick: (_) => controller.setStatus(presence),
                ),
            ],
          ),
        ),
        tray.MenuItem.separator(),
        tray.MenuItem(
          key: 'quit',
          label: L10n.instance.tr('system.quit'),
          onClick: (_) => quit(),
        ),
      ],
    );
    try {
      await tray.trayManager.setContextMenu(menu);
    } catch (_) {}
  }

  Future<void> showWindow() async {
    if (!supported) return;
    await windowManager.show();
    await windowManager.focus();
    controller.setAppVisible(true);
  }

  Future<void> hideWindow() async {
    if (!supported) return;
    await windowManager.hide();
    controller.setAppVisible(false);
  }

  Future<void> toggleWindow() async {
    if (await windowManager.isVisible()) {
      await hideWindow();
    } else {
      await showWindow();
    }
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await controller.shutdown();
    } catch (_) {}
    try {
      await HotKeyManager.instance.unregisterAll();
    } catch (_) {}
    try {
      tray.trayManager.removeListener(this);
      await tray.trayManager.destroy();
    } catch (_) {}
    windowManager.removeListener(this);
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {
      exit(0);
    }
  }

  Future<void> dispose() async {
    controller.removeListener(_onControllerChanged);
    windowManager.removeListener(this);
    tray.trayManager.removeListener(this);
    await HotKeyManager.instance.unregisterAll();
  }

  @override
  void onWindowClose() {
    if (controller.settings.closeToTray) {
      hideWindow();
    } else {
      quit();
    }
  }

  @override
  void onWindowFocus() => controller.setAppVisible(true);

  @override
  void onWindowBlur() => controller.setAppVisible(false);

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    tray.trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    menuItem.onClick?.call(menuItem);
  }
}
