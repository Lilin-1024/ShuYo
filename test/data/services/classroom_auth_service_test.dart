import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/core/classroom_url_resolver.dart';
import 'package:shuyo/data/services/classroom_auth_service.dart';
import 'package:shuyo/data/services/session_cookie_jar.dart';
import 'package:shuyo/data/services/webvpn_session_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ClassroomUrlResolver.configure(useWebVpn: true);
  });

  tearDown(() => ClassroomUrlResolver.configure(useWebVpn: false));

  test(
    'uses the current portal token instead of an older proxy shadow',
    () async {
      final service = ClassroomAuthService(
        cookieLoader: (uri) async => uri.host == 'webvpn.shu.edu.cn'
            ? const [
                SessionCookie(
                  name: 'webvpn-token',
                  value: 'fresh',
                  domain: 'webvpn.shu.edu.cn',
                ),
                SessionCookie(
                  name: 'JSESSIONID',
                  value: 'portal-session',
                  domain: 'webvpn.shu.edu.cn',
                ),
              ]
            : const [
                SessionCookie(
                  name: 'webvpn-token',
                  value: 'stale',
                  domain: ClassroomUrlResolver.webVpnHost,
                ),
                SessionCookie(
                  name: 'JSESSIONID',
                  value: 'classroom-session',
                  domain: ClassroomUrlResolver.webVpnHost,
                ),
              ],
      );

      final header = await service.cookieHeader();
      expect(header, contains('webvpn-token=fresh'));
      expect(header, contains('JSESSIONID=classroom-session'));
      expect(header, isNot(contains('stale')));
    },
  );

  test('recovers the saved portal token when the cookie jar is empty',
      () async {
    SharedPreferences.setMockInitialValues({
      WebVpnSessionStore.cachedCookiesKey: jsonEncode({
        'portal': [
          {
            'name': 'webvpn-token',
            'value': 'saved-token',
            'domain': 'webvpn.shu.edu.cn',
            'path': '/',
          },
        ],
      }),
    });
    final service = ClassroomAuthService(cookieLoader: (_) async => const []);

    expect(await service.cookieHeader(), 'webvpn-token=saved-token');
  });

  test('does not forward a portal backend session to the classroom', () async {
    final service = ClassroomAuthService(
      cookieLoader: (uri) async => uri.host == 'webvpn.shu.edu.cn'
          ? const [
              SessionCookie(
                name: 'webvpn-token',
                value: 'gateway',
                domain: 'webvpn.shu.edu.cn',
              ),
              SessionCookie(
                name: 'JSESSIONID',
                value: 'portal-only',
                domain: 'webvpn.shu.edu.cn',
              ),
            ]
          : const [],
    );

    expect(await service.cookieHeader(), 'webvpn-token=gateway');
  });

  test(
    'requires the gateway token rather than accepting unrelated cookies',
    () async {
      final service = ClassroomAuthService(
        cookieLoader: (_) async => const [
          SessionCookie(
            name: 'JSESSIONID',
            value: 'backend-only',
            domain: ClassroomUrlResolver.webVpnHost,
          ),
        ],
      );

      expect(await service.cookieHeader(), isNull);
    },
  );

  test('does not read cookies in direct mode', () async {
    ClassroomUrlResolver.configure(useWebVpn: false);
    final service = ClassroomAuthService(
      cookieLoader: (_) async =>
          throw StateError('direct access must not read cookies'),
    );

    expect(await service.cookieHeader(), isNull);
  });

  test('can recover a cached token when cookie reads fail', () async {
    SharedPreferences.setMockInitialValues({
      WebVpnSessionStore.cachedCookiesKey:
          '{"portal":[{"name":"webvpn-token","value":"saved"}]}',
    });
    final service = ClassroomAuthService(
      cookieLoader: (_) async => throw StateError('cookie jar unavailable'),
    );

    expect(await service.cookieHeader(), 'webvpn-token=saved');
    await (await SharedPreferences.getInstance()).remove(
      WebVpnSessionStore.cachedCookiesKey,
    );
    expect(await service.cookieHeader(), isNull);
  });

  test(
    'a live proxy token is usable when the portal read is unavailable',
    () async {
      final service = ClassroomAuthService(
        cookieLoader: (uri) async {
          if (uri.host == 'webvpn.shu.edu.cn') {
            throw StateError('portal unavailable');
          }
          return const [
            SessionCookie(
              name: 'webvpn-token',
              value: 'proxy',
              domain: ClassroomUrlResolver.webVpnHost,
            ),
          ];
        },
      );

      expect(await service.cookieHeader(), 'webvpn-token=proxy');
    },
  );

  test(
    'reads path-scoped classroom cookies from the actual request URI',
    () async {
      final target = ClassroomUrlResolver.uri('/build/findBuildRoomType');
      final service = ClassroomAuthService(
        cookieLoader: (uri) async {
          if (uri.host == 'webvpn.shu.edu.cn') {
            return const [
              SessionCookie(
                name: 'webvpn-token',
                value: 'gateway',
                domain: 'webvpn.shu.edu.cn',
              ),
            ];
          }
          expect(uri, target);
          return const [
            SessionCookie(
              name: 'JSESSIONID',
              value: 'building-session',
              domain: ClassroomUrlResolver.webVpnHost,
              path: '/build',
            ),
          ];
        },
      );

      expect(
        await service.cookieHeader(targetUri: target),
        contains('JSESSIONID=building-session'),
      );
    },
  );

  test(
    'ignores malformed caches and cookies from a non-portal cache group',
    () async {
      final service = ClassroomAuthService(cookieLoader: (_) async => const []);
      final prefs = await SharedPreferences.getInstance();
      for (final raw in [
        'not-json',
        '[]',
        '{"portal":{}}',
        '{"academic":[{"name":"webvpn-token","value":"unrelated"}]}',
      ]) {
        await prefs.setString(WebVpnSessionStore.cachedCookiesKey, raw);
        expect(await service.cookieHeader(), isNull);
      }
    },
  );

  test('direct classroom requests do not read session cookies', () async {
    ClassroomUrlResolver.configure(useWebVpn: false);
    var calls = 0;
    final auth = ClassroomAuthService(
      cookieLoader: (_) async {
        calls++;
        return const [];
      },
    );

    expect(await auth.cookieHeader(), isNull);
    expect(calls, 0);
  });

  test(
    'proxied classroom requests read portal and classroom cookies',
    () async {
      final hosts = <String>[];
      final auth = ClassroomAuthService(
        cookieLoader: (uri) async {
          hosts.add(uri.host);
          if (uri.host == 'webvpn.shu.edu.cn') {
            return const [
              SessionCookie(
                name: 'webvpn-token',
                value: 'session',
                domain: 'webvpn.shu.edu.cn',
              ),
            ];
          }
          return [
            SessionCookie(name: 'classroom', value: 'ok', domain: uri.host),
          ];
        },
      );

      final header = await auth.cookieHeader();
      expect(header, contains('webvpn-token=session'));
      expect(header, contains('classroom=ok'));
      expect(hosts, ['webvpn.shu.edu.cn', ClassroomUrlResolver.webVpnHost]);
    },
  );

  test(
    'a restored jar does not forward inherited portal backend cookies',
    () async {
      final jar = SessionCookieJar();
      for (final cookie in const [
        SessionCookie(
          name: 'webvpn-token',
          value: 'fresh',
          domain: 'webvpn.shu.edu.cn',
        ),
        SessionCookie(
          name: 'JSESSIONID',
          value: 'portal-only',
          domain: 'webvpn.shu.edu.cn',
        ),
        SessionCookie(
          name: 'webvpn-token',
          value: 'stale',
          domain: ClassroomUrlResolver.webVpnHost,
        ),
        SessionCookie(
          name: 'classroom-session',
          value: 'building-session',
          domain: ClassroomUrlResolver.webVpnHost,
          path: '/build',
        ),
      ]) {
        await jar.setCookie(cookie);
      }

      final restarted = ClassroomAuthService(cookieJar: SessionCookieJar());
      final header = await restarted.cookieHeader(
        targetUri: ClassroomUrlResolver.uri('/build/findBuildRoomType'),
      );

      expect(header, contains('webvpn-token=fresh'));
      expect(header, contains('classroom-session=building-session'));
      expect(header, isNot(contains('portal-only')));
      expect(header, isNot(contains('stale')));
    },
  );

  test('an explicit direct URI never receives WebVPN authentication', () async {
    var calls = 0;
    final auth = ClassroomAuthService(
      cookieLoader: (_) async {
        calls++;
        return const [];
      },
    );

    expect(
      await auth.cookieHeader(
        targetUri: Uri.parse('${ClassroomUrlResolver.directBaseUrl}/build'),
      ),
      isNull,
    );
    expect(calls, 0);
  });
}
