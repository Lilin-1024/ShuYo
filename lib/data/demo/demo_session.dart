import 'package:shared_preferences/shared_preferences.dart';

class DemoSession {
  const DemoSession._();

  static const username = 'admin2512';
  static const password = 'abc123456';
  static const displayUsername = 'admin';
  static const _enabledKey = 'demo.session.enabled.v1';

  static bool matchesCredentials(String inputUsername, String inputPassword) {
    return inputUsername.trim() == username && inputPassword == password;
  }

  static Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? false;
  }

  static Future<void> enable() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, true);
  }

  static Future<void> disable() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_enabledKey);
  }
}
