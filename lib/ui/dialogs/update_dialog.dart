import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/helpers.dart';
import '../../core/i18n.dart';
import '../../services/update/update_platform.dart';
import '../../state/update_view_model.dart';
import '../theme.dart';
import 'dialogs.dart';

Future<void> showUpdateDialog(BuildContext context, UpdateViewModel model) {
  return showDialog<void>(
    context: context,
    builder: (_) => ChangeNotifierProvider<UpdateViewModel>.value(
      value: model,
      child: const _UpdateDialog(),
    ),
  );
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<UpdateViewModel>();
    final colors = appColors(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update_alt, color: colors.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(L10n.instance.tr('update.version_update'))),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(child: _body(context, model)),
        ),
      ),
      actions: _actions(context, model),
    );
  }

  Widget _body(BuildContext context, UpdateViewModel model) {
    final colors = appColors(context);
    switch (model.status) {
      case UpdateStatus.idle:
        return Text(L10n.instance.tr('update.check_for_updates_to_fetch_the_latest_release_information_from_the_server'));
      case UpdateStatus.checking:
        return Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(L10n.instance.tr('update.checking_for_updates'))),
          ],
        );
      case UpdateStatus.upToDate:
        return _message(
          context,
          icon: Icons.check_circle_outline,
          color: colors.accent,
          title: L10n.instance.tr('update.you_re_up_to_date'),
          detail: trf('ui.current_version__arg_0', [model.result?.localVersion.toString() ?? model.localVersion]),
        );
      case UpdateStatus.noAsset:
        return _message(
          context,
          icon: Icons.info_outline,
          color: colors.muted,
          title: L10n.instance.tr('update.new_version_available'),
          detail: L10n.instance.tr('update.no_package_is_available_for_this_platform_download_it_manually_from_the_release_page'),
        );
      case UpdateStatus.available:
        return _available(context, model);
      case UpdateStatus.downloading:
        return _downloading(context, model);
      case UpdateStatus.downloaded:
        return _downloaded(context, model);
      case UpdateStatus.error:
        return _message(
          context,
          icon: Icons.error_outline,
          color: colors.danger,
          title: L10n.instance.tr('update.update_check_failed'),
          detail: L10n.instance.tr(model.error ?? '请稍后重试'),
        );
    }
  }

  Widget _available(BuildContext context, UpdateViewModel model) {
    final colors = appColors(context);
    final result = model.result!;
    final release = result.release;
    final asset = result.asset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          trf('update.new_version_available__arg_0', [release.tagName.isEmpty ? result.remoteVersion.toString() : release.tagName]),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        _line(context, L10n.instance.tr('ui.current_version_2'), result.localVersion.toString()),
        _line(context, L10n.instance.tr('update.latest_version'), result.remoteVersion.toString()),
        _line(context, L10n.instance.tr('ui.platform'), _platformLabel(result.platform)),
        if (release.publishedAt != null)
          _line(context, L10n.instance.tr('ui.release_date'), _formatDate(release.publishedAt!)),
        if (asset != null) ...[
          _line(context, L10n.instance.tr('update.package'), asset.name),
          if (asset.hasSize)
            _line(context, L10n.instance.tr('update.package_size'), humanSize(asset.size)),
        ],
        const SizedBox(height: 10),
        Text(
          L10n.instance.tr('update.release_notes'),
          style: TextStyle(fontWeight: FontWeight.w600, color: colors.muted),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: SelectableText(
            release.notes.trim().isEmpty
                ? L10n.instance.tr('update.no_release_notes')
                : release.notes.trim(),
            style: TextStyle(fontSize: 12.5, height: 1.45, color: colors.text),
          ),
        ),
      ],
    );
  }

  Widget _downloading(BuildContext context, UpdateViewModel model) {
    final colors = appColors(context);
    final percent = model.total > 0 ? '${(model.progress * 100).round()}%' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          L10n.instance.tr('update.downloading_package'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: model.total > 0 ? model.progress : null,
          color: colors.accent,
          backgroundColor: colors.border,
        ),
        const SizedBox(height: 8),
        Text(
          model.total > 0
              ? '${humanSize(model.received)} / ${humanSize(model.total)}  $percent'
              : humanSize(model.received),
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
      ],
    );
  }

  Widget _downloaded(BuildContext context, UpdateViewModel model) {
    final colors = appColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _message(
          context,
          icon: Icons.download_done,
          color: colors.accent,
          title: L10n.instance.tr('ui.download_complete'),
          detail: L10n.instance.tr('share.the_package_has_been_saved_you_can_open_or_share_it_directly'),
        ),
        const SizedBox(height: 8),
        SelectableText(
          model.downloadedFile?.path ?? '',
          style: TextStyle(fontSize: 11.5, color: colors.muted),
        ),
      ],
    );
  }

  Widget _message(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String detail,
  }) {
    final colors = appColors(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(fontSize: 12.5, height: 1.45, color: colors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _line(BuildContext context, String label, String value) {
    final colors = appColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colors.muted,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, UpdateViewModel model) {
    final platform = model.result?.platform ?? model.platform;
    final actions = <Widget>[];
    switch (model.status) {
      case UpdateStatus.idle:
        actions.add(TextButton(
          onPressed: () => model.check(),
          child: Text(L10n.instance.tr('update.check_for_updates')),
        ));
      case UpdateStatus.checking:
        actions.add(TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.instance.tr('system.hide')),
        ));
      case UpdateStatus.upToDate:
        actions.add(TextButton(
          onPressed: () => model.check(localVersion: model.localVersion),
          child: Text(L10n.instance.tr('ui.check_again')),
        ));
      case UpdateStatus.available:
        actions.add(TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.instance.tr('ui.later')),
        ));
        actions.add(TextButton(
          onPressed: () async {
            final ok = await model.copyLink();
            if (context.mounted) {
              showAppSnack(
                context,
                L10n.instance.tr(ok ? '已复制下载链接' : '没有可用的下载链接'),
              );
            }
          },
          child: Text(L10n.instance.tr('ui.copy_link')),
        ));
        actions.add(TextButton(
          onPressed: () => _openBrowser(context, model),
          child: Text(L10n.instance.tr('ui.open_in_browser')),
        ));
        actions.add(FilledButton(
          onPressed: model.download,
          child: Text(_downloadLabel(platform)),
        ));
      case UpdateStatus.noAsset:
        actions.add(TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.instance.tr('system.close')),
        ));
        actions.add(FilledButton(
          onPressed: () => _openBrowser(context, model),
          child: Text(L10n.instance.tr('ui.open_in_browser')),
        ));
      case UpdateStatus.downloading:
        actions.add(TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.instance.tr('system.hide')),
        ));
      case UpdateStatus.downloaded:
        actions.add(TextButton(
          onPressed: () => _openBrowser(context, model),
          child: Text(L10n.instance.tr('ui.open_in_browser')),
        ));
        actions.add(TextButton(
          onPressed: () async {
            final ok = await model.copyLink();
            if (context.mounted) {
              showAppSnack(
                context,
                L10n.instance.tr(ok ? '已复制下载链接' : '没有可用的下载链接'),
              );
            }
          },
          child: Text(L10n.instance.tr('ui.copy_link')),
        ));
        actions.add(FilledButton(
          onPressed: () async {
            final error = await model.openDownloaded();
            if (context.mounted && error != null) {
              showAppSnack(context, L10n.instance.tr(error));
            }
          },
          child: Text(L10n.instance.tr(
            platform == UpdatePlatform.ios ? '分享安装包' : '打开安装包',
          )),
        ));
      case UpdateStatus.error:
        final retryDownload = model.result?.asset != null;
        actions.add(TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.instance.tr('system.close')),
        ));
        actions.add(FilledButton(
          onPressed: retryDownload
              ? model.download
              : () => model.check(localVersion: model.localVersion),
          child: Text(L10n.instance.tr(retryDownload ? '重试下载' : '重试')),
        ));
    }
    return actions;
  }

  Future<void> _openBrowser(BuildContext context, UpdateViewModel model) async {
    final error = await model.openInBrowser();
    if (context.mounted && error != null) {
      showAppSnack(context, L10n.instance.tr(error));
    }
  }

  static String _downloadLabel(UpdatePlatform platform) {
    return switch (platform) {
      UpdatePlatform.android => L10n.instance.tr('ui.download_apk'),
      UpdatePlatform.ios => L10n.instance.tr('share.download_share'),
      UpdatePlatform.macOS ||
      UpdatePlatform.windows ||
      UpdatePlatform.linux =>
        L10n.instance.tr('update.download_package'),
    };
  }

  static String _platformLabel(UpdatePlatform platform) {
    return switch (platform) {
      UpdatePlatform.android => 'Android',
      UpdatePlatform.ios => 'iOS',
      UpdatePlatform.macOS => 'macOS',
      UpdatePlatform.windows => 'Windows',
      UpdatePlatform.linux => 'Linux',
    };
  }

  static String _formatDate(DateTime value) {
    final date = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }
}
