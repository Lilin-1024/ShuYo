import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'client_settings_service.dart';

class ForumBadgeNotificationService {
  ForumBadgeNotificationService({
    ClientSettingsService? settingsService,
    FlutterLocalNotificationsPlugin? notifications,
  })  : _settingsService = settingsService ?? ClientSettingsService(),
        _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'forum_messages';
  static const _notificationId = 430000;

  final ClientSettingsService _settingsService;
  final FlutterLocalNotificationsPlugin _notifications;
  bool _initialized = false;

  Future<bool> requestNotificationPermission() {
    return _ensureNotificationPermission(request: true);
  }

  Future<void> showBadgeSummary({
    required int newNotifications,
    required int newMessages,
  }) async {
    if (newNotifications <= 0 && newMessages <= 0) {
      return;
    }
    final settings = await _settingsService.loadNotificationSettings();
    if (!settings.enabled || !settings.forumEnabled) {
      return;
    }
    final allowed = await _ensureNotificationPermission();
    if (!allowed) {
      return;
    }
    await _notifications.show(
      id: _notificationId,
      title: '乐乎有新消息',
      body: _messageBody(
        newNotifications: newNotifications,
        newMessages: newMessages,
      ),
      notificationDetails: _notificationDetails,
      payload: 'forum:badges',
    );
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<bool> _ensureNotificationPermission({bool request = false}) async {
    await _ensureInitialized();
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidEnabled = await android?.areNotificationsEnabled();
    if (androidEnabled == false && request) {
      final granted = await android?.requestNotificationsPermission();
      if (granted == false) {
        return false;
      }
    } else if (androidEnabled == false) {
      return false;
    }

    if (request) {
      final ios = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final iosGranted = await ios?.requestPermissions(
        alert: true,
        sound: true,
      );
      if (iosGranted == false) {
        return false;
      }

      final macOS = _notifications.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final macOSGranted = await macOS?.requestPermissions(
        alert: true,
        sound: true,
      );
      if (macOSGranted == false) {
        return false;
      }
    }

    return true;
  }

  static String _messageBody({
    required int newNotifications,
    required int newMessages,
  }) {
    final parts = <String>[
      if (newNotifications > 0) '$newNotifications 条论坛通知',
      if (newMessages > 0) '$newMessages 条私信',
    ];
    return parts.join('，');
  }

  static const _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      '论坛消息',
      channelDescription: '提示论坛通知和私信变化',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );
}
