import 'web_push.dart';

/// Fuori dal browser le notifiche web non esistono (vedi `web_push_web.dart`).
WebPushClient createWebPushClient() => const NoWebPush();
