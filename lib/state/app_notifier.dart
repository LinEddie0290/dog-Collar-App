/// T36・T34-G：通知（D-059 M4）。アプリを閉じていても気づけるように、ローカル通知で出す。
///
/// 画面・判定の側はこの [AppNotifier] だけを使う。テストでは [MemoryNotifier] を渡す。
/// 本物は [LocalAppNotifier]（flutter_local_notifications を包む）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract class AppNotifier {
  /// 最初に 1 回（許可を聞く）。失敗しても落とさない。
  Future<void> init();

  /// 1 件出す。[key] が同じものは上書きする（同じ通知を何枚も重ねない）。
  Future<void> show({required String key, required String title, required String body});
}

/// テスト用：出したものを覚えておくだけ。
class MemoryNotifier implements AppNotifier {
  final List<({String key, String title, String body})> shown = <({String key, String title, String body})>[];

  @override
  Future<void> init() async {}

  @override
  Future<void> show({required String key, required String title, required String body}) async {
    shown.add((key: key, title: title, body: body));
  }
}

/// 本物のローカル通知。
class LocalAppNotifier implements AppNotifier {
  LocalAppNotifier({FlutterLocalNotificationsPlugin? plugin}) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const String _channelId = 'collar_alerts';
  static const String _channelName = '安全・紧急';

  @override
  Future<void> init() async {
    if (_ready) return;
    try {
      const DarwinInitializationSettings darwin = DarwinInitializationSettings();
      const InitializationSettings settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
        macOS: darwin,
      );
      await _plugin.initialize(settings: settings); // v20 以降は名前つき（今は 23.0.2）
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      // 許可されない・この環境で使えない：通知なしで続ける（画面の表示は出る）
      debugPrint('notifications unavailable: $e');
    }
  }

  @override
  Future<void> show({required String key, required String title, required String body}) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      const NotificationDetails details = NotificationDetails(
        android: AndroidNotificationDetails(_channelId, _channelName, importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        macOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      );
      await _plugin.show(id: key.hashCode & 0x7fffffff, title: title, body: body, notificationDetails: details);
    } catch (e) {
      debugPrint('notification failed: $e');
    }
  }
}
