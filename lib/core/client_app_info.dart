import 'dart:io' show Platform;

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
      final parsedBuildNumber = int.tryParse(info.buildNumber.trim());
      buildNumber = parsedBuildNumber == null
          ? _fallbackBuildNumber
          : _logicalBuildNumber(parsedBuildNumber);
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

  /// Flutter adds an ABI-specific offset when an APK is built with
  /// `--split-per-abi` (1000/2000/4000 for armeabi-v7a/arm64-v8a/x86_64).
  /// package_info_plus exposes Android's resulting versionCode, so strip that
  /// offset before using the value for update checks and telemetry. Without
  /// this, build 16 is reported as 2016 by an arm64 APK and update checks can
  /// never match the backend's logical build number.
  static int _logicalBuildNumber(int value) {
    if (!Platform.isAndroid) {
      return value;
    }
    for (final offset in const [4000, 2000, 1000]) {
      if (value >= offset && value < offset + 1000) {
        return value - offset;
      }
    }
    return value;
  }
}
