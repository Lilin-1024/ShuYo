import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/app_data_migration_service.dart';
import 'package:shuyo/data/services/session_cookie_jar.dart';

void main() {
  test('removes forum drafts and cookies but preserves campus and WebVPN state',
      () async {
    final root = await Directory.systemTemp.createTemp('shuyo-migration-');
    addTearDown(() => root.delete(recursive: true));
    final images = Directory('${root.path}/forum-images')
      ..createSync(recursive: true);
    File('${images.path}/old.bin').writeAsBytesSync([1, 2, 3]);
    SharedPreferences.setMockInitialValues({
      'forum.composerDraft.v2.alice.draft': 'old draft',
      'forum.account.snapshot.v1.webvpn': 'old account',
      'client.backend.presence.day.42': '2026-09-26',
      'academic.schedule.cache': 'saved schedule',
      'academic.account.student_id': '25120000',
      'academic.auth.cached_cookies.webvpn': 'saved session',
      'client.network.webvpn.enabled': true,
      'client.theme.id': 'dark',
    });
    final cleared = <SessionCookie>[];
    var loads = 0;
    final service = AppDataMigrationService(
      cacheDirectoryLoader: () async => root,
      cookieLoader: (domain) async {
        loads++;
        return [
          SessionCookie(
              name: '_forum_session', value: 'old', domain: domain.host),
          SessionCookie(
              name: 'webvpn-token', value: 'keep', domain: domain.host),
        ];
      },
      cookieSetter: (cookie) async => cleared.add(cookie),
    );
    await service.migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('forum.composerDraft.v2.alice.draft'), isNull);
    expect(prefs.getString('forum.account.snapshot.v1.webvpn'), isNull);
    expect(prefs.getString('client.backend.presence.day.42'), isNull);
    expect(prefs.getString('academic.schedule.cache'), 'saved schedule');
    expect(prefs.getString('academic.account.student_id'), '25120000');
    expect(prefs.getString('academic.auth.cached_cookies.webvpn'),
        'saved session');
    expect(prefs.getBool('client.network.webvpn.enabled'), isTrue);
    expect(prefs.getString('client.theme.id'), 'dark');
    expect(await images.exists(), isFalse);
    expect(cleared, hasLength(2));
    expect(
        cleared.every((cookie) =>
            cookie.name == '_forum_session' && cookie.value.isEmpty),
        isTrue);
    expect(prefs.getInt(AppDataMigrationService.schemaVersionKey), 4);
    await service.migrateIfNeeded();
    expect(loads, 2);
  });

  test('retries when cookie cleanup fails', () async {
    SharedPreferences.setMockInitialValues(
        {'forum.composerDraft.v2.a.b': 'draft'});
    final service = AppDataMigrationService(
      cacheDirectoryLoader: () async => Directory.systemTemp,
      cookieLoader: (_) async => throw StateError('cookie failure'),
      cookieSetter: (_) async {},
    );
    await service.migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(AppDataMigrationService.schemaVersionKey), isNull);
  });
}
