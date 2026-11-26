import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/rss_models.dart';
import '../state/chat_controller.dart';
import '../state/chat_view_model.dart';
import 'adaptive.dart';
import 'screens/chat_screen.dart';
import 'screens/rss_reader_screen.dart';
import 'screens/settings_screen.dart';

Future<void> openChatScreen(BuildContext context, String conversationId) {
  final controller = context.read<ChatController>();
  controller.openConversation(conversationId);
  return Navigator.of(context).push<void>(
    adaptivePageRoute(
      ChangeNotifierProvider<ChatViewModel>(
        create: (_) => ChatViewModel(controller, conversationId),
        child: ChatScreen(conversationId: conversationId),
      ),
    ),
  );
}

/// 设置从标签页改成独立页面后，托盘、菜单栏和详情页都需要一个不带 BuildContext 的入口。
Future<void> openSettingsScreen(BuildContext context) {
  return Navigator.of(context).push<void>(
    adaptivePageRoute(const SettingsScreen()),
  );
}

/// 文章详情走微信读书式排版：正文列宽、字号由资讯设置控制。
/// 是否标记已读由详情页自己按设置处理。
Future<void> openRssReader(BuildContext context, RssArticle article) {
  return Navigator.of(context).push<void>(
    adaptivePageRoute(RssReaderScreen(article: article)),
  );
}
