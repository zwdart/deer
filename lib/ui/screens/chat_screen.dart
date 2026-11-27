import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/helpers.dart';
import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../services/screenshot_service.dart';
import '../../state/chat_controller.dart';
import '../../state/chat_view_model.dart';
import '../adaptive.dart';
import '../dialogs/dialogs.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'image_viewer_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  ChatController? _controller;
  int _lastCount = 0;
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.read<ChatController>();
    if (!identical(_controller, c)) {
      _controller?.removeListener(_onChanged);
      _controller = c;
      c.addListener(_onChanged);
    }
    if (!_opened) {
      _opened = true;
      _lastCount = c.msgs[widget.conversationId]?.length ?? 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        c.openConversation(widget.conversationId);
        _jumpToBottom();
      });
    }
  }

  void _onChanged() {
    final count = _controller?.msgs[widget.conversationId]?.length ?? 0;
    if (count == _lastCount) return;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.offset < 260) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    final viewModel = context.watch<ChatViewModel>();
    final conv = c.convs[widget.conversationId];
    if (conv == null) {
      return Scaffold(
        appBar: DeerAppBar(),
        body: EmptyState(
          icon: Icons.chat_bubble_outline,
          title: L10n.instance.tr('chat.chat_not_found'),
          message: L10n.instance.tr('ui.it_may_have_already_been_deleted'),
        ),
      );
    }
    final peer = conv.kind == ConvKind.direct ? c.peers[conv.peerId] : null;
    final messages = c.msgs[conv.id] ?? const <Message>[];
    final typing = c.typingNames(conv);

    return Scaffold(
      appBar: DeerAppBar(
        titleSpacing: 6,
        title: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showInfo(context, c, conv),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                PeerAvatar(
                  name: c.conversationTitle(conv),
                  avatar: peer?.avatar ?? '',
                  status: peer?.status ?? Presence.offline,
                  showStatus: conv.kind == ConvKind.direct,
                  isGroup: conv.kind == ConvKind.group,
                  size: 38,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.conversationTitle(conv),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _subtitle(c, conv, peer, typing),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: typing.isNotEmpty
                              ? c0(context).accent
                              : appColors(context).muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconAction(
            icon: Icons.info_outline,
            tooltip: L10n.instance.tr('chat.chat_info'),
            onPressed: () => _showInfo(context, c, conv),
          ),
          if (c.settings.screenshotEnabled)
            IconAction(
              icon: Icons.photo_camera_outlined,
              tooltip: L10n.instance.tr('image.screenshot'),
              onPressed: () => _takeScreenshot(context, c),
            ),
          _MoreMenu(controller: c, conversation: conv),
          const SizedBox(width: 4),
        ],
      ),
      body: DropTarget(
        enable: AppPlatform.isDesktop,
        onDragEntered: (_) => viewModel.setDragging(true),
        onDragExited: (_) => viewModel.setDragging(false),
        onDragDone: (detail) {
          viewModel.setDragging(false);
          final paths = detail.files.map((f) => f.path).toList();
          if (paths.isNotEmpty) c.sendFiles(paths);
        },
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? EmptyState(
                          icon: Icons.waving_hand_outlined,
                          title: L10n.instance.tr('chat.start_chatting'),
                          message: conv.kind == ConvKind.group
                              ? L10n.instance.tr('chat.send_the_first_message_to_the_devices_in_this_group')
                              : L10n.instance.tr('chat.messages_are_sent_directly_over_the_lan_without_a_server'),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final i = messages.length - 1 - index;
                            final m = messages[i];
                            final previous = i > 0 ? messages[i - 1] : null;
                            final showDate = previous == null ||
                                !sameDay(previous.sentAt, m.sentAt);
                            return _MessageRow(
                              controller: c,
                              conversation: conv,
                              message: m,
                              showDate: showDate,
                              showSender: conv.kind == ConvKind.group &&
                                  !m.mine &&
                                  (previous == null ||
                                      previous.senderId != m.senderId ||
                                      showDate),
                              onLongPress: () =>
                                  _showMessageActions(context, c, conv, m),
                              onOpenImage: () => _openImage(context, c, m),
                              onOpenFile: () => _openFile(context, c, m),
                              onDownload: () => _download(context, c, m),
                              onRetryDownload: () => _download(context, c, m),
                            );
                          },
                        ),
                ),
                if (typing.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: appColors(context).faint,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            trf('chat.arg_0__is_typing', [typing.join('、')]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: appColors(context).faint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _Composer(
                  controller: c,
                  conversation: conv,
                  input: viewModel.input,
                  canSend: viewModel.canSend,
                  onSend: viewModel.canSend ? () => _send(c, viewModel) : null,
                  onAttach: () => _showAttach(context, c),
                  onShareLink: () => _sendShareLink(context, c),
                ),
              ],
            ),
            if (viewModel.dragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: appColors(context).accent.withValues(alpha: 0.12),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: appColors(context).panel,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: appColors(context).accent),
                      ),
                      child: Text(
                        L10n.instance.tr('ui.release_to_send_files'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: appColors(context).accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  AppColors c0(BuildContext context) => appColors(context);

  String _subtitle(
    ChatController c,
    Conversation conv,
    Peer? peer,
    List<String> typing,
  ) {
    if (typing.isNotEmpty) return trf('chat.arg_0__is_typing', [typing.join('、')]);
    if (conv.kind == ConvKind.group) {
      return trf('chat.arg_0__members', [conv.members.length]);
    }
    if (peer == null) return L10n.instance.tr('device.device_info_unavailable');
    if (!peer.connected) return L10n.instance.tr('chat.offline_messages_will_be_sent_after_connecting');
    return L10n.instance.tr(presenceLabelKey(peer.status));
  }

  String get convId => widget.conversationId;

  Future<void> _send(ChatController c, ChatViewModel viewModel) async {
    await viewModel.send();
    _jumpToBottom();
  }

  Future<void> _takeScreenshot(
    BuildContext context,
    ChatController c,
  ) async {
    final bytes = await ScreenshotService.instance.capture();
    if (bytes == null) {
      if (context.mounted) {
        showAppSnack(context, L10n.instance.tr('image.could_not_create_the_screenshot'));
      }
      return;
    }
    final savedPath = await ScreenshotService.instance.saveToDirectory(
      bytes,
      c.settings.screenshotDir,
    );
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final colors = appColors(dialogContext);
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    L10n.instance.tr('image.screenshot'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.panel,
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  if (savedPath != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${L10n.instance.tr('image.screenshot_saved')}$savedPath',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: colors.muted),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(),
                        child: Text(L10n.instance.tr('system.close')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop('copy'),
                        icon: const Icon(Icons.copy_outlined, size: 17),
                        label: Text(L10n.instance.tr('ui.copy')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop('share'),
                        icon: const Icon(Icons.ios_share, size: 17),
                        label: Text(L10n.instance.tr('share.share_2')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop('save'),
                        icon: const Icon(Icons.save_alt, size: 17),
                        label: Text(L10n.instance.tr('ui.save')),
                      ),
                      FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop('send'),
                        icon: const Icon(Icons.send_outlined, size: 17),
                        label: Text(L10n.instance.tr('chat.send_to_current_chat')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'send':
        var path = savedPath;
        path ??= await ScreenshotService.instance.saveToDirectory(
          bytes,
          c.paths.cacheDir,
        );
        if (path == null) {
          if (context.mounted) {
            showAppSnack(context, L10n.instance.tr('image.could_not_save_the_screenshot_2'));
          }
          return;
        }
        await c.sendFiles([path]);
        _jumpToBottom();
        break;
      case 'copy':
        try {
          await Pasteboard.writeImage(bytes);
          if (context.mounted) {
            showAppSnack(context, L10n.instance.tr('ui.copied_2'));
          }
        } catch (_) {
          if (context.mounted) {
            showAppSnack(context, L10n.instance.tr('image.could_not_copy_the_screenshot_2'));
          }
        }
        break;
      case 'share':
        final path = savedPath ??
            await ScreenshotService.instance.saveToDirectory(
              bytes,
              c.paths.cacheDir,
            );
        if (path == null) return;
        await SharePlus.instance.share(
          ShareParams(files: [XFile(path)], text: 'deer'),
        );
        break;
      case 'save':
        try {
          final uri = await FilePicker.saveFile(
            fileName: savedPath == null
                ? 'deer.png'
                : savedPath.split(Platform.pathSeparator).last,
            bytes: bytes,
            mimeType: 'image/png',
            dialogTitle: L10n.instance.tr('image.save_screenshot'),
          );
          if (uri != null && context.mounted) {
            showAppSnack(
              context,
              '${L10n.instance.tr('image.screenshot_saved')}${uri.path}',
            );
          }
        } catch (e) {
          if (context.mounted) {
            showAppSnack(context, '${L10n.instance.tr('image.could_not_save_the_screenshot')}$e');
          }
        }
        break;
    }
  }

  Future<void> _showAttach(BuildContext context, ChatController c) async {
    final action = await showAdaptiveActionSheet<String>(
      context,
      title: L10n.instance.tr('ui.send'),
      actions: [
        AdaptiveSheetAction(
          value: 'gallery',
          icon: Icons.photo_library_outlined,
          label: AppPlatform.isDesktop
              ? L10n.instance.tr('image.choose_image')
              : L10n.instance.tr('image.images'),
        ),
        if (AppPlatform.isMobile)
          AdaptiveSheetAction(
            value: 'camera',
            icon: Icons.photo_camera_outlined,
            label: L10n.instance.tr('image.take_photo'),
          ),
        AdaptiveSheetAction(
          value: 'file',
          icon: Icons.attach_file,
          label: L10n.instance.tr('ui.files'),
        ),
        if (!AppPlatform.isIOS)
          AdaptiveSheetAction(
            value: 'clipboard',
            icon: Icons.content_paste_outlined,
            label: L10n.instance.tr('image.paste_image'),
          ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'gallery':
        try {
          if (AppPlatform.isDesktop) {
            final result = await FilePicker.pickFiles(
              type: FileType.image,
            );
            final paths =
                result.map((e) => e.path).whereType<String>().toList();
            if (paths.isNotEmpty) await c.sendFiles(paths);
          } else {
            final images = await ImagePicker().pickMultiImage();
            if (images.isEmpty) return;
            await c.sendFiles(images.map((e) => e.path).toList());
          }
        } catch (e) {
          if (context.mounted) showAppSnack(context, trf('image.could_not_choose_image__arg_0', ['$e']));
        }
        break;
      case 'camera':
        try {
          final image =
              await ImagePicker().pickImage(source: ImageSource.camera);
          if (image == null) return;
          await c.sendFiles([image.path]);
        } catch (e) {
          if (context.mounted) showAppSnack(context, trf('image.could_not_take_photo__arg_0', ['$e']));
        }
        break;
      case 'file':
        try {
          final result = await FilePicker.pickFiles();
          if (result.isEmpty) return;
          final paths =
              result.map((e) => e.path).whereType<String>().toList();
          if (paths.isNotEmpty) await c.sendFiles(paths);
        } catch (e) {
          if (context.mounted) showAppSnack(context, trf('ui.could_not_choose_file__arg_0', ['$e']));
        }
        break;
      case 'clipboard':
        await c.sendClipboardImage();
        break;
    }
    _jumpToBottom();
  }

  Future<void> _sendShareLink(BuildContext context, ChatController c) async {
    if (!c.shareRunning) {
      await c.startShare(quiet: true);
      if (!c.shareRunning) return;
    }
    final url = c.shareUrl();
    if (url.isEmpty) {
      if (context.mounted) showAppSnack(context, L10n.instance.tr('share.file_sharing_is_off'));
      return;
    }
    await c.sendText('${L10n.instance.tr('share.i_shared_a_folder_with_zchat')}$url');
    _jumpToBottom();
  }

  Future<void> _download(
    BuildContext context,
    ChatController c,
    Message m,
  ) async {
    final path = m.file?.path ?? '';
    if (path.isNotEmpty && await File(path).exists()) {
      if (!context.mounted) return;
      await _openPath(context, path, m.file?.mime ?? '');
      return;
    }
    await c.downloadMessage(m.convId, m.id);
  }

  Future<void> _openImage(
    BuildContext context,
    ChatController c,
    Message m,
  ) async {
    final path = m.file?.path ?? '';
    if (path.isEmpty || !await File(path).exists()) {
      if (!context.mounted) return;
      await _download(context, c, m);
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      adaptivePageRoute<void>(
        ImageViewerScreen(
          path: path,
          title: m.file?.name ?? L10n.instance.tr('image.images'),
        ),
      ),
    );
  }

  Future<void> _openFile(
    BuildContext context,
    ChatController c,
    Message m,
  ) async {
    await _download(context, c, m);
  }

  Future<void> _openPath(
    BuildContext context,
    String path,
    String mime,
  ) async {
    if (mime.toLowerCase().startsWith('image/')) {
      if (!context.mounted) return;
      await Navigator.of(context).push(
        adaptivePageRoute<void>(
          ImageViewerScreen(
            path: path,
            title: path.split(Platform.pathSeparator).last,
          ),
        ),
      );
      return;
    }
    try {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && context.mounted) {
        showAppSnack(context, trf('ui.could_not_open_file__arg_0', [result.message]));
      }
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('ui.could_not_open_file__arg_0', ['$e']));
    }
  }

  Future<void> _showMessageActions(
    BuildContext context,
    ChatController c,
    Conversation conv,
    Message m,
  ) async {
    if (m.recalled) return;
    final action = await showAdaptiveActionSheet<String>(
      context,
      title: L10n.instance.tr('chat.message_actions'),
      actions: [
        if (m.kind == MessageKind.text && m.text.isNotEmpty)
          AdaptiveSheetAction(
            value: 'copy',
            icon: Icons.copy_outlined,
            label: L10n.instance.tr('ui.copy_text'),
          ),
        if (m.file != null) ...[
          AdaptiveSheetAction(
            value: 'download',
            icon: Icons.download_outlined,
            label: L10n.instance.tr('ui.download_open'),
          ),
          AdaptiveSheetAction(
            value: 'share-file',
            icon: Icons.share_outlined,
            label: L10n.instance.tr('share.share_file'),
          ),
          AdaptiveSheetAction(
            value: 'copy-link',
            icon: Icons.link,
            label: L10n.instance.tr('ui.copy_file_link'),
          ),
        ],
        if (m.mine)
          AdaptiveSheetAction(
            value: 'recall',
            icon: Icons.undo,
            label: L10n.instance.tr('chat.unsend'),
          ),
        AdaptiveSheetAction(
          value: 'delete',
          icon: Icons.delete_outline,
          label: L10n.instance.tr('ui.delete'),
          destructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.text));
        if (context.mounted) showAppSnack(context, L10n.instance.tr('ui.copied_2'));
        break;
      case 'download':
        await _download(context, c, m);
        break;
      case 'share-file':
        final path = m.file?.path ?? '';
        if (path.isEmpty || !await File(path).exists()) {
          if (context.mounted) showAppSnack(context, L10n.instance.tr('ui.download_the_file_first'));
          return;
        }
        await SharePlus.instance.share(
          ShareParams(files: [XFile(path)], text: m.file?.name ?? ''),
        );
        break;
      case 'copy-link':
        final link = c.shareLinkForMessage(m);
        if (link.isEmpty) {
          if (context.mounted) showAppSnack(context, L10n.instance.tr('ui.no_file_link_available'));
          return;
        }
        await Clipboard.setData(ClipboardData(text: link));
        if (context.mounted) showAppSnack(context, L10n.instance.tr('ui.link_copied'));
        break;
      case 'recall':
        c.recallMessage(conv.id, m.id);
        break;
      case 'delete':
        if (await confirmAction(
          context,
          title: L10n.instance.tr('chat.delete_this_message'),
          confirm: L10n.instance.tr('ui.delete'),
          destructive: true,
        )) {
          c.deleteMessage(conv.id, m.id);
        }
        break;
    }
  }

  Future<void> _showInfo(
    BuildContext context,
    ChatController c,
    Conversation conv,
  ) async {
    if (conv.kind == ConvKind.direct) {
      await _showPeerInfo(context, c, conv);
    } else {
      await _showGroupInfo(context, c, conv);
    }
  }

  Future<void> _showPeerInfo(
    BuildContext context,
    ChatController c,
    Conversation conv,
  ) async {
    final peer = c.peers[conv.peerId];
    if (peer == null) {
      showAppSnack(context, L10n.instance.tr('device.device_info_unavailable'));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final colors = appColors(context);
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            maxChildSize: 0.92,
            minChildSize: 0.4,
            builder: (context, scroll) {
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                children: [
                  Center(
                    child: PeerAvatar(
                      name: peer.displayName,
                      avatar: peer.avatar,
                      status: peer.status,
                      size: 84,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    peer.displayName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (peer.signature.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      peer.signature,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.muted, height: 1.4),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SectionCard(
                    child: Column(
                      children: [
                        InfoRow(
                          label: L10n.instance.tr('ui.status'),
                          value:
                              L10n.instance.tr(presenceLabelKey(peer.status)),
                        ),
                        InfoRow(
                          label: L10n.instance.tr('device.address'),
                          value: peer.addr.isEmpty ? L10n.instance.tr('ui.unknown') : peer.addr,
                        ),
                        if (peer.platform.isNotEmpty)
                          InfoRow(label: L10n.instance.tr('ui.platform'), value: peer.platform),
                        if (peer.version.isNotEmpty)
                          InfoRow(label: L10n.instance.tr('ui.version'), value: peer.version),
                        InfoRow(
                          label: L10n.instance.tr('device.connect'),
                          value: peer.connected ? L10n.instance.tr('device.connected') : L10n.instance.tr('device.not_connected'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final name = await promptText(
                              context,
                              title: L10n.instance.tr('ui.edit_alias'),
                              label: L10n.instance.tr('ui.alias_2'),
                              initial: peer.alias,
                            );
                            if (name == null) return;
                            c.setAlias(peer.id, name);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: Text(L10n.instance.tr('ui.alias')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            try {
                              await c.connectPeer(peer.id);
                              if (context.mounted) {
                                showAppSnack(context, L10n.instance.tr('device.connecting'));
                              }
                            } catch (e) {
                              if (context.mounted) {
                                showAppSnack(context, '$e');
                              }
                            }
                          },
                          icon: const Icon(Icons.wifi_tethering, size: 18),
                          label: Text(peer.connected ? L10n.instance.tr('device.refresh_connection') : L10n.instance.tr('device.connect')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: colors.danger,
                    ),
                    onPressed: () async {
                      if (await confirmAction(
                        context,
                        title: L10n.instance.tr('chat.delete_chat_2'),
                        message: L10n.instance.tr('chat.messages_on_this_device_will_be_deleted_the_device_will_remain_in_discover'),
                        confirm: L10n.instance.tr('ui.delete'),
                        destructive: true,
                      )) {
                        c.deleteConversation(conv.id);
                        if (context.mounted) Navigator.of(context).pop();
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(L10n.instance.tr('chat.delete_chat')),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _showGroupInfo(
    BuildContext context,
    ChatController c,
    Conversation conv,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final colors = appColors(context);
        return ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final current = c.convs[conv.id] ?? conv;
            final members = c.groupMembers(current);
            return SafeArea(
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.76,
                maxChildSize: 0.94,
                minChildSize: 0.4,
                builder: (context, scroll) {
                  return ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    children: [
                      Center(
                        child: PeerAvatar(
                          name: c.conversationTitle(current),
                          isGroup: true,
                          showStatus: false,
                          size: 76,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        c.conversationTitle(current),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        trf('chat.arg_0__members', [current.members.length]),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final name = await promptText(
                                  context,
                                  title: L10n.instance.tr('ui.rename_group'),
                                  label: L10n.instance.tr('chat.group_name'),
                                  initial: current.title,
                                );
                                if (name == null || name.isEmpty) return;
                                c.renameGroup(current.id, name);
                              },
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: Text(L10n.instance.tr('ui.rename')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () async {
                                final candidates = c
                                    .sortedPeers()
                                    .where((p) =>
                                        p.id != c.profile.id &&
                                        !current.members.contains(p.id))
                                    .toList();
                                final draft = await showGroupDraftDialog(
                                  context,
                                  candidates: candidates,
                                  title: L10n.instance.tr('chat.add_members'),
                                  confirm: L10n.instance.tr('ui.add'),
                                );
                                if (draft == null) return;
                                c.addGroupMembers(
                                  current.id,
                                  draft.members,
                                );
                              },
                              icon: const Icon(Icons.person_add_alt_1, size: 18),
                              label: Text(L10n.instance.tr('chat.add_members')),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SectionCard(
                        title: L10n.instance.tr('chat.group_members'),
                        child: Column(
                          children: [
                            for (final member in members)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: PeerAvatar(
                                  name: member.displayName,
                                  avatar: member.avatar,
                                  status: member.status,
                                  size: 36,
                                ),
                                title: Text(
                                  member.id == c.profile.id
                                      ? trf('ui.arg_0__me', [member.displayName])
                                      : member.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  member.id == c.profile.id
                                      ? L10n.instance.tr('chat.owner')
                                      : L10n.instance.tr(
                                          presenceLabelKey(member.status),
                                        ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: member.id == c.profile.id
                                    ? null
                                    : IconButton(
                                        tooltip: L10n.instance.tr('chat.remove_from_group'),
                                        icon: const Icon(
                                          Icons.person_remove_outlined,
                                          size: 20,
                                        ),
                                        onPressed: () async {
                                          if (await confirmAction(
                                            context,
                                            title:
                                                trf('chat.remove__arg_0__from_the_group', [member.displayName]),
                                            confirm: L10n.instance.tr('ui.remove_4'),
                                            destructive: true,
                                          )) {
                                            c.removeGroupMember(
                                              current.id,
                                              member.id,
                                            );
                                                      }
                                        },
                                      ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (current.owner == c.profile.id)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: colors.danger,
                          ),
                          onPressed: () async {
                            if (await confirmAction(
                              context,
                              title: L10n.instance.tr('chat.disband_group'),
                              message: L10n.instance.tr('chat.all_members_will_be_notified_that_the_group_was_disbanded'),
                              confirm: L10n.instance.tr('ui.dissolve'),
                              destructive: true,
                            )) {
                              c.disbandGroup(current);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_forever_outlined),
                          label: Text(L10n.instance.tr('chat.dissolve_group')),
                        )
                      else
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: colors.danger,
                          ),
                          onPressed: () async {
                            if (await confirmAction(
                              context,
                              title: L10n.instance.tr('chat.leave_group_4'),
                              confirm: L10n.instance.tr('system.quit'),
                              destructive: true,
                            )) {
                              c.leaveGroup(current);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            }
                          },
                          icon: const Icon(Icons.logout),
                          label: Text(L10n.instance.tr('chat.leave_group')),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _MoreMenu extends StatelessWidget {
  final ChatController controller;
  final Conversation conversation;

  const _MoreMenu({required this.controller, required this.conversation});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final isOwner = conversation.owner == controller.profile.id;
    return PopupMenuButton<String>(
      tooltip: L10n.instance.tr('ui.more'),
      onSelected: (value) async {
        switch (value) {
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
              confirm: L10n.instance.tr('ui.clear_3'),
              destructive: true,
            )) {
              controller.clearHistory(conversation.id);
            }
            break;
          case 'leave':
            if (await confirmAction(
              context,
              title: L10n.instance.tr('chat.leave_group_4'),
              confirm: L10n.instance.tr('system.quit'),
              destructive: true,
            )) {
              controller.leaveGroup(conversation);
              if (context.mounted) Navigator.of(context).pop();
            }
            break;
          case 'disband':
            if (await confirmAction(
              context,
              title: L10n.instance.tr('chat.disband_group'),
              confirm: L10n.instance.tr('ui.dissolve'),
              destructive: true,
            )) {
              controller.disbandGroup(conversation);
              if (context.mounted) Navigator.of(context).pop();
            }
            break;
          case 'delete':
            if (await confirmAction(
              context,
              title: L10n.instance.tr('chat.delete_chat_2'),
              confirm: L10n.instance.tr('ui.delete'),
              destructive: true,
            )) {
              controller.deleteConversation(conversation.id);
              if (context.mounted) Navigator.of(context).pop();
            }
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'pin',
          child: Text(conversation.pinned ? L10n.instance.tr('chat.unpin') : L10n.instance.tr('chat.pin_chat')),
        ),
        PopupMenuItem(
          value: 'mute',
          child: Text(conversation.muted ? L10n.instance.tr('chat.unmute') : L10n.instance.tr('chat.mute_chat')),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'clear', child: Text(L10n.instance.tr('chat.clear_chat_history'))),
        if (conversation.kind == ConvKind.group)
          PopupMenuItem(
            value: isOwner ? 'disband' : 'leave',
            child: Text(
              isOwner ? L10n.instance.tr('chat.dissolve_group') : L10n.instance.tr('chat.leave_group'),
              style: TextStyle(color: c.danger),
            ),
          )
        else
          PopupMenuItem(
            value: 'delete',
            child: Text(L10n.instance.tr('chat.delete_chat'), style: TextStyle(color: c.danger)),
          ),
      ],
      icon: const Icon(Icons.more_horiz),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final ChatController controller;
  final Conversation conversation;
  final Message message;
  final bool showDate;
  final bool showSender;
  final VoidCallback onLongPress;
  final VoidCallback onOpenImage;
  final VoidCallback onOpenFile;
  final VoidCallback onDownload;
  final VoidCallback onRetryDownload;

  const _MessageRow({
    required this.controller,
    required this.conversation,
    required this.message,
    required this.showDate,
    required this.showSender,
    required this.onLongPress,
    required this.onOpenImage,
    required this.onOpenFile,
    required this.onDownload,
    required this.onRetryDownload,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    if (message.kind == MessageKind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            if (showDate) _DateChip(time: message.sentAt, bottom: 8),
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Text(
                  message.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: c.muted, height: 1.35),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final mine = message.mine;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;
    final bubbleColor = mine ? c.bubbleOut : c.bubbleIn;
    final textColor = mine ? c.onAccent : c.text;

    final content = Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showDate) _DateChip(time: message.sentAt, bottom: 8),
        if (showSender)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Text(
              message.senderName.isEmpty
                  ? controller.peerName(message.senderId)
                  : message.senderName,
              style: TextStyle(
                fontSize: 11,
                color: c.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Row(
          mainAxisAlignment:
              mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine && conversation.kind == ConvKind.group) ...[
              PeerAvatar(
                name: message.senderName,
                status: Presence.offline,
                showStatus: false,
                size: 30,
              ),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  decoration: BoxDecoration(
                    color: message.recalled ? c.panel : bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(mine ? 16 : 5),
                      bottomRight: Radius.circular(mine ? 5 : 16),
                    ),
                    border: message.recalled
                        ? Border.all(color: c.border)
                        : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _body(context, c, textColor),
                ),
              ),
            ),
            if (mine && conversation.kind == ConvKind.direct) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Icon(
                  message.read
                      ? Icons.done_all
                      : message.delivered
                          ? Icons.done_all
                          : Icons.done,
                  size: 14,
                  color: message.read ? c.accent : c.faint,
                ),
              ),
            ],
          ],
        ),
        Padding(
          padding: EdgeInsets.only(
            top: 3,
            left: mine ? 0 : 4,
            right: mine ? 2 : 0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatClock(message.sentAt),
                style: TextStyle(fontSize: 9.5, color: c.faint),
              ),
              if (message.file != null &&
                  message.file!.size > 0 &&
                  message.kind != MessageKind.text) ...[
                const SizedBox(width: 5),
                Text(
                  humanSize(message.file!.size),
                  style: TextStyle(fontSize: 9.5, color: c.faint),
                ),
              ],
            ],
          ),
        ),
        if (mine && message.file != null)
          _SendStatus(controller: controller, message: message),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(
        top: 3,
        bottom: 3,
        left: mine ? 44 : 0,
        right: mine ? 0 : 44,
      ),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Flexible(child: content)],
      ),
    );
  }

  Widget _body(BuildContext context, AppColors c, Color textColor) {
    if (message.recalled) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          L10n.instance.tr('chat.message_unsent'),
          style: TextStyle(fontSize: 12, color: c.faint, fontStyle: FontStyle.italic),
        ),
      );
    }
    final file = message.file;
    if (message.kind == MessageKind.image && file != null) {
      return _ImageBody(
        controller: controller,
        message: message,
        onOpen: onOpenImage,
        onDownload: onDownload,
      );
    }
    if (message.kind == MessageKind.file && file != null) {
      return _FileBody(
        controller: controller,
        message: message,
        onOpen: onOpenFile,
        onDownload: onDownload,
        textColor: textColor,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        message.text,
        style: TextStyle(fontSize: 14.5, color: textColor, height: 1.38),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final DateTime time;
  final double bottom;

  const _DateChip({required this.time, this.bottom = 0});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final now = DateTime.now();
    String label;
    if (sameDay(time, now)) {
      label = L10n.instance.tr('ui.today');
    } else if (sameDay(time, now.subtract(const Duration(days: 1)))) {
      label = L10n.instance.tr('ui.yesterday');
    } else if (time.year == now.year) {
      label = trf('ui.arg_0___arg_1_2', [time.month, time.day]);
    } else {
      label = trf('ui.arg_0___arg_1___arg_2_2', [time.year, time.month, time.day]);
    }
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 10, color: c.faint),
          ),
        ),
      ),
    );
  }
}

class _ImageBody extends StatelessWidget {
  final ChatController controller;
  final Message message;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  const _ImageBody({
    required this.controller,
    required this.message,
    required this.onOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final file = message.file!;
    final download = controller.downloads[message.id];
    final path = file.path;
    final ready = path.isNotEmpty && File(path).existsSync();
    final size = _bubbleSize(file);
    if (ready) {
      return GestureDetector(
        onTap: onOpen,
        child: Hero(
          tag: 'img-${message.id}',
          child: Image.file(
            File(path),
            width: size.width,
            height: size.height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(c, file),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onDownload,
      child: SizedBox(
        width: size.width,
        height: size.height.clamp(120, 240),
        child: Center(
          child: _placeholder(c, file, download: download),
        ),
      ),
    );
  }

  Size _bubbleSize(FileMeta file) {
    if (file.width > 0 && file.height > 0) {
      final width = file.width.toDouble().clamp(120.0, 280.0);
      final height = width * file.height / file.width;
      return Size(width, height.clamp(100.0, 320.0));
    }
    return const Size(220, 160);
  }

  Widget _placeholder(AppColors c, FileMeta file, {DownloadState? download}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.image_outlined, size: 34, color: c.faint),
        const SizedBox(height: 6),
        Text(
          download?.error.isNotEmpty == true
              ? L10n.instance.tr('ui.download_failed_tap_to_retry')
              : L10n.instance.tr('image.tap_to_download_image'),
          style: TextStyle(fontSize: 11, color: c.muted),
        ),
        if (download != null && download.working) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              value: download.value,
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ],
    );
  }
}

class _FileBody extends StatelessWidget {
  final ChatController controller;
  final Message message;
  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final Color textColor;

  const _FileBody({
    required this.controller,
    required this.message,
    required this.onOpen,
    required this.onDownload,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final file = message.file!;
    final download = controller.downloads[message.id];
    final send = controller.sends[message.id];
    final path = file.path;
    final ready = path.isNotEmpty && File(path).existsSync();
    final busy = download?.working == true || send?.working == true;
    final progress = download?.working == true
        ? download!.value
        : (send != null && send.working ? send.value : 0.0);
    final error = download?.error.isNotEmpty == true
        ? download!.error
        : send?.error.isNotEmpty == true
            ? send!.error
            : '';

    return InkWell(
      onTap: ready
          ? onOpen
          : (message.mine ? null : onDownload),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconFor(file),
                    size: 21,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 210),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ready
                            ? trf('ui.tap_to_open__arg_0', [humanSize(file.size)])
                            : busy
                                ? '${(progress * 100).round()}% · ${humanSize(file.size)}'
                                : error.isNotEmpty
                                    ? error
                                    : message.mine
                                        ? L10n.instance.tr('ui.waiting_for_the_other_side_to_download')
                                        : trf('ui.tap_to_download__arg_0', [humanSize(file.size)]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: textColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  ready
                      ? Icons.open_in_new
                      : message.mine
                          ? Icons.upload_outlined
                          : Icons.download_outlined,
                  size: 18,
                  color: textColor.withValues(alpha: 0.75),
                ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: textColor.withValues(alpha: 0.18),
                  color: textColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconFor(FileMeta file) {
    final mime = file.mime.toLowerCase();
    if (mime.startsWith('video/')) return Icons.videocam_outlined;
    if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.startsWith('text/')) return Icons.description_outlined;
    if (mime.contains('zip') || mime.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}

class _SendStatus extends StatelessWidget {
  final ChatController controller;
  final Message message;

  const _SendStatus({required this.controller, required this.message});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final send = controller.sends[message.id];
    if (send == null || !send.working || send.total <= 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 3, right: 2),
      child: SizedBox(
        width: 170,
        child: LinearProgressIndicator(
          value: send.value,
          minHeight: 2,
          backgroundColor: c.border,
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final ChatController controller;
  final Conversation conversation;
  final TextEditingController input;
  final bool canSend;
  final VoidCallback? onSend;
  final VoidCallback onAttach;
  final VoidCallback onShareLink;

  const _Composer({
    required this.controller,
    required this.conversation,
    required this.input,
    required this.canSend,
    required this.onSend,
    required this.onAttach,
    required this.onShareLink,
  });

  Widget _buildInput(AppColors c) {
    return TextField(
      controller: input,
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.newline,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration(
        hintText: L10n.instance.tr('chat.send_message'),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: c.accent, width: 1.3),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Container(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: L10n.instance.tr('ui.add_attachment'),
            onPressed: onAttach,
            icon: const Icon(Icons.add_circle_outline),
            color: c.muted,
          ),
          IconButton(
            tooltip: L10n.instance.tr('share.send_share_link'),
            onPressed: onShareLink,
            icon: const Icon(Icons.link),
            color: c.muted,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: AppPlatform.isDesktop
                ? CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): () {
                        if (canSend) onSend?.call();
                      },
                    },
                    child: _buildInput(c),
                  )
                : _buildInput(c),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 42,
            height: 42,
            child: IconButton.filled(
              tooltip: L10n.instance.tr('ui.send'),
              onPressed: canSend ? onSend : null,
              style: IconButton.styleFrom(
                backgroundColor: canSend ? c.accent : c.panel,
                foregroundColor: canSend ? c.onAccent : c.faint,
              ),
              icon: const Icon(Icons.arrow_upward, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
