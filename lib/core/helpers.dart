import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import 'i18n.dart';

final Random _secure = Random.secure();

String randomHex(int bytes) {
  final b = List<int>.generate(bytes, (_) => _secure.nextInt(256));
  return b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
}

String newId([String prefix = '']) {
  final id = randomHex(16);
  return prefix.isEmpty ? id : '${prefix}_$id';
}

String newHttpToken() => randomHex(16);

String newTransferToken() => 't_${randomHex(18)}';

String rfc3339(DateTime time) {
  final dt = time;
  final local = dt.isUtc ? dt.toLocal() : dt;
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final abs = off.abs();
  final hh = abs.inHours.toString().padLeft(2, '0');
  final mm = (abs.inMinutes % 60).toString().padLeft(2, '0');
  final frac = local.millisecond.toString().padLeft(3, '0') +
      local.microsecond.toString().padLeft(3, '0');
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}T'
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}'
      '.$frac$sign$hh:$mm';
}

DateTime? parseTime(Object? value) {
  if (value == null) return null;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  final s = value.toString();
  if (s.isEmpty) return null;
  var text = s;
  final dot = text.indexOf('.');
  if (dot >= 0) {
    var end = dot + 1;
    while (end < text.length && _isDigit(text.codeUnitAt(end))) {
      end++;
    }
    final digits = end - dot - 1;
    if (digits > 6) {
      text = text.substring(0, dot + 7) + text.substring(end);
    }
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.toLocal() : parsed;
}

bool _isDigit(int c) => c >= 48 && c <= 57;

int asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

String humanSize(int n) {
  if (n < 1024) return '$n B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = n.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

String truncateRunes(String s, int max) {
  final runes = s.runes.toList();
  if (runes.length <= max) return s;
  return '${String.fromCharCodes(runes.take(max))}…';
}

String chatPreview(String kind, String text, String fileName, bool recalled) {
  if (recalled) return tr('chat.message_unsent');
  switch (kind) {
    case 'image':
      return text.isEmpty ? tr('image.image_2') : '${tr('image.image_2')} $text';
    case 'file':
      return '${tr('ui.file_2')} $fileName';
    case 'system':
      return text;
    default:
      return truncateRunes(text.replaceAll('\n', ' '), 80);
  }
}

String sanitizeFileName(String name) {
  var base = p.basename(name.replaceAll('\\', '/'));
  if (base == '.' || base == '..' || base.isEmpty) base = 'file';
  final cleaned = base.replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_').trim();
  if (cleaned.isEmpty) return 'file';
  return cleaned;
}

Future<String> uniquePath(String dir, String name) async {
  final base = sanitizeFileName(name);
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  final ext = dot > 0 ? base.substring(dot) : '';
  var candidate = p.join(dir, base);
  var n = 1;
  while (await File(candidate).exists() ||
      await Directory(candidate).exists()) {
    candidate = p.join(dir, '$stem ($n)$ext');
    n++;
  }
  return candidate;
}

String mimeOf(String path) =>
    lookupMimeType(path) ?? 'application/octet-stream';

bool isImageMime(String mime) => mime.toLowerCase().startsWith('image/');

String extForMime(String mime) {
  final e = extensionFromMime(mime);
  if (e != null && e.isNotEmpty) return '.$e';
  switch (mime.split('/').first) {
    case 'image':
      return '.png';
    case 'text':
      return '.txt';
    default:
      return '.bin';
  }
}

String sha256Hex(String text) =>
    sha256.convert(utf8.encode(text)).toString();

Future<void> writeAtomic(String path, List<int> data) async {
  final dir = p.dirname(path);
  await Directory(dir).create(recursive: true);
  final tmp = File('$path.tmp-${randomHex(4)}');
  await tmp.writeAsBytes(data, flush: true);
  try {
    await tmp.rename(path);
  } catch (_) {
    final target = File(path);
    if (await target.exists()) await target.delete();
    await tmp.rename(path);
  }
}

Future<void> moveFile(String from, String to) async {
  final src = File(from);
  try {
    await src.rename(to);
  } on FileSystemException {
    await src.copy(to);
    await src.delete();
  }
}

String urlHost(String url) {
  final uri = Uri.tryParse(url);
  return uri?.host ?? '';
}

String rewriteUrlHost(String url, String host) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty || host.isEmpty) return url;
  return uri.replace(host: host).toString();
}

bool looksLikeSharePath(String path) {
  return path.startsWith('/t/') ||
      path.startsWith('/health') ||
      path.startsWith('/upload');
}

String? shareTokenFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final parts = uri.pathSegments;
  if (parts.length >= 2 && parts.first == 't') {
    final token = parts[1];
    if (RegExp(r'^[0-9a-fA-F]{16,64}$').hasMatch(token)) return token;
  }
  final m = RegExp(r'/t/([0-9a-fA-F]{16,64})').firstMatch(url);
  return m?.group(1);
}

String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
