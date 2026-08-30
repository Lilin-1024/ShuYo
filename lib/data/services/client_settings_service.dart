import 'package:shared_preferences/shared_preferences.dart';

class ClientNotificationSettings {
  const ClientNotificationSettings({
    required this.scheduleEnabled,
  });

  final bool scheduleEnabled;

  ClientNotificationSettings copyWith({
    bool? scheduleEnabled,
  }) {
    return ClientNotificationSettings(
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
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

  static const scheduleNotificationsEnabledKey =
      'client.notifications.schedule.enabled';
  static const autoUseWebVpnProxyKey = 'client.network.webvpn.auto_proxy';
  static const startupOnboardingCompletedKey =
      'client.onboarding.startup.completed';
  static const themeIdKey = 'client.theme.id';
  static const followSystemThemeKey = 'client.theme.follow_system';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<ClientNotificationSettings> loadNotificationSettings() async {
    final prefs = await _preferencesLoader();
    return ClientNotificationSettings(
      // Course reminders are opt-in. Permission prompts should only happen
      // after the user explicitly enables reminders in settings.
      scheduleEnabled: prefs.getBool(scheduleNotificationsEnabledKey) ?? false,
    );
  }

  Future<ClientNotificationSettings> saveNotificationSettings(
    ClientNotificationSettings settings,
  ) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(
      scheduleNotificationsEnabledKey,
      settings.scheduleEnabled,
    );
    return settings;
  }

  Future<ClientNetworkSettings> loadNetworkSettings() async {
    final prefs = await _preferencesLoader();
    return ClientNetworkSettings(
      autoUseWebVpnProxy: prefs.getBool(autoUseWebVpnProxyKey) ?? true,
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

  Future<String?> loadThemeId() async {
    final prefs = await _preferencesLoader();
    return prefs.getString(themeIdKey);
  }

  Future<void> saveThemeId(String themeId) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(themeIdKey, themeId);
  }

  Future<bool> loadFollowSystemTheme() async {
    final prefs = await _preferencesLoader();
    return prefs.getBool(followSystemThemeKey) ?? false;
  }

  Future<void> saveFollowSystemTheme(bool enabled) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(followSystemThemeKey, enabled);
  }

  Future<bool> loadStartupOnboardingCompleted() async {
    final prefs = await _preferencesLoader();
    return prefs.getBool(startupOnboardingCompletedKey) ?? false;
  }

  Future<void> saveStartupOnboardingCompleted(bool completed) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(startupOnboardingCompletedKey, completed);
  }
}
