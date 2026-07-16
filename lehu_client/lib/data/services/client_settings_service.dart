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

class ClientNetworkSettings {
  const ClientNetworkSettings({
    required this.autoUseWebVpnProxy,
  });

  final bool autoUseWebVpnProxy;

  ClientNetworkSettings copyWith({
    bool? autoUseWebVpnProxy,
  }) {
    return ClientNetworkSettings(
      autoUseWebVpnProxy: autoUseWebVpnProxy ?? this.autoUseWebVpnProxy,
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
  static const autoUseWebVpnProxyKey = 'client.network.webvpn.auto_proxy';

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

  Future<ClientNetworkSettings> loadNetworkSettings() async {
    final prefs = await _preferencesLoader();
    return ClientNetworkSettings(
      autoUseWebVpnProxy: prefs.getBool(autoUseWebVpnProxyKey) ?? false,
    );
  }

  Future<ClientNetworkSettings> saveNetworkSettings(
    ClientNetworkSettings settings,
  ) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(
      autoUseWebVpnProxyKey,
      settings.autoUseWebVpnProxy,
    );
    return settings;
  }
}
