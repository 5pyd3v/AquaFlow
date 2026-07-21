import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'logger_service.dart';

/// Background message handler must be a top-level function (FCM
/// requirement — it runs in a separate isolate).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.info('Background FCM message: ${message.messageId}');
}

/// Handles the full push-notification lifecycle: permission request,
/// FCM token registration against the signed-in profile, foreground
/// local-notification display, and tap-to-navigate payload parsing.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final ValueNotifier<Map<String, dynamic>?> onNotificationTap =
      ValueNotifier(null);

  static const _channel = AndroidNotificationChannel(
    'aquaflow_high_importance',
    'AquaFlow Notifications',
    description: 'Order updates, delivery alerts and offers.',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          onNotificationTap.value =
              jsonDecode(response.payload!) as Map<String, dynamic>;
        }
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onNotificationTap.value = message.data;
    });

    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      onNotificationTap.value = initialMessage.data;
    }

    _fcm.onTokenRefresh.listen(_syncTokenToProfile);
  }

  Future<void> registerDeviceToken() async {
    final token = await _fcm.getToken();
    if (token != null) await _syncTokenToProfile(token);
  }

  Future<void> _syncTokenToProfile(String token) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client.from(SupabaseConfig.profiles).update({
        'fcm_token': token,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
    } catch (e) {
      AppLogger.error('Failed to sync FCM token', e);
    }
  }

  Future<void> clearDeviceToken() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from(SupabaseConfig.profiles)
          .update({'fcm_token': null}).eq('id', userId);
      await _fcm.deleteToken();
    } catch (e) {
      AppLogger.error('Failed to clear FCM token', e);
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }
}
