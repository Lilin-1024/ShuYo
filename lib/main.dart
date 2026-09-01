import 'dart:io';

import 'package:flutter/material.dart';

import 'app/shuyo_app.dart';
import 'core/shuyo_http_overrides.dart';
import 'data/services/app_data_migration_service.dart';
import 'data/services/client_settings_service.dart';
import 'shared/theme/shuyo_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = ShuYoHttpOverrides();
  final initialThemeSettings = await _loadInitialThemeSettings();
  runApp(
    ShuYoApp(
      initialThemeId: initialThemeSettings.themeId,
      initialFollowSystemTheme: initialThemeSettings.followSystemTheme,
    ),
  );
}

Future<_InitialThemeSettings> _loadInitialThemeSettings() async {
  try {
    // Theme preferences must be read after the migration, since the migration
    // can intentionally clear the complete preferences store.
    await AppDataMigrationService().migrateIfNeeded();
    final settingsService = ClientSettingsService();
    return _InitialThemeSettings(
      themeId: ShuYoThemes.byId(await settingsService.loadThemeId()).id,
      followSystemTheme: await settingsService.loadFollowSystemTheme(),
    );
  } on Object {
    // Keep startup recoverable if a platform preference or migration service
    // is temporarily unavailable. ShuYoApp will still surface startup errors.
    return const _InitialThemeSettings(
      themeId: ShuYoThemes.defaultId,
      followSystemTheme: false,
    );
  }
}

class _InitialThemeSettings {
  const _InitialThemeSettings({
    required this.themeId,
    required this.followSystemTheme,
  });

  final String themeId;
  final bool followSystemTheme;
}
