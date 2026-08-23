import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}
