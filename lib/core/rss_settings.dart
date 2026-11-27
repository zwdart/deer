import 'dart:convert';
import 'dart:io';

import 'helpers.dart';

/// RSS 相关偏好。deer 不用 shared_preferences，和聊天设置一样落在数据目录的 json 文件里。
class RssSettings {
  bool autoSync;
  int syncIntervalMinutes;
  bool autoBackup;
  int keepDays;
  bool markReadOnOpen;
  bool showImages;
  int fontSize;
  double lineHeight;
  int contentWidth;
  bool newestFirst;

  RssSettings({
    this.autoSync = false,
    this.syncIntervalMinutes = 30,
    this.autoBackup = false,
    this.keepDays = 0,
    this.markReadOnOpen = true,
    this.showImages = true,
    this.fontSize = 17,
    this.lineHeight = 1.75,
    this.contentWidth = 720,
    this.newestFirst = true,
  });

  Map<String, dynamic> toJson() => {
        'autoSync': autoSync,
        'syncIntervalMinutes': syncIntervalMinutes,
        'autoBackup': autoBackup,
        'keepDays': keepDays,
        'markReadOnOpen': markReadOnOpen,
        'showImages': showImages,
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'contentWidth': contentWidth,
        'newestFirst': newestFirst,
      };

  factory RssSettings.fromJson(Map<String, dynamic> m, RssSettings d) =>
      RssSettings(
        autoSync: asBool(m['autoSync'], d.autoSync),
        syncIntervalMinutes:
            asInt(m['syncIntervalMinutes'], d.syncIntervalMinutes).clamp(1, 1440),
        autoBackup: asBool(m['autoBackup'], d.autoBackup),
        keepDays: asInt(m['keepDays'], d.keepDays),
        markReadOnOpen: asBool(m['markReadOnOpen'], d.markReadOnOpen),
        showImages: asBool(m['showImages'], d.showImages),
        fontSize: asInt(m['fontSize'], d.fontSize).clamp(13, 26),
        lineHeight: (m['lineHeight'] as num?)?.toDouble() ?? d.lineHeight,
        contentWidth: asInt(m['contentWidth'], d.contentWidth).clamp(480, 1000),
        newestFirst: asBool(m['newestFirst'], d.newestFirst),
      );
}

class RssSettingsStore {
  final String path;
  DateTime? lastBackupAt;

  RssSettingsStore(this.path);

  Future<RssSettings> load() async {
    final file = File(path);
    if (!await file.exists()) return RssSettings();
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return RssSettings();
      final map = Map<String, dynamic>.from(raw);
      final last = map['lastBackupAt'];
      lastBackupAt = last is String ? DateTime.tryParse(last) : null;
      return RssSettings.fromJson(map, RssSettings());
    } catch (_) {
      return RssSettings();
    }
  }

  Future<void> save(RssSettings settings, {DateTime? backupAt}) async {
    if (backupAt != null) lastBackupAt = backupAt;
    final data = settings.toJson();
    final stamp = lastBackupAt;
    if (stamp != null) data['lastBackupAt'] = stamp.toIso8601String();
    await writeAtomic(
        path, utf8.encode(const JsonEncoder.withIndent('  ').convert(data)));
  }
}
