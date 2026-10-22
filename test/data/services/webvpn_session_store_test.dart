import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/session_cookie_jar.dart';
import 'package:shuyo/data/services/webvpn_session_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('clears a rejected WebVPN session without touching unrelated cookies',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      WebVpnSessionStore.cachedCookiesKey,
      '{"portal":[{"name":"webvpn-token","value":"stale","domain":"webvpn.shu.edu.cn","path":"/"}]}',
    );
    final cleared = <SessionCookie>[];
    final store = WebVpnSessionStore(
      cookieLoader: (domain) async => [
        SessionCookie(
          name: 'webvpn-token',
          value: 'stale',
          domain: domain.host,
        ),
        SessionCookie(
          name: 'SHU_OAUTH2',
          value: 'oauth-session',
          domain: domain.host,
        ),
      ],
      cookieSetter: (cookie) async => cleared.add(cookie),
    );

    await store.clearSession();

    expect(prefs.getString(WebVpnSessionStore.cachedCookiesKey), isNull);
    expect(
      cleared.where((cookie) => cookie.name == 'webvpn-token'),
      isNotEmpty,
    );
    expect(
      cleared.where((cookie) => cookie.name == 'SHU_OAUTH2').every(
            (cookie) =>
                cookie.domain.contains('oauth-shu-edu-cn') ||
                cookie.domain.contains('newsso-shu-edu-cn'),
          ),
      isTrue,
    );
  });

  test('detects a persisted WebVPN token while the switch is off', () async {
    SharedPreferences.setMockInitialValues({
      WebVpnSessionStore.cachedCookiesKey:
          '{"portal":[{"name":"webvpn-token","value":"saved","domain":"webvpn.shu.edu.cn","path":"/"}]}',
    });
    final store = WebVpnSessionStore(
      cookieLoader: (_) async => const [],
      cookieSetter: (_) async {},
    );

    expect(await store.hasStoredSession(), isTrue);
  });
}
