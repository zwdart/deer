import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
import 'theme.dart';

class AppPlatform {
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isDesktop => isMacOS || isWindows || isLinux;
  static bool get isMobile => isIOS || isAndroid;
  static bool get usesCupertino => isIOS || isMacOS;

  static TargetPlatform get targetPlatform {
    if (isIOS) return TargetPlatform.iOS;
    if (isAndroid) return TargetPlatform.android;
    if (isMacOS) return TargetPlatform.macOS;
    if (isWindows) return TargetPlatform.windows;
    return TargetPlatform.linux;
  }
}

PageRoute<T> adaptivePageRoute<T>(Widget page) {
  if (AppPlatform.usesCupertino) {
    return CupertinoPageRoute<T>(builder: (_) => page);
  }
  return MaterialPageRoute<T>(builder: (_) => page);
}

IconData get adaptiveBackIcon =>
    AppPlatform.usesCupertino ? CupertinoIcons.back : Icons.arrow_back;

class DchatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor;
  final double? toolbarHeight;
  final double? titleSpacing;

  const DchatAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.backgroundColor,
    this.toolbarHeight,
    this.titleSpacing,
  });

  @override
  Size get preferredSize {
    final height = toolbarHeight ?? (AppPlatform.usesCupertino ? 48 : kToolbarHeight);
    return Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final cupertino = AppPlatform.usesCupertino;
    return AppBar(
      title: titleWidget ?? title,
      actions: actions,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: cupertino,
      toolbarHeight: toolbarHeight ?? (cupertino ? 48 : null),
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: backgroundColor,
      bottom: bottom,
      titleSpacing: titleSpacing,
      leadingWidth: cupertino ? 44 : null,
      iconTheme: IconThemeData(
        size: 20,
        color: Theme.of(context).appBarTheme.foregroundColor,
      ),
    );
  }
}

class AdaptiveSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AdaptiveSwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (AppPlatform.usesCupertino) {
      return CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: appColors(context).accent,
      );
    }
    return Switch(value: value, onChanged: onChanged);
  }
}

class AdaptiveSegment {
  final String value;
  final String label;

  const AdaptiveSegment(this.value, this.label);
}

class AdaptiveSegmentedControl extends StatelessWidget {
  final List<AdaptiveSegment> segments;
  final String selected;
  final ValueChanged<String> onChanged;

  const AdaptiveSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (AppPlatform.usesCupertino) {
      return CupertinoSlidingSegmentedControl<String>(
        groupValue: selected,
        onValueChanged: (value) {
          if (value != null) onChanged(value);
        },
        children: {
          for (final segment in segments)
            segment.value: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                segment.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
        },
      );
    }
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        for (final segment in segments)
          ButtonSegment(value: segment.value, label: Text(segment.label)),
      ],
      selected: {selected},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class AdaptiveSheetAction<T> {
  final T value;
  final String label;
  final IconData? icon;
  final bool destructive;

  const AdaptiveSheetAction({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
  });
}

Future<T?> showAdaptiveActionSheet<T>(
  BuildContext context, {
  String? title,
  String? message,
  required List<AdaptiveSheetAction<T>> actions,
  String? cancel,
}) {
  final cancelLabel = cancel ?? L10n.instance.tr('ui.cancel');
  if (AppPlatform.usesCupertino) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: title == null ? null : Text(title),
          message: message == null ? null : Text(message),
          actions: [
            for (final action in actions)
              CupertinoActionSheetAction(
                isDestructiveAction: action.destructive,
                onPressed: () => Navigator.pop(context, action.value),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (action.icon != null) ...[
                      Icon(action.icon, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Text(action.label),
                  ],
                ),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: Text(cancelLabel),
          ),
        );
      },
    );
  }
  if (AppPlatform.isDesktop) {
    return showDialog<T>(
      context: context,
      builder: (dialogContext) {
        final c = appColors(dialogContext);
        return SimpleDialog(
          title: title == null
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title),
                    if (message != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ],
                ),
          children: [
            for (final action in actions)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, action.value),
                child: Row(
                  children: [
                    if (action.icon != null) ...[
                      Icon(
                        action.icon,
                        size: 19,
                        color: action.destructive ? c.danger : c.muted,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      action.label,
                      style: TextStyle(
                        color: action.destructive ? c.danger : null,
                      ),
                    ),
                  ],
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                cancelLabel,
                style: TextStyle(color: c.faint),
              ),
            ),
          ],
        );
      },
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final c = appColors(context);
      final actionsList = actions;
      return ConstrainedBox(
        // 最大到屏幕 85% 高度，超过则内部滚动，不会被键盘或状态栏裁掉
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: 1 + actionsList.length, // 标题 + N 项
          separatorBuilder: (_, _) => const Divider(height: 1, thickness: 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              if (title == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }
            final action = actionsList[index - 1];
            return ListTile(
              leading: action.icon == null ? null : Icon(action.icon),
              title: Text(
                action.label,
                style: action.destructive ? TextStyle(color: c.danger) : null,
              ),
              onTap: () => Navigator.pop(context, action.value),
            );
          },
        ),
      );
    },
  );
}
