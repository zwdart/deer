import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// Captures the Flutter surface of the running app.
///
/// The widget tree is wrapped in a [RepaintBoundary] by [DeerApp] and the
/// resulting image can be copied, saved, shared or sent to a conversation.
class ScreenshotService {
  ScreenshotService._();

  static final ScreenshotService instance = ScreenshotService._();

  final GlobalKey boundaryKey = GlobalKey();

  Future<Uint8List?> capture({double maxPixelRatio = 3}) async {
    final context = boundaryKey.currentContext;
    final render = context?.findRenderObject();
    if (render is! RenderRepaintBoundary) return null;
    try {
      final view = ui.PlatformDispatcher.instance.views.isEmpty
          ? null
          : ui.PlatformDispatcher.instance.views.first;
      final ratio = (view?.devicePixelRatio ?? 1).clamp(1.0, maxPixelRatio);
      final image = await render.toImage(pixelRatio: ratio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  Future<String?> saveToDirectory(Uint8List bytes, String directory) async {
    try {
      final dir = Directory(directory);
      await dir.create(recursive: true);
      final now = DateTime.now();
      final name = 'deer-'
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}-'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}.png';
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
