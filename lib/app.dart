import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/desktop_service.dart';
import 'services/keep_awake_service.dart';
import 'services/screenshot_service.dart';
import 'state/chat_controller.dart';
import 'state/chats_view_model.dart';
import 'state/home_view_model.dart';
import 'state/rss_controller.dart';
import 'state/update_view_model.dart';
import 'ui/adaptive.dart';
import 'ui/navigation.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

class DeerApp extends StatefulWidget {
  final ChatController controller;
  final RssController rss;
  final HomeViewModel home;
  final ChatsViewModel chats;
  final DesktopService desktop;

  const DeerApp({
    super.key,
    required this.controller,
    required this.rss,
    required this.home,
    required this.chats,
    required this.desktop,
  });

  @override
  State<DeerApp> createState() => _DeerAppState();
}

class _DeerAppState extends State<DeerApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.onOpenConversation = _openConversation;
    widget.controller.addListener(_syncKeepAwake);
    _syncKeepAwake();
  }

  void _openConversation(String convId) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    openChatScreen(context, convId);
  }

  void _syncKeepAwake() {
    KeepAwakeService.instance.sync(
      enabled: widget.controller.settings.keepAwake,
      foreground: _foreground,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    _foreground = visible;
    _syncKeepAwake();
    widget.controller.setAppVisible(visible);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_syncKeepAwake);
    KeepAwakeService.instance.release();
    widget.controller.onOpenConversation = null;
    widget.desktop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatController>.value(value: widget.controller),
        ChangeNotifierProvider<RssController>.value(value: widget.rss),
        ChangeNotifierProvider<HomeViewModel>.value(value: widget.home),
        ChangeNotifierProvider<ChatsViewModel>.value(value: widget.chats),
        ChangeNotifierProvider<UpdateViewModel>(
          create: (_) => UpdateViewModel(),
        ),
      ],
      child: Selector<ChatController, String>(
        selector: (_, controller) =>
            '${controller.settings.appearance}|${controller.settings.language}',
        builder: (context, value, _) {
          final parts = value.split('|');
          final appearance = parts.first;
          return MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'deer',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(
              brightness: Brightness.light,
              platform: AppPlatform.targetPlatform,
            ),
            darkTheme: buildAppTheme(
              brightness: Brightness.dark,
              platform: AppPlatform.targetPlatform,
            ),
            themeMode: switch (appearance) {
              'light' => ThemeMode.light,
              'dark' => ThemeMode.dark,
              _ => ThemeMode.system,
            },
            builder: (context, child) {
              return RepaintBoundary(
                key: ScreenshotService.instance.boundaryKey,
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
