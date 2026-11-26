import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/paths.dart';
import 'services/desktop_service.dart';
import 'state/chat_controller.dart';
import 'state/chats_view_model.dart';
import 'state/home_view_model.dart';
import 'state/rss_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DesktopService.supported) {
    await windowManager.ensureInitialized();
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }
  final paths = AppPaths();
  await paths.init();
  final controller = ChatController(paths);
  await controller.init();
  final rss = RssController(paths);
  await rss.init();
  final home = HomeViewModel();
  final chats = ChatsViewModel();
  final desktop = DesktopService(controller: controller, home: home);
  await desktop.init();
  runApp(
    DchatApp(
      controller: controller,
      rss: rss,
      home: home,
      chats: chats,
      desktop: desktop,
    ),
  );
}
