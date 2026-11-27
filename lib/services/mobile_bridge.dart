import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

class MobileBridge {
  static const MethodChannel _channel =
      MethodChannel('xin.dart.deer/mobile');

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  static bool get isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  static Future<void> acquireMulticast() async {
    if (!isMobile) return;
    try {
      await _channel.invokeMethod<void>('acquireMulticast');
    } catch (_) {}
  }

  static Future<void> releaseMulticast() async {
    if (!isMobile) return;
    try {
      await _channel.invokeMethod<void>('releaseMulticast');
    } catch (_) {}
  }

  static Future<Uint8List?> clipboardImage() async {
    if (isDesktop) {
      try {
        return await Pasteboard.image;
      } catch (_) {
        return null;
      }
    }
    if (!isMobile) return null;
    try {
      final result = await _channel.invokeMethod<Uint8List>('getClipboardImage');
      return result;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> deviceLabel() async {
    if (isDesktop) {
      try {
        final host = Platform.localHostname.trim();
        return host.isEmpty ? null : host;
      } catch (_) {
        return null;
      }
    }
    if (!isMobile) return null;
    try {
      return await _channel.invokeMethod<String>('deviceLabel');
    } catch (_) {
      return null;
    }
  }
}
