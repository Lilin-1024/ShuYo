import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'client_settings_service.dart';

/// Performs one-time migrations which intentionally make a major release look
/// like a fresh install to the user.
///
/// The marker is written only after every cleanup step has completed.  This is
/// important when an update is interrupted halfway through: the next launch
/// will retry the cleanup instead of considering stale credentials migrated.
class AppDataMigrationService {
  AppDataMigrationService({
    Future<SharedPreferences> Function()? preferencesLoader,
    Future<void> Function()? webViewCookieClearer,
    Future<Directory> Function()? cacheDirectoryLoader,
  })  : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _webViewCookieClearer = webViewCookieClearer ?? _clearWebViewCookies,
        _cacheDirectoryLoader =
            cacheDirectoryLoader ?? getApplicationCacheDirectory;

  /// Increment this for a future release which needs another clean migration.
  static const currentSchemaVersion = 2;
  static const schemaVersionKey = 'client.data.schema.version';

  final Future<SharedPreferences> Function() _preferencesLoader;
  final Future<void> Function() _webViewCookieClearer;
  final Future<Directory> Function() _cacheDirectoryLoader;

  Future<void> migrateIfNeeded() async {
    final preferences = await _preferencesLoader();
    final version = preferences.getInt(schemaVersionKey);
    if (version != null && version >= currentSchemaVersion) {
      return;
    }

    // Clearing the complete preferences store also covers keys introduced by
    // older builds which are not known to this source tree.  The schema marker
    // is restored below, after cleanup, so this operation is still one-shot.
    await preferences.clear();
    await _webViewCookieClearer();
    await _clearForumImageCache();

    // Explicitly persist the intended fresh-install defaults.  Keeping these
    // values here documents the migration contract and avoids depending on a
    // later service's implicit defaults.
    await preferences.setBool(
        ClientSettingsService.autoUseWebVpnProxyKey, true);
    await preferences.setBool(
      ClientSettingsService.startupOnboardingCompletedKey,
      false,
    );
    await preferences.setInt(schemaVersionKey, currentSchemaVersion);
  }

  Future<void> _clearForumImageCache() async {
    final root = await _cacheDirectoryLoader();
    final directory = Directory('${root.path}/forum-images');
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  static Future<void> _clearWebViewCookies() async {
    // clearCookies() clears the platform WebView cookie store, including
    // cookies whose domain/path is not currently known to the client.  This is
    // more complete than deleting only the handful of hosts used today.
    await WebViewCookieManager().clearCookies();
  }
}
