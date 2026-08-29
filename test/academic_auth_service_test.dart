import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/core/academic_constants.dart';
import 'package:shuyo/core/academic_url_resolver.dart';
import 'package:shuyo/core/forum_url_resolver.dart';
import 'package:shuyo/data/services/academic_auth_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ForumUrlResolver.configure(useWebVpn: true);
  });

  test('restores a cached campus session when WebView cookies are partial',
      () async {
    final portal = Uri.parse(ForumUrlResolver.webVpnPortalUrl);
    final academic = Uri.parse(AcademicUrlResolver.webVpnBaseUrl);
    final first = AcademicAuthService(
      cookieLoader: (domain) async {
        if (domain.host == portal.host) {
          return [
            WebViewCookie(
              name: 'webvpn-token',
              value: 'portal-session',
              domain: portal.host,
            ),
          ];
        }
        if (domain.host == academic.host) {
          return [
            WebViewCookie(
              name: 'JSESSIONID',
              value: 'academic-session',
              domain: academic.host,
            ),
          ];
        }
        return const [];
      },
      cookieSetter: (_) async {},
    );

    final initialHeader = await first.cookieHeader();
    expect(initialHeader, contains('webvpn-token=portal-session'));
    expect(initialHeader, contains('JSESSIONID=academic-session'));

    final restored = <WebViewCookie>[];
    final restarted = AcademicAuthService(
      cookieLoader: (_) async => const [],
      cookieSetter: (cookie) async => restored.add(cookie),
      webVpnSessionValidator: (_) async => WebVpnSessionStatus.valid,
    );

    expect(await restarted.hasWebVpnSession(), isTrue);
    expect(
      restored.any(
        (cookie) =>
            cookie.name == 'webvpn-token' &&
            cookie.value == 'portal-session' &&
            cookie.domain == portal.host,
      ),
      isTrue,
    );
    expect(
      await restarted.cookieHeader(),
      allOf(
        contains('webvpn-token=portal-session'),
        contains('JSESSIONID=academic-session'),
      ),
    );
  });

  test('does not treat a stale portal token as an authenticated session',
      () async {
    final portal = Uri.parse(ForumUrlResolver.webVpnPortalUrl);
    final service = AcademicAuthService(
      cookieLoader: (domain) async => domain.host == portal.host
          ? [
              WebViewCookie(
                name: 'webvpn-token',
                value: 'stale-session',
                domain: portal.host,
              ),
            ]
          : const [],
      cookieSetter: (_) async {},
      webVpnSessionValidator: (_) async => WebVpnSessionStatus.loginRequired,
    );

    expect(await service.hasWebVpnSession(), isFalse);
  });

  test('keeps a cached account when WebVPN validation is temporarily offline',
      () async {
    final portal = Uri.parse(ForumUrlResolver.webVpnPortalUrl);
    final service = AcademicAuthService(
      cookieLoader: (domain) async => domain.host == portal.host
          ? [
              WebViewCookie(
                name: 'webvpn-token',
                value: 'possibly-valid-session',
                domain: portal.host,
              ),
            ]
          : const [],
      cookieSetter: (_) async {},
      webVpnSessionValidator: (_) async => WebVpnSessionStatus.unavailable,
    );

    expect(await service.hasWebVpnSession(), isTrue);
  });

  test('restores and validates a cached direct campus session', () async {
    ForumUrlResolver.configure(useWebVpn: false);
    final academic = Uri.parse(AcademicConstants.baseUrl);
    final restored = <WebViewCookie>[];
    final service = AcademicAuthService(
      cookieLoader: (_) async => const [],
      cookieSetter: (cookie) async => restored.add(cookie),
      directSessionValidator: (_) async => WebVpnSessionStatus.valid,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'academic.auth.cached_cookies.direct',
      '{"academic":[{"name":"JSESSIONID","value":"direct-session","domain":"${academic.host}","path":"/"}]}',
    );

    expect(await service.hasAcademicSession(), isTrue);
    expect(
      restored.any(
        (cookie) =>
            cookie.name == 'JSESSIONID' && cookie.value == 'direct-session',
      ),
      isTrue,
    );
  });
}
