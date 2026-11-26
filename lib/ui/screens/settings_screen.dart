import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/helpers.dart';
import '../../core/i18n.dart';
import '../../core/models.dart';
import '../../state/chat_controller.dart';
import '../../state/rss_controller.dart';
import '../../state/update_view_model.dart';
import '../adaptive.dart';
import '../dialogs/dialogs.dart';
import '../dialogs/update_dialog.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ChatController>().refreshDbStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ChatController>();
    final colors = appColors(context);
    final stats = c.dbStats;

    return Scaffold(
      appBar: DchatAppBar(title: Text(L10n.instance.tr('设置'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _ProfileCard(controller: c),
          const SizedBox(height: 14),
          SectionCard(
            title: L10n.instance.tr('外观'),
            child: Column(
              children: [
                _ChoiceRow(
                  label: L10n.instance.tr('主题'),
                  child: AdaptiveSegmentedControl(
                    segments: [
                      AdaptiveSegment('system', L10n.instance.tr('跟随系统')),
                      AdaptiveSegment('light', L10n.instance.tr('浅色')),
                      AdaptiveSegment('dark', L10n.instance.tr('深色')),
                    ],
                    selected: c.settings.appearance,
                    onChanged: c.setAppearance,
                  ),
                ),
                const SizedBox(height: 10),
                _ChoiceRow(
                  label: L10n.instance.tr('语言'),
                  child: AdaptiveSegmentedControl(
                    segments: [
                      AdaptiveSegment('system', L10n.instance.tr('系统')),
                      AdaptiveSegment('zh', L10n.instance.tr('中文')),
                      AdaptiveSegment('en', 'English'),
                    ],
                    selected: c.settings.language,
                    onChanged: c.setLanguage,
                  ),
                ),
                const Divider(height: 24),
                _SwitchRow(
                  label: L10n.instance.tr('触感反馈'),
                  subtitle: L10n.instance.tr('操作时使用轻微振动'),
                  value: c.settings.haptics,
                  onChanged: c.setHaptics,
                ),
                _SwitchRow(
                  label: L10n.instance.tr('保持屏幕常亮'),
                  subtitle: L10n.instance.tr('在应用使用期间防止屏幕自动熄灭'),
                  value: c.settings.keepAwake,
                  onChanged: c.setKeepAwake,
                ),
                _SwitchRow(
                  label: L10n.instance.tr('启用截图'),
                  subtitle: L10n.instance.tr('在聊天工具栏中使用截图按钮'),
                  value: c.settings.screenshotEnabled,
                  onChanged: c.setScreenshotEnabled,
                ),
                InfoRow(
                  label: L10n.instance.tr('保存目录'),
                  value: c.settings.screenshotDir.isEmpty
                      ? L10n.instance.tr('未设置')
                      : c.settings.screenshotDir,
                  trailing: TextButton(
                    onPressed: () => _pickScreenshotDir(context, c),
                    child: Text(L10n.instance.tr('更改')),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: L10n.instance.tr('消息'),
            child: Column(
              children: [
                _SwitchRow(
                  label: L10n.instance.tr('通知'),
                  subtitle: L10n.instance.tr('收到新消息时显示系统通知'),
                  value: c.settings.notifications,
                  onChanged: c.setNotifications,
                ),
                _SwitchRow(
                  label: L10n.instance.tr('通知内容预览'),
                  subtitle: L10n.instance.tr('在通知中显示消息内容'),
                  value: c.settings.notifyPreview,
                  onChanged: c.setNotifyPreview,
                ),
                _SwitchRow(
                  label: L10n.instance.tr('自动下载图片'),
                  subtitle: L10n.instance.tr('打开聊天时自动获取图片'),
                  value: c.settings.autoDownloadImages,
                  onChanged: c.setAutoDownloadImages,
                ),
                const Divider(height: 20),
                InfoRow(
                  label: L10n.instance.tr('下载目录'),
                  value: c.settings.downloadDir,
                  trailing: TextButton(
                    onPressed: () => _pickDownloadDir(context, c),
                    child: Text(L10n.instance.tr('更改')),
                  ),
                ),
              ],
            ),
          ),
          if (AppPlatform.isDesktop) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: L10n.instance.tr('桌面'),
              child: Column(
                children: [
                  _SwitchRow(
                    label: L10n.instance.tr('关闭窗口时留在托盘'),
                    subtitle: L10n.instance.tr('点击关闭后继续在后台接收消息'),
                    value: c.settings.closeToTray,
                    onChanged: c.setCloseToTray,
                  ),
                  _SwitchRow(
                    label: L10n.instance.tr('启动时自动共享'),
                    subtitle: L10n.instance.tr('打开应用后自动开启文件共享'),
                    value: c.settings.shareOnStart,
                    onChanged: c.setShareOnStart,
                  ),
                  InfoRow(
                    label: L10n.instance.tr('共享目录'),
                    value: c.settings.shareDir.isEmpty
                        ? L10n.instance.tr('未设置')
                        : c.settings.shareDir,
                    trailing: TextButton(
                      onPressed: () => _pickShareDir(context, c),
                      child: Text(L10n.instance.tr('更改')),
                    ),
                  ),
                  InfoRow(
                    label: L10n.instance.tr('上传目录'),
                    value: c.settings.uploadDir.isEmpty
                        ? L10n.instance.tr('未设置')
                        : c.settings.uploadDir,
                    trailing: TextButton(
                      onPressed: () => _pickUploadDir(context, c),
                      child: Text(L10n.instance.tr('更改')),
                    ),
                  ),
                  InfoRow(
                    label: L10n.instance.tr('数据目录'),
                    value: c.dataDir,
                    trailing: TextButton(
                      onPressed: () => _openDataDir(context, c),
                      child: Text(L10n.instance.tr('打开')),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: L10n.instance.tr('网络'),
            child: Column(
              children: [
                _SwitchRow(
                  label: L10n.instance.tr('自动发现'),
                  subtitle: L10n.instance.tr('通过 UDP 广播寻找局域网设备'),
                  value: c.settings.discovery,
                  onChanged: c.setDiscovery,
                ),
                InfoRow(
                  label: L10n.instance.tr('本机地址'),
                  value: c.localIps.isEmpty ? L10n.instance.tr('未知') : c.localIps.join(', '),
                ),
                InfoRow(
                  label: L10n.instance.tr('聊天端口'),
                  value: '${c.settings.port}',
                  trailing: TextButton(
                    onPressed: () => _editPort(
                      context,
                      c,
                      title: L10n.instance.tr('修改聊天端口'),
                      initial: c.settings.port,
                      onSaved: (port) async {
                        c.settings.port = port;
                        await c.restartNetwork();
                      },
                    ),
                    child: Text(L10n.instance.tr('修改')),
                  ),
                ),
                InfoRow(
                  label: L10n.instance.tr('传输端口'),
                  value: '${c.settings.transferPort}',
                  trailing: TextButton(
                    onPressed: () => _editPort(
                      context,
                      c,
                      title: L10n.instance.tr('修改传输端口'),
                      initial: c.settings.transferPort,
                      onSaved: (port) async {
                        c.settings.transferPort = port;
                        await c.restartNetwork();
                      },
                    ),
                    child: Text(L10n.instance.tr('修改')),
                  ),
                ),
                InfoRow(
                  label: L10n.instance.tr('共享端口'),
                  value: '${c.settings.sharePort}',
                  trailing: TextButton(
                    onPressed: () => _editPort(
                      context,
                      c,
                      title: L10n.instance.tr('修改共享端口'),
                      initial: c.settings.sharePort,
                      onSaved: c.setSharePort,
                    ),
                    child: Text(L10n.instance.tr('修改')),
                  ),
                ),
                InfoRow(
                  label: L10n.instance.tr('文件传输服务'),
                  value: (c.transfer?.running ?? false) ? L10n.instance.tr('运行中') : L10n.instance.tr('未运行'),
                ),
                InfoRow(
                  label: L10n.instance.tr('文件共享服务'),
                  value: c.shareRunning ? L10n.instance.tr('运行中') : L10n.instance.tr('已停止'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: L10n.instance.tr('数据'),
            child: Column(
              children: [
                InfoRow(
                  label: L10n.instance.tr('会话'),
                  value: '${stats?.conversations ?? 0}',
                ),
                InfoRow(
                  label: L10n.instance.tr('消息'),
                  value: '${stats?.messages ?? 0}',
                ),
                InfoRow(
                  label: L10n.instance.tr('数据库大小'),
                  value: humanSize(stats?.bytes ?? 0),
                ),
                if (stats != null)
                  InfoRow(label: L10n.instance.tr('数据库位置'), value: stats.path),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_fix_high_outlined,
                      color: colors.muted),
                  title: Text(L10n.instance.tr('整理数据库')),
                  subtitle: Text(L10n.instance.tr('回收空间并优化聊天记录')),
                  onTap: c.vacuumDatabase,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cleaning_services_outlined,
                      color: colors.danger),
                  title: Text(
                    L10n.instance.tr('清空所有聊天记录'),
                    style: TextStyle(color: colors.danger),
                  ),
                  subtitle: Text(L10n.instance.tr('保留联系人和设置')),
                  onTap: () async {
                    if (await confirmAction(
                      context,
                      title: L10n.instance.tr('清空所有聊天记录？'),
                      message: L10n.instance.tr('所有本机消息都会删除，无法恢复。'),
                      confirm: L10n.instance.tr('清空'),
                      destructive: true,
                    )) {
                      c.clearAllHistory();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _NewsSection(),
          const SizedBox(height: 14),
          SectionCard(
            title: L10n.instance.tr('关于'),
            child: Column(
              children: [
                InfoRow(label: L10n.instance.tr('应用'), value: 'dchat'),
                InfoRow(label: L10n.instance.tr('版本'), value: c.version),
                InfoRow(label: L10n.instance.tr('身份 ID'), value: c.profile.id),
                InfoRow(label: L10n.instance.tr('协议版本'), value: 'zchat v1'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final update = context.read<UpdateViewModel>();
                          update.reset();
                          update.check(localVersion: c.version);
                          showUpdateDialog(context, update);
                        },
                        icon: const Icon(Icons.system_update_alt, size: 17),
                        label: Text(L10n.instance.tr('检查更新')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse('https://github.com/zwdart/dchat'),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.public, size: 17),
                        label: Text(L10n.instance.tr('项目主页')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  L10n.instance.tr('消息和文件只在局域网设备之间传输，不经过任何服务器。'),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickShareDir(BuildContext context, ChatController c) async {
    try {
      // ignore: deprecated_member_use
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: L10n.instance.tr('选择共享目录'),
        initialDirectory:
            c.settings.shareDir.isEmpty ? null : c.settings.shareDir,
      );
      if (dir == null || dir.isEmpty) return;
      await c.setShareDirs(dir, c.settings.uploadDir);
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('无法选择目录：%s', ['$e']));
    }
  }

  Future<void> _pickUploadDir(BuildContext context, ChatController c) async {
    try {
      // ignore: deprecated_member_use
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: L10n.instance.tr('选择上传目录'),
        initialDirectory:
            c.settings.uploadDir.isEmpty ? null : c.settings.uploadDir,
      );
      if (dir == null || dir.isEmpty) return;
      await c.setShareDirs(c.settings.shareDir, dir);
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('无法选择目录：%s', ['$e']));
    }
  }

  Future<void> _openDataDir(BuildContext context, ChatController c) async {
    try {
      final ok = await launchUrl(
        Uri.file(c.dataDir),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        showAppSnack(context, c.dataDir);
      }
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('无法打开目录：%s', ['$e']));
    }
  }

  Future<void> _pickScreenshotDir(
    BuildContext context,
    ChatController c,
  ) async {
    try {
      // ignore: deprecated_member_use
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: L10n.instance.tr('选择截图保存目录'),
        initialDirectory:
            c.settings.screenshotDir.isEmpty ? null : c.settings.screenshotDir,
      );
      if (dir == null || dir.isEmpty) return;
      await c.setSettings((s) => s.screenshotDir = dir);
      if (context.mounted) {
        showAppSnack(context, L10n.instance.tr('截图保存目录已更新'));
      }
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('无法选择目录：%s', ['$e']));
    }
  }

  Future<void> _pickDownloadDir(
    BuildContext context,
    ChatController c,
  ) async {
    try {
      // ignore: deprecated_member_use
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: L10n.instance.tr('选择下载目录'),
        initialDirectory:
            c.settings.downloadDir.isEmpty ? null : c.settings.downloadDir,
      );
      if (dir == null || dir.isEmpty) return;
      await c.setDownloadDir(dir);
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('无法选择目录：%s', ['$e']));
    }
  }

  Future<void> _editPort(
    BuildContext context,
    ChatController c, {
    required String title,
    required int initial,
    required Future<void> Function(int) onSaved,
  }) async {
    final value = await promptText(
      context,
      title: title,
      label: L10n.instance.tr('端口（1024 - 65535）'),
      initial: '$initial',
    );
    if (value == null) return;
    final port = int.tryParse(value);
    if (port == null || port < 1024 || port > 65535) {
      if (context.mounted) showAppSnack(context, L10n.instance.tr('请输入有效端口'));
      return;
    }
    await onSaved(port);
  }
}

class _ProfileCard extends StatelessWidget {
  final ChatController controller;

  const _ProfileCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.accent.withValues(alpha: 0.13),
            c.panel,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _editAvatar(context),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PeerAvatar(
                      name: controller.profile.name,
                      avatar: controller.profile.avatar,
                      status: controller.profile.status,
                      size: 64,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 23,
                        height: 23,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.background,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.photo_camera,
                          size: 12,
                          color: c.onAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      controller.profile.signature.isEmpty
                          ? L10n.instance.tr('点击编辑个人信息')
                          : controller.profile.signature,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final name = await promptText(
                      context,
                      title: L10n.instance.tr('修改名称'),
                      label: L10n.instance.tr('名称'),
                      initial: controller.profile.name,
                    );
                    if (name == null || name.isEmpty) return;
                    await controller.updateProfile(name: name);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(L10n.instance.tr('名称')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final signature = await promptText(
                      context,
                      title: L10n.instance.tr('修改签名'),
                      label: L10n.instance.tr('个性签名'),
                      initial: controller.profile.signature,
                      multiline: true,
                      maxLines: 3,
                    );
                    if (signature == null) return;
                    await controller.updateProfile(signature: signature);
                  },
                  icon: const Icon(Icons.notes, size: 17),
                  label: Text(L10n.instance.tr('签名')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                L10n.instance.tr('状态'),
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Presence>(
                    isExpanded: true,
                    value: controller.profile.status,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      for (final p in presenceOptions)
                        DropdownMenuItem(
                          value: p,
                          child: Row(
                            children: [
                              StatusDot(status: p, size: 9),
                              const SizedBox(width: 8),
                              Text(L10n.instance.tr(presenceLabelKey(p))),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) controller.setStatus(value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editAvatar(BuildContext context) async {
    final action = await showAdaptiveActionSheet<String>(
      context,
      title: L10n.instance.tr('修改头像'),
      actions: [
        AdaptiveSheetAction(
          value: 'gallery',
          icon: Icons.photo_library_outlined,
          label: AppPlatform.isDesktop
              ? L10n.instance.tr('选择图片')
              : L10n.instance.tr('从相册选择'),
        ),
        if (AppPlatform.isMobile)
          AdaptiveSheetAction(
            value: 'camera',
            icon: Icons.photo_camera_outlined,
            label: L10n.instance.tr('拍照'),
          ),
        if (controller.profile.avatar.isNotEmpty)
          AdaptiveSheetAction(
            value: 'clear',
            icon: Icons.delete_outline,
            label: L10n.instance.tr('移除头像'),
            destructive: true,
          ),
      ],
    );
    if (action == null || !context.mounted) return;
    if (action == 'clear') {
      await controller.clearAvatar();
      return;
    }
    try {
      if (action == 'gallery' && AppPlatform.isDesktop) {
        final result = await FilePicker.pickFiles(type: FileType.image);
        final path = result.isEmpty ? null : result.first.path;
        if (path == null) return;
        final bytes = await File(path).readAsBytes();
        await controller.setAvatarBytes(bytes);
        return;
      }
      final picker = ImagePicker();
      final XFile? image;
      if (action == 'camera') {
        image = await picker.pickImage(source: ImageSource.camera);
      } else {
        image = await picker.pickImage(source: ImageSource.gallery);
      }
      if (image == null) return;
      final bytes = await File(image.path).readAsBytes();
      await controller.setAvatarBytes(bytes);
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('无法更新头像：%s', ['$e']));
    }
  }
}

/// 资讯（本地订阅）设置：同步节奏、阅读排版与备份。
class _NewsSection extends StatelessWidget {
  const _NewsSection();

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssController>();
    final settings = rss.settings;
    final colors = appColors(context);
    final backup = rss.store.lastBackupAt;
    return SectionCard(
      title: L10n.instance.tr('资讯'),
      subtitle: L10n.instance.tr('订阅源与文章只保存在本机'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SwitchRow(
            label: L10n.instance.tr('自动同步'),
            subtitle: L10n.instance.tr('按固定间隔抓取全部订阅源'),
            value: settings.autoSync,
            onChanged: (value) => rss.update((s) => s.autoSync = value),
          ),
          _ChoiceRow(
            label: L10n.instance.tr('同步间隔'),
            child: AdaptiveSegmentedControl(
              segments: [
                AdaptiveSegment('10', L10n.instance.tr('10 分钟')),
                AdaptiveSegment('30', L10n.instance.tr('30 分钟')),
                AdaptiveSegment('60', L10n.instance.tr('1 小时')),
                AdaptiveSegment('360', L10n.instance.tr('6 小时')),
              ],
              selected: '${settings.syncIntervalMinutes}',
              onChanged: (value) => rss.update(
                (s) => s.syncIntervalMinutes = int.tryParse(value) ?? 30,
              ),
            ),
          ),
          const Divider(height: 24),
          _SwitchRow(
            label: L10n.instance.tr('打开即标记已读'),
            value: settings.markReadOnOpen,
            onChanged: (value) => rss.update((s) => s.markReadOnOpen = value),
          ),
          _SwitchRow(
            label: L10n.instance.tr('显示图片'),
            value: settings.showImages,
            onChanged: (value) => rss.update((s) => s.showImages = value),
          ),
          _SwitchRow(
            label: L10n.instance.tr('最新文章优先'),
            subtitle: L10n.instance.tr('关闭后按发布时间从旧到新排列'),
            value: settings.newestFirst,
            onChanged: (value) => rss.update((s) => s.newestFirst = value),
          ),
          _ChoiceRow(
            label: L10n.instance.tr('正文字号'),
            child: AdaptiveSegmentedControl(
              segments: [
                AdaptiveSegment('15', L10n.instance.tr('小')),
                AdaptiveSegment('17', L10n.instance.tr('标准')),
                AdaptiveSegment('19', L10n.instance.tr('大')),
                AdaptiveSegment('22', L10n.instance.tr('特大')),
              ],
              selected: '${settings.fontSize}',
              onChanged: (value) =>
                  rss.update((s) => s.fontSize = int.tryParse(value) ?? 17),
            ),
          ),
          _ChoiceRow(
            label: L10n.instance.tr('正文宽度'),
            child: AdaptiveSegmentedControl(
              segments: [
                AdaptiveSegment('620', L10n.instance.tr('窄')),
                AdaptiveSegment('720', L10n.instance.tr('标准')),
                AdaptiveSegment('860', L10n.instance.tr('宽')),
              ],
              selected: '${settings.contentWidth}',
              onChanged: (value) =>
                  rss.update((s) => s.contentWidth = int.tryParse(value) ?? 720),
            ),
          ),
          const Divider(height: 24),
          _SwitchRow(
            label: L10n.instance.tr('自动备份订阅'),
            subtitle: L10n.instance.tr('同步后导出一份 OPML 到本机备份目录'),
            value: settings.autoBackup,
            onChanged: (value) => rss.update((s) => s.autoBackup = value),
          ),
          _ChoiceRow(
            label: L10n.instance.tr('文章保留'),
            child: AdaptiveSegmentedControl(
              segments: [
                AdaptiveSegment('0', L10n.instance.tr('不限')),
                AdaptiveSegment('30', L10n.instance.tr('30 天')),
                AdaptiveSegment('90', L10n.instance.tr('90 天')),
                AdaptiveSegment('180', L10n.instance.tr('180 天')),
              ],
              selected: '${settings.keepDays}',
              onChanged: (value) =>
                  rss.update((s) => s.keepDays = int.tryParse(value) ?? 0),
            ),
          ),
          InfoRow(
            label: L10n.instance.tr('上次备份'),
            value: backup == null
                ? L10n.instance.tr('从未备份')
                : '${backup.month}/${backup.day} ${formatClock(backup)}',
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.backup_outlined, color: colors.muted),
            title: Text(L10n.instance.tr('立即备份订阅')),
            subtitle: Text(L10n.instance.tr('把当前订阅导出为 OPML')),
            onTap: () async {
              await rss.backupNow();
              if (!context.mounted) return;
              showAppSnack(context, L10n.instance.tr('备份已写入本地目录'));
            },
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _ChoiceRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 11.5, color: c.muted),
                  ),
                ],
              ],
            ),
          ),
          AdaptiveSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
