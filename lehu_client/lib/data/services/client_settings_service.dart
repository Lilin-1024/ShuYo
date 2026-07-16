import 'package:shared_preferences/shared_preferences.dart';

class ClientNotificationSettings {
  const ClientNotificationSettings({
    required this.enabled,
    required this.scheduleEnabled,
    required this.forumEnabled,
  });

  final bool enabled;
  final bool scheduleEnabled;
  final bool forumEnabled;

  ClientNotificationSettings copyWith({
    bool? enabled,
    bool? scheduleEnabled,
    bool? forumEnabled,
  }) {
    return ClientNotificationSettings(
      enabled: enabled ?? this.enabled,
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
      forumEnabled: forumEnabled ?? this.forumEnabled,
    );
  }
}

class ClientSettingsService {
  ClientSettingsService({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const notificationsEnabledKey = 'client.notifications.enabled';
  static const scheduleNotificationsEnabledKey =
      'client.notifications.schedule.enabled';
  static const forumNotificationsEnabledKey =
      'client.notifications.forum.enabled';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<ClientNotificationSettings> loadNotificationSettings() async {
    final prefs = await _preferencesLoader();
    return ClientNotificationSettings(
      enabled: prefs.getBool(notificationsEnabledKey) ?? true,
      scheduleEnabled: prefs.getBool(scheduleNotificationsEnabledKey) ?? true,
      forumEnabled: prefs.getBool(forumNotificationsEnabledKey) ?? true,
    );
  }

  Future<ClientNotificationSettings> saveNotificationSettings(
    ClientNotificationSettings settings,
  ) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(notificationsEnabledKey, settings.enabled);
    await prefs.setBool(
      scheduleNotificationsEnabledKey,
      settings.scheduleEnabled,
    );
    await prefs.setBool(forumNotificationsEnabledKey, settings.forumEnabled);
    return settings;
  }
}
