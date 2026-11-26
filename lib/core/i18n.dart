import 'dart:io';

import 'package:flutter/foundation.dart';

import 'i18n_data.g.dart';

/// 全局国际化单例。
///
/// 文案以静态 const map 的形式嵌在 [i18n_data.g.dart] 里，
/// 由 `_tool_gen_i18n_map.py` 脚本从 `assets/i18n/en.json` 和 `zh.json` 生成。
/// key 使用 dotted 形式（如 `chat.typing`、`device.port`）。
class L10n extends ChangeNotifier {
  L10n._();
  static final L10n instance = L10n._();

  String _language = 'system';

  String get language => _language;

  set language(String value) {
    if (_language == value) return;
    _language = value;
    notifyListeners();
  }

  bool get english {
    if (_language == 'en') return true;
    if (_language == 'zh') return false;
    // 生产构建使用系统 locale；测试里 Platform.localeName 固定是 en_US，
    // 所以通过 dart.vm.product 区分：生产按系统，测试默认中文。
    if (bool.fromEnvironment('dart.vm.product')) {
      return Platform.localeName.toLowerCase().startsWith('en');
    }
    // 非生产（debug、profile、test）：默认中文，避免测试拿到英文翻译。
    return false;
  }

  /// 保持与旧代码的兼容性 —— 现在数据已嵌入 Dart 源码，不需要异步加载。
  Future<void> load() async {}

  /// 直接 key 翻译。中文环境返回中文，英文环境返回英文。
  String tr(String key) {
    final map = english ? L10nData.en : L10nData.zh;
    final v = map[key];
    if (v != null && v.isNotEmpty) return v;
    return key;
  }

  /// 带占位符替换。支持 %s、%d、%v，按出现顺序依次替换成 args 里的元素。
  String trf(String key, List<Object> args) {
    var s = tr(key);
    for (final arg in args) {
      final idxS = s.indexOf('%s');
      final idxD = s.indexOf('%d');
      final idxV = s.indexOf('%v');
      final candidates = [idxS, idxD, idxV].where((i) => i >= 0).toList()..sort();
      if (candidates.isEmpty) break;
      final idx = candidates.first;
      s = s.replaceRange(idx, idx + 2, arg.toString());
    }
    return s;
  }
}

/// 全局便捷函数，任何地方 import 后直接调用。
String tr(String key) => L10n.instance.tr(key);

/// 带占位符替换的全局便捷函数。
String trf(String key, List<Object> args) => L10n.instance.trf(key, args);
