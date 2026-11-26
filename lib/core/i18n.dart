import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class L10n extends ChangeNotifier {
  L10n._();
  static final L10n instance = L10n._();

  final Map<String, String> _en = {};
  String _language = 'system';
  bool _loaded = false;

  String get language => _language;

  set language(String value) {
    if (_language == value) return;
    _language = value;
    notifyListeners();
  }

  bool get english {
    if (language == 'en') return true;
    if (language == 'zh') return false;
    return !Platform.localeName.toLowerCase().startsWith('zh');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final text = await rootBundle.loadString('assets/en.tsv');
      for (final line in text.split('\n')) {
        if (line.isEmpty || line.startsWith('#')) continue;
        final i = line.indexOf('\t');
        if (i < 0) continue;
        var key = line.substring(0, i);
        var value = line.substring(i + 1);
        if (value.endsWith('\r')) value = value.substring(0, value.length - 1);
        key = key.replaceAll(r'\n', '\n');
        value = value.replaceAll(r'\n', '\n');
        _en[key] = value;
      }
    } catch (_) {}
  }

  String tr(String key) {
    if (!english) return key;
    return _en[key] ?? key;
  }

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

String tr(String key) => L10n.instance.tr(key);
String trf(String key, List<Object> args) => L10n.instance.trf(key, args);
