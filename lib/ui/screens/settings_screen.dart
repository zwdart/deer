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
      appBar: DchatAppBar(title: Text(L10n.instance.tr('settings.settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _ProfileCard(controller: c),
          const SizedBox(height: 14),
          SectionCard(
            title: L10n.instance.tr('ui.appearance'),
            child: Column(
              children: [
                _ChoiceRow(
                  label: L10n.instance.tr('settings.theme'),
                  child: AdaptiveSegmentedControl(
                    segments: [
                      AdaptiveSegment('system', L10n.instance.tr('settings.use_system_setting')),
                      AdaptiveSegment('light', L10n.instance.tr('ui.light')),
                      AdaptiveSegment('dark', L10n.instance.tr('ui.dark')),
                    ],
                    selected: c.settings.appearance,
                    onChanged: c.setAppearance,
                  ),
                ),
                const SizedBox(height: 10),
                _ChoiceRow(
                  label: L10n.instance.tr('settings.language'),
                  child: AdaptiveSegmentedControl(
                    segments: [
                      AdaptiveSegment('system', L10n.instance.tr('ui.system')),
                      AdaptiveSegment('zh', L10n.instance.tr('ui.chinese')),
                      AdaptiveSegment('en', 'English'),
                    ],
                    selected: c.settings.language,
                    onChanged: c.setLanguage,
                  ),
                ),
                const Divider(height: 24),
                _SwitchRow(
                  label: L10n.instance.tr('ui.haptic_feedback'),
                  subtitle: L10n.instance.tr('ui.use_light_vibration_for_actions'),
                  value: c.settings.haptics,
                  onChanged: c.setHaptics,
                ),
                _SwitchRow(
                  label: L10n.instance.tr('ui.keep_the_screen_awake'),
                  subtitle: L10n.instance.tr('settings.prevent_the_screen_from_sleeping_while_the_app_is_in_use'),
                  value: c.settings.keepAwake,
                  onChanged: c.setKeepAwake,
                ),
                _SwitchRow(
                  label: L10n.instance.tr('image.enable_screenshots'),
                  subtitle: L10n.instance.tr('image.use_the_screenshot_button_in_the_chat_toolbar'),
                  value: c.settings.screenshotEnabled,
                  onChanged: c.setScreenshotEnabled,
                ),
                InfoRow(
                  label: L10n.instance.tr('ui.save_folder'),
                  value: c.settings.screenshotDir.isEmpty
                      ? L10n.instance.tr('settings.not_set')
                      : c.settings.screenshotDir,
                  trailing: TextButton(
                    onPressed: () => _pickScreenshotDir(context, c),
                    child: Text(L10n.instance.tr('ui.change')),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: L10n.instance.tr('chat.messages_2'),
            child: Column(
              children: [
                _SwitchRow(
                  label: L10n.instance.tr('settings.notifications'),
                  subtitle: L10n.instance.tr('chat.show_system_notifications_for_new_messages'),
                  value: c.settings.notifications,
                  onChanged: c.setNotifications,
                ),
                _SwitchRow(
                  label: L10n.instance.tr('settings.notification_preview'),
                  subtitle: L10n.instance.tr('chat.show_message_content_in_notifications'),
                  value: c.settings.notifyPreview,
                  onChanged: c.setNotifyPreview,
                ),
                _SwitchRow(
                  label: L10n.instance.tr('image.auto_download_images'),
                  subtitle: L10n.instance.tr('image.automatically_fetch_images_when_opening_a_chat'),
                  value: c.settings.autoDownloadImages,
                  onChanged: c.setAutoDownloadImages,
                ),
                const Divider(height: 20),
                InfoRow(
                  label: L10n.instance.tr('share.downloads'),
                  value: c.settings.downloadDir,
                  trailing: TextButton(
                    onPressed: () => _pickDownloadDir(context, c),
                    child: Text(L10n.instance.tr('ui.change')),
                  ),
                ),
              ],
            ),
          ),
          if (AppPlatform.isDesktop) ...[
            const SizedBox(height: 14),
            SectionCard(
              title: L10n.instance.tr('ui.desktop'),
              child: Column(
                children: [
                  _SwitchRow(
                    label: L10n.instance.tr('settings.keep_running_in_the_tray_when_the_window_closes'),
                    subtitle: L10n.instance.tr('chat.keep_receiving_messages_in_the_background_after_closing'),
                    value: c.settings.closeToTray,
                    onChanged: c.setCloseToTray,
                  ),
                  _SwitchRow(
                    label: L10n.instance.tr('share.share_automatically_on_startup'),
                    subtitle: L10n.instance.tr('share.automatically_start_file_sharing_when_the_app_opens'),
                    value: c.settings.shareOnStart,
                    onChanged: c.setShareOnStart,
                  ),
                  InfoRow(
                    label: L10n.instance.tr('share.shared_folder'),
                    value: c.settings.shareDir.isEmpty
                        ? L10n.instance.tr('settings.not_set')
                        : c.settings.shareDir,
                    trailing: TextButton(
                      onPressed: () => _pickShareDir(context, c),
                      child: Text(L10n.instance.tr('ui.change')),
                    ),
                  ),
                  InfoRow(
                    label: L10n.instance.tr('share.upload_folder'),
                    value: c.settings.uploadDir.isEmpty
                        ? L10n.instance.tr('settings.not_set')
                        : c.settings.uploadDir,
                    trailing: TextButton(
                      onPressed: () => _pickUploadDir(context, c),
                      child: Text(L10n.instance.tr('ui.change')),
                    ),
                  ),
                  InfoRow(
                    label: L10n.instance.tr('ui.data_folder'),
                    value: c.dataDir,
                    trailing: TextButton(
                      onPressed: () => _openDataDir(context, c),
                      child: Text(L10n.instance.tr('ui.open')),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: L10n.instance.tr('network.network'),
            child: Column(
              children: [
                _SwitchRow(
                  label: L10n.instance.tr('device.auto_discovery'),
                  subtitle: L10n.instance.tr('device.find_lan_devices_via_udp_broadcast'),
                  value: c.settings.discovery,
                  onChanged: c.setDiscovery,
                ),
                InfoRow(
                  label: L10n.instance.tr('device.local_address'),
                  value: c.localIps.isEmpty ? L10n.instance.tr('ui.unknown') : c.localIps.join(', '),
                ),
                InfoRow(
                  label: L10n.instance.tr('chat.chat_port'),
                  value: '${c.settings.port}',
                  trailing: TextButton(
                    onPressed: () => _editPort(
                      context,
                      c,
                      title: L10n.instance.tr('chat.change_chat_port'),
                      initial: c.settings.port,
                      onSaved: (port) async {
                        c.settings.port = port;
                        await c.restartNetwork();
                      },
                    ),
                    child: Text(L10n.instance.tr('ui.change_2')),
                  ),
                ),
                InfoRow(
                  label: L10n.instance.tr('device.transfer_port'),
                  value: '${c.settings.transferPort}',
                  trailing: TextButton(
                    onPressed: () => _editPort(
                      context,
                      c,
                      title: L10n.instance.tr('device.change_transfer_port'),
                      initial: c.settings.transferPort,
                      onSaved: (port) async {
                        c.settings.transferPort = port;
                        await c.restartNetwork();
                      },
                    ),
                    child: Text(L10n.instance.tr('ui.change_2')),
                  ),
                ),
                InfoRow(
                  label: L10n.instance.tr('share.share_port'),
                  value: '${c.settings.sharePort}',
                  trailing: TextButton(
                    onPressed: () => _editPort(
                      context,
                      c,
                      title: L10n.instance.tr('share.change_sharing_port'),
                      initial: c.settings.sharePort,
                      onSaved: c.setSharePort,
                    ),
                    child: Text(L10n.instance.tr('ui.change_2')),
                  ),
                ),
                InfoRow(
                  label: L10n.instance.tr('ui.file_transfer_service'),
                  value: (c.transfer?.running ?? false) ? L10n.instance.tr('ui.running') : L10n.instance.tr('ui.not_running'),
                ),
                InfoRow(
                  label: L10n.instance.tr('share.file_sharing_service'),
                  value: c.shareRunning ? L10n.instance.tr('ui.running') : L10n.instance.tr('ui.stopped'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: L10n.instance.tr('ui.data'),
            child: Column(
              children: [
                InfoRow(
                  label: L10n.instance.tr('chat.chats'),
                  value: '${stats?.conversations ?? 0}',
                ),
                InfoRow(
                  label: L10n.instance.tr('chat.messages_2'),
                  value: '${stats?.messages ?? 0}',
                ),
                InfoRow(
                  label: L10n.instance.tr('ui.database_size'),
                  value: humanSize(stats?.bytes ?? 0),
                ),
                if (stats != null)
                  InfoRow(label: L10n.instance.tr('ui.database_location'), value: stats.path),
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_fix_high_outlined,
                      color: colors.muted),
                  title: Text(L10n.instance.tr('ui.compact_database')),
                  subtitle: Text(L10n.instance.tr('chat.reclaim_space_and_optimize_chat_history')),
                  onTap: c.vacuumDatabase,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cleaning_services_outlined,
                      color: colors.danger),
                  title: Text(
                    L10n.instance.tr('chat.clear_all_chat_history_2'),
                    style: TextStyle(color: colors.danger),
                  ),
                  subtitle: Text(L10n.instance.tr('settings.keep_contacts_and_settings')),
                  onTap: () async {
                    if (await confirmAction(
                      context,
                      title: L10n.instance.tr('chat.clear_all_chat_history_3'),
                      message: L10n.instance.tr('chat.all_messages_on_this_device_will_be_deleted_and_cannot_be_recovered'),
                      confirm: L10n.instance.tr('ui.clear_3'),
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
            title: L10n.instance.tr('system.about'),
            child: Column(
              children: [
                InfoRow(label: L10n.instance.tr('ui.apply'), value: 'dchat'),
                InfoRow(label: L10n.instance.tr('ui.version'), value: c.version),
                InfoRow(label: L10n.instance.tr('ui.identity_id'), value: c.profile.id),
                InfoRow(label: L10n.instance.tr('ui.protocol_version'), value: 'zchat v1'),
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
                        label: Text(L10n.instance.tr('update.check_for_updates')),
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
                        label: Text(L10n.instance.tr('ui.project_page')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  L10n.instance.tr('chat.messages_and_files_travel_only_between_devices_on_your_lan_never_through_a_server'),
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
        dialogTitle: L10n.instance.tr('share.choose_shared_folder'),
        initialDirectory:
            c.settings.shareDir.isEmpty ? null : c.settings.shareDir,
      );
      if (dir == null || dir.isEmpty) return;
      await c.setShareDirs(dir, c.settings.uploadDir);
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('ui.could_not_choose_directory__arg_0', ['$e']));
    }
  }

  Future<void> _pickUploadDir(BuildContext context, ChatController c) async {
    try {
      // ignore: deprecated_member_use
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: L10n.instance.tr('share.choose_upload_folder'),
        initialDirectory:
            c.settings.uploadDir.isEmpty ? null : c.settings.uploadDir,
      );
      if (dir == null || dir.isEmpty) return;
      await c.setShareDirs(c.settings.shareDir, dir);
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('ui.could_not_choose_directory__arg_0', ['$e']));
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
      if (context.mounted) showAppSnack(context, trf('ui.could_not_open_directory__arg_0', ['$e']));
    }
  }

  Future<void> _pickScreenshotDir(
    BuildContext context,
    ChatController c,
  ) async {
    try {
      // ignore: deprecated_member_use
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: L10n.instance.tr('image.choose_screenshot_folder'),
        initialDirectory:
            c.settings.screenshotDir.isEmpty ? null : c.settings.screenshotDir,
      );
      if (dir == null || dir.isEmpty) return;
      await c.setSettings((s) => s.screenshotDir = dir);
      if (context.mounted) {
        showAppSnack(context, L10n.instance.tr('image.screenshot_folder_updated'));
      }
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('ui.could_not_choose_directory__arg_0', ['$e']));
    }
  }

  Future<void> _pickDownloadDir(
    BuildContext context,
    ChatController c,
  ) async {
    try {
      // ignore: deprecated_member_use
      final dir = await FilePicker.getDirectoryPath(
        dialogTitle: L10n.instance.tr('share.choose_download_folder'),
        initialDirectory:
            c.settings.downloadDir.isEmpty ? null : c.settings.downloadDir,
      );
      if (dir == null || dir.isEmpty) return;
      await c.setDownloadDir(dir);
    } catch (e) {
      if (context.mounted) showAppSnack(context, trf('ui.could_not_choose_directory__arg_0', ['$e']));
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
      label: L10n.instance.tr('device.port_1024_65535'),
      initial: '$initial',
    );
    if (value == null) return;
    final port = int.tryParse(value);
    if (port == null || port < 1024 || port > 65535) {
      if (context.mounted) showAppSnack(context, L10n.instance.tr('device.enter_a_valid_port'));
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
                          ? L10n.instance.tr('ui.tap_to_edit_your_profile')
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
                      title: L10n.instance.tr('ui.edit_name'),
                      label: L10n.instance.tr('ui.name'),
                      initial: controller.profile.name,
                    );
                    if (name == null || name.isEmpty) return;
                    await controller.updateProfile(name: name);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(L10n.instance.tr('ui.name')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final signature = await promptText(
                      context,
                      title: L10n.instance.tr('ui.edit_bio'),
                      label: L10n.instance.tr('ui.bio_2'),
                      initial: controller.profile.signature,
                      multiline: true,
                      maxLines: 3,
                    );
                    if (signature == null) return;
                    await controller.updateProfile(signature: signature);
                  },
                  icon: const Icon(Icons.notes, size: 17),
                  label: Text(L10n.instance.tr('ui.bio')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                L10n.instance.tr('ui.status'),
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
      title: L10n.instance.tr('ui.change_avatar'),
      actions: [
        AdaptiveSheetAction(
          value: 'gallery',
          icon: Icons.photo_library_outlined,
          label: AppPlatform.isDesktop
              ? L10n.instance.tr('image.choose_image')
              : L10n.instance.tr('image.choose_from_library'),
        ),
        if (AppPlatform.isMobile)
          AdaptiveSheetAction(
            value: 'camera',
            icon: Icons.photo_camera_outlined,
            label: L10n.instance.tr('image.take_photo'),
          ),
        if (controller.profile.avatar.isNotEmpty)
          AdaptiveSheetAction(
            value: 'clear',
            icon: Icons.delete_outline,
            label: L10n.instance.tr('ui.remove_avatar'),
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
      if (context.mounted) showAppSnack(context, trf('update.could_not_update_avatar__arg_0', ['$e']));
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
      title: L10n.instance.tr('rss.news'),
      subtitle: L10n.instance.tr('rss.feeds_and_articles_stay_on_this_device'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SwitchRow(
            label: L10n.instance.tr('rss.auto_sync'),
            subtitle: L10n.instance.tr('rss.fetch_every_feed_on_a_fixed_schedule'),
            value: settings.autoSync,
            onChanged: (value) => rss.update((s) => s.autoSync = value),
          ),
          _ChoiceRow(
            label: L10n.instance.tr('rss.sync_interval'),
            child: AdaptiveSegmentedControl(
              segments: [
                AdaptiveSegment('10', L10n.instance.tr('ui.10_min')),
                AdaptiveSegment('30', L10n.instance.tr('ui.30_min')),
                AdaptiveSegment('60', L10n.instance.tr('ui.1_hour')),
                AdaptiveSegment('360', L10n.instance.tr('ui.6_hours')),
              ],
              selected: '${settings.syncIntervalMinutes}',
              onChanged: (value) => rss.update(
                (s) => s.syncIntervalMinutes = int.tryParse(value) ?? 30,
              ),
            ),
          ),
          const Divider(height: 24),
          _SwitchRow(
            label: L10n.instance.tr('ui.mark_read_on_open'),
            value: settings.markReadOnOpen,
            onChanged: (value) => rss.update((s) => s.markReadOnOpen = value),
          ),
          _SwitchRow(
            label: L10n.instance.tr('image.show_images'),
            value: settings.showImages,
            onChanged: (value) => rss.update((s) => s.showImages = value),
          ),
          _SwitchRow(
            label: L10n.instance.tr('rss.newest_first'),
            subtitle: L10n.instance.tr('system.when_off_older_articles_come_first'),
            value: settings.newestFirst,
            onChanged: (value) => rss.update((s) => s.newestFirst = value),
          ),
          _ChoiceRow(
            label: L10n.instance.tr('ui.text_size'),
            child: AdaptiveSegmentedControl(
              segments: [
                AdaptiveSegment('15', L10n.instance.tr('ui.small')),
                AdaptiveSegment('17', L10n.instance.tr('ui.regular')),
                AdaptiveSegment('19', L10n.instance.tr('ui.large')),
                AdaptiveSegment('22', L10n.instance.tr('ui.huge')),
              ],
              selected: '${settings.fontSize}',
              onChanged: (value) =>
                  rss.update((s) => s.fontSize = int.tryParse(value) ?? 17),
            ),
          ),
          _ChoiceRow(
            label: L10n.instance.tr('ui.column_width'),
            child: AdaptiveSegmentedControl(
              segments: [
                AdaptiveSegment('620', L10n.instance.tr('ui.narrow')),
                AdaptiveSegment('720', L10n.instance.tr('ui.regular')),
                AdaptiveSegment('860', L10n.instance.tr('ui.wide')),
              ],
              selected: '${settings.contentWidth}',
              onChanged: (value) =>
                  rss.update((s) => s.contentWidth = int.tryParse(value) ?? 720),
            ),
          ),
          const Divider(height: 24),
          _SwitchRow(
            label: L10n.instance.tr('rss.auto_backup'),
            subtitle: L10n.instance.tr('rss.write_an_opml_copy_to_the_backup_folder_after_each_sync'),
            value: settings.autoBackup,
            onChanged: (value) => rss.update((s) => s.autoBackup = value),
          ),
          _ChoiceRow(
            label: L10n.instance.tr('rss.keep_articles'),
            child: AdaptiveSegmentedControl(
              segments: [
                AdaptiveSegment('0', L10n.instance.tr('ui.keep_all')),
                AdaptiveSegment('30', L10n.instance.tr('ui.30_days')),
                AdaptiveSegment('90', L10n.instance.tr('ui.90_days')),
                AdaptiveSegment('180', L10n.instance.tr('ui.180_days')),
              ],
              selected: '${settings.keepDays}',
              onChanged: (value) =>
                  rss.update((s) => s.keepDays = int.tryParse(value) ?? 0),
            ),
          ),
          InfoRow(
            label: L10n.instance.tr('ui.last_backup'),
            value: backup == null
                ? L10n.instance.tr('ui.never')
                : '${backup.month}/${backup.day} ${formatClock(backup)}',
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.backup_outlined, color: colors.muted),
            title: Text(L10n.instance.tr('rss.back_up_now')),
            subtitle: Text(L10n.instance.tr('rss.save_current_subscriptions_as_opml')),
            onTap: () async {
              await rss.backupNow();
              if (!context.mounted) return;
              showAppSnack(context, L10n.instance.tr('ui.backup_written_to_your_device'));
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
