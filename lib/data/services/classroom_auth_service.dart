import 'dart:convert';

import '../../core/classroom_url_resolver.dart';
import '../../core/webvpn_urls.dart';
import 'secure_app_store.dart';
import 'session_cookie_jar.dart';
import 'webvpn_session_store.dart';

class ClassroomAuthService {
  ClassroomAuthService({
    SessionCookieJar? cookieJar,
    Future<List<SessionCookie>> Function(Uri)? cookieLoader,
    SecureAppStore? secureStore,
  })  : _cookieJar = cookieJar,
        _secureStore = secureStore ?? SecureAppStore() {
    _cookieLoader = cookieLoader ??
        (uri) =>
            (_cookieJar ??= SessionCookieJar.shared).getCookies(domain: uri);
  }

  SessionCookieJar? _cookieJar;
  final SecureAppStore _secureStore;
  late final Future<List<SessionCookie>> Function(Uri) _cookieLoader;

  Future<String?> cookieHeader({Uri? targetUri}) async {
    final target = targetUri ?? ClassroomUrlResolver.baseUri;
    if (target.host != ClassroomUrlResolver.webVpnHost) {
      return null;
    }
    final portal = Uri.parse(WebVpnUrls.portal);
    final portalCookies = await _loadCookies(portal);
    final classroomCookies = await _loadCookies(target);
    // A proxy can retain an older token. Prefer the current portal session,
    // and recover its saved copy when neither live source is available.
    final token = _webVpnToken(portalCookies) ??
        _webVpnToken(classroomCookies) ??
        await _cachedPortalToken();
    if (token == null) return null;

    final values = <String, String>{};
    for (final cookie in classroomCookies) {
      // The jar also matches parent domains. Only the gateway token, not
      // the portal's backend cookies, belongs on a classroom request.
      final domain = cookie.domain.toLowerCase().replaceFirst(
            RegExp(r'^\.'),
            '',
          );
      if (cookie.name.isNotEmpty &&
          cookie.name != 'webvpn-token' &&
          cookie.value.isNotEmpty &&
          domain != portal.host) {
        values.putIfAbsent(cookie.name, () => cookie.value);
      }
    }
    values['webvpn-token'] = token;
    return values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  Future<List<SessionCookie>> _loadCookies(Uri uri) async {
    try {
      return await _cookieLoader(uri);
    } on Object {
      // One unavailable source must not discard the other source or the
      // securely saved session.
      return const [];
    }
  }

  String? _webVpnToken(Iterable<SessionCookie> cookies) {
    for (final cookie in cookies) {
      if (cookie.name == 'webvpn-token' && cookie.value.isNotEmpty) {
        return cookie.value;
      }
    }
    return null;
  }

  Future<String?> _cachedPortalToken() async {
    try {
      final raw = await _secureStore.read(WebVpnSessionStore.cachedCookiesKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['portal'] is! List) return null;
      for (final cookie in decoded['portal'] as List) {
        if (cookie is! Map || cookie['name'] != 'webvpn-token') continue;
        final value = cookie['value'];
        if (value is String && value.isNotEmpty) return value;
      }
    } on Object {
      // A malformed cache or unavailable secure store does not establish
      // an authenticated session.
    }
    return null;
  }
}
