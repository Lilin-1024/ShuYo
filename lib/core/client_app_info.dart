import 'package:package_info_plus/package_info_plus.dart';

class ClientAppInfo {
  const ClientAppInfo._();

  static const _fallbackVersion = '0.2.0';
  static const _fallbackBuildNumber = 4;
  static const _fallbackAppName = 'ShuYo';
  static const _fallbackPackageName = 'work.shuyo.app';

  static String version = _fallbackVersion;
  static int buildNumber = _fallbackBuildNumber;
  static String appName = _fallbackAppName;
  static String packageName = _fallbackPackageName;

  static Future<void>? _loadFuture;

  static String get displayVersion => '$version+$buildNumber';

  static Future<void> load() {
    return _loadFuture ??= _loadFromPlatform();
  }

  static Future<void> _loadFromPlatform() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version.trim().isEmpty ? _fallbackVersion : info.version;
      buildNumber =
          int.tryParse(info.buildNumber.trim()) ?? _fallbackBuildNumber;
      appName = info.appName.trim().isEmpty ? _fallbackAppName : info.appName;
      packageName = info.packageName.trim().isEmpty
          ? _fallbackPackageName
          : info.packageName;
    } on Object {
      version = _fallbackVersion;
      buildNumber = _fallbackBuildNumber;
      appName = _fallbackAppName;
      packageName = _fallbackPackageName;
    }
  }
}
