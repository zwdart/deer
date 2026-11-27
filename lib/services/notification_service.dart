import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  void Function(String convId)? onSelect;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: LinuxInitializationSettings(
        defaultActionName: '打开',
      ),
      windows: WindowsInitializationSettings(
        appName: 'deer',
        appUserModelId: 'Xin.Dart.Deer',
        guid: 'c2b5d8a1-4f3e-4a9b-8c7d-1e2f3a4b5c6d',
      ),
    );
    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) onSelect?.call(payload);
        },
      );
      _ready = true;
      if (Platform.isAndroid) {
        try {
          await _plugin
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission();
        } catch (_) {}
      }
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        onSelect?.call(payload);
      }
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> show({
    required String convId,
    required String title,
    required String body,
    bool sound = true,
  }) async {
    if (!_ready) return;
    const android = AndroidNotificationDetails(
      'messages',
      'Messages',
      channelDescription: 'New chat messages',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      groupKey: 'messages',
      styleInformation: BigTextStyleInformation(''),
    );
    final darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: sound,
    );
    const linux = LinuxNotificationDetails();
    const windows = WindowsNotificationDetails();
    final details = NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
      windows: windows,
    );
    try {
      await _plugin.show(
        id: _idFor(convId),
        title: title,
        body: body,
        notificationDetails: details,
        payload: convId,
      );
    } catch (_) {}
  }

  int _idFor(String convId) {
    var hash = 0;
    for (final c in convId.codeUnits) {
      hash = ((hash * 31) + c) & 0x7fffffff;
    }
    return hash & 0x7fffffff;
  }

  Future<void> cancel(String convId) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _idFor(convId));
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
