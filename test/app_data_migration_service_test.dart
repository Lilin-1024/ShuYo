import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/app_data_migration_service.dart';

void main() {
  test('clears legacy preferences and image cache once', () async {
    final root = await Directory.systemTemp.createTemp('shuyo-migration-');
    addTearDown(() => root.delete(recursive: true));
    final imageDir = Directory('${root.path}/forum-images')
      ..createSync(recursive: true);
    File('${imageDir.path}/old.bin').writeAsBytesSync([1, 2, 3]);

    SharedPreferences.setMockInitialValues({
      'academic.auth.cached_cookies.webvpn': 'legacy',
      'forum.account.snapshot.v1.webvpn': 'legacy',
      'client.onboarding.startup.completed': true,
      'client.network.webvpn.auto_proxy': false,
    });
    var cookieClearCount = 0;
    final service = AppDataMigrationService(
      webViewCookieClearer: () async => cookieClearCount++,
      cacheDirectoryLoader: () async => root,
    );

    await service.migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('academic.auth.cached_cookies.webvpn'), isNull);
    expect(prefs.getString('forum.account.snapshot.v1.webvpn'), isNull);
    expect(prefs.getBool('client.onboarding.startup.completed'), isFalse);
    expect(prefs.getBool('client.network.webvpn.auto_proxy'), isTrue);
    expect(prefs.getInt(AppDataMigrationService.schemaVersionKey),
        AppDataMigrationService.currentSchemaVersion);
    expect(await imageDir.exists(), isFalse);
    expect(cookieClearCount, 1);

    await service.migrateIfNeeded();
    expect(cookieClearCount, 1);
  });

  test('does not write marker when cleanup fails', () async {
    SharedPreferences.setMockInitialValues({'legacy': true});
    final service = AppDataMigrationService(
      webViewCookieClearer: () async => throw StateError('cookie failure'),
      cacheDirectoryLoader: () async => Directory.systemTemp,
    );

    await expectLater(service.migrateIfNeeded(), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(AppDataMigrationService.schemaVersionKey), isNull);
  });
}
