import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/core/forum_url_resolver.dart';
import 'package:shuyo/data/services/forum_auth_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'forum.auth.cached_cookie_header.webvpn':
          '_t=trust-token; _forum_session=old-session; webvpn-token=portal',
    });
    ForumUrlResolver.configure(useWebVpn: true);
  });

  tearDown(() => ForumUrlResolver.configure(useWebVpn: false));

  test('migrates legacy headers and persists a rotated forum session',
      () async {
    final synchronized = <WebViewCookie>[];
    final service = ForumAuthService(
      cookieLoader: (_) async => const [],
      cookieSetter: (cookie) async => synchronized.add(cookie),
    );

    expect(
        await service.cookieHeader(), contains('_forum_session=old-session'));

    await service.updateFromSetCookieHeaders(
      ForumUrlResolver.baseUri,
      const [
        '_forum_session=new-session; Path=/; Max-Age=3600; Secure; HttpOnly',
      ],
    );

    final header = await service.cookieHeader();
    expect(header, contains('_forum_session=new-session'));
    expect(header, isNot(contains('_forum_session=old-session')));
    // HttpOnly cookies remain in the native jar and are not downgraded to a
    // JavaScript-readable WebView cookie.
    expect(synchronized, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.getString('forum.auth.cookies.v2.webvpn'), contains('expiresAt'));
  });

  test('removes a server-expired cookie without dropping other login cookies',
      () async {
    final service = ForumAuthService(
      cookieLoader: (_) async => const [],
      cookieSetter: (_) async {},
    );

    await service.cookieHeader();
    await service.updateFromSetCookieHeaders(
      ForumUrlResolver.baseUri,
      const ['_forum_session=deleted; Path=/; Max-Age=0'],
    );

    final header = await service.cookieHeader();
    expect(header, isNot(contains('_forum_session=')));
    expect(header, contains('_t=trust-token'));
    expect(header, contains('webvpn-token=portal'));
  });
}
