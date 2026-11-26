import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../state/group_draft_model.dart';
import '../adaptive.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../../core/i18n.dart';

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String label = '',
  String initial = '',
  String? confirm,
  bool multiline = false,
  int maxLines = 1,
}) {
  final confirmLabel = confirm ?? L10n.instance.tr('ui.ok');
  final controller = TextEditingController(text: initial);
  final future = AppPlatform.usesCupertino
      ? showCupertinoDialog<String>(
          context: context,
          builder: (context) {
            return CupertinoAlertDialog(
              title: Text(title),
              content: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: CupertinoTextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: multiline ? maxLines : 1,
                  minLines: multiline ? 2 : 1,
                  placeholder: label.isEmpty ? null : label,
                ),
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context),
                  child: Text(L10n.instance.tr('ui.cancel')),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => _submit(context, controller),
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        )
      : showDialog<String>(
          context: context,
          builder: (context) {
            final c = appColors(context);
            return AlertDialog(
              title: Text(title),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLines: multiline ? maxLines : 1,
                minLines: multiline ? 2 : 1,
                decoration: InputDecoration(
                  labelText: label.isEmpty ? null : label,
                  hintStyle: TextStyle(color: c.faint),
                ),
                onSubmitted: multiline ? null : (_) => _submit(context, controller),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(L10n.instance.tr('ui.cancel')),
                ),
                FilledButton(
                  onPressed: () => _submit(context, controller),
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        );
  return future.whenComplete(controller.dispose);
}

void _submit(BuildContext context, TextEditingController controller) {
  Navigator.pop(context, controller.text.trim());
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  String? confirm,
  bool destructive = false,
}) async {
  final confirmLabel = confirm ?? L10n.instance.tr('ui.ok');
  final result = AppPlatform.usesCupertino
      ? await showCupertinoDialog<bool>(
          context: context,
          builder: (context) {
            return CupertinoAlertDialog(
              title: Text(title),
              content: message == null ? null : Text(message),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(L10n.instance.tr('ui.cancel')),
                ),
                CupertinoDialogAction(
                  isDestructiveAction: destructive,
                  isDefaultAction: !destructive,
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        )
      : await showDialog<bool>(
          context: context,
          builder: (context) {
            final c = appColors(context);
            return AlertDialog(
              title: Text(title),
              content: message == null
                  ? null
                  : Text(message, style: TextStyle(color: c.muted, height: 1.4)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(L10n.instance.tr('ui.cancel')),
                ),
                FilledButton(
                  style: destructive
                      ? FilledButton.styleFrom(backgroundColor: c.danger)
                      : null,
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirmLabel),
                ),
              ],
            );
          },
        );
  return result ?? false;
}

class GroupDraft {
  final String name;
  final List<String> members;

  GroupDraft(this.name, this.members);
}

Future<GroupDraft?> showGroupDraftDialog(
  BuildContext context, {
  required List<Peer> candidates,
  String initialName = '',
  Set<String> initialMembers = const {},
  String? title,
  String? confirm,
}) {
  return showDialog<GroupDraft>(
    context: context,
    builder: (context) {
      return ChangeNotifierProvider<GroupDraftModel>(
        create: (_) => GroupDraftModel(
          initialName: initialName,
          initialMembers: initialMembers,
        ),
        child: _GroupDraftDialog(
          candidates: candidates,
          title: title ?? L10n.instance.tr('chat.new_group_3'),
          confirm: confirm ?? L10n.instance.tr('ui.create'),
        ),
      );
    },
  );
}

class _GroupDraftDialog extends StatelessWidget {
  final List<Peer> candidates;
  final String title;
  final String confirm;

  const _GroupDraftDialog({
    required this.candidates,
    required this.title,
    required this.confirm,
  });

  @override
  Widget build(BuildContext context) {
    final model = context.watch<GroupDraftModel>();
    final c = appColors(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (AppPlatform.usesCupertino)
          CupertinoTextField(
            controller: model.name,
            autofocus: true,
            placeholder: L10n.instance.tr('chat.group_name'),
          )
        else
          TextField(
            controller: model.name,
            autofocus: true,
            decoration: InputDecoration(labelText: L10n.instance.tr('chat.group_name')),
          ),
        const SizedBox(height: 16),
        Text(
          L10n.instance.tr('chat.select_members'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 8),
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              L10n.instance.tr('chat.no_devices_online_yet_you_can_add_members_later'),
              style: TextStyle(color: c.faint, fontSize: 13),
            ),
          )
        else
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final peer in candidates)
                    CheckboxListTile(
                      value: model.isSelected(peer.id),
                      onChanged: (_) => model.toggle(peer.id),
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: PeerAvatar(
                        name: peer.displayName,
                        avatar: peer.avatar,
                        status: peer.status,
                        size: 34,
                      ),
                      title: Text(
                        peer.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        peer.connected
                            ? L10n.instance.tr(presenceLabelKey(peer.status))
                            : L10n.instance.tr('ui.offline'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );

    if (AppPlatform.usesCupertino) {
      return CupertinoAlertDialog(
        title: Text(title),
        content: SizedBox(width: 320, child: content),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.instance.tr('ui.cancel')),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final name = model.trimmedName;
              if (name.isEmpty) return;
              Navigator.pop(context, GroupDraft(name, model.selected.toList()));
            },
            child: Text(confirm),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(title),
      content: SizedBox(width: 420, child: content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L10n.instance.tr('ui.cancel')),
        ),
        FilledButton(
          onPressed: () {
            final name = model.trimmedName;
            if (name.isEmpty) return;
            Navigator.pop(context, GroupDraft(name, model.selected.toList()));
          },
          child: Text(confirm),
        ),
      ],
    );
  }
}

void showAppSnack(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<void> showTextInfo(
  BuildContext context, {
  required String title,
  required String value,
}) {
  if (AppPlatform.usesCupertino) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(value)),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(context),
              child: Text(L10n.instance.tr('system.close')),
            ),
          ],
        );
      },
    );
  }
  return showDialog<void>(
    context: context,
    builder: (context) {
      final c = appColors(context);
      return AlertDialog(
        title: Text(title),
        content: SelectableText(
          value,
          style: TextStyle(color: c.muted, height: 1.45),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L10n.instance.tr('system.close')),
          ),
        ],
      );
    },
  );
}
