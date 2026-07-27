import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/forum_url_resolver.dart';

class ForumAuthService {
  ForumAuthService({
    WebViewCookieManager? cookieManager,
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : _cookieManager = cookieManager ?? WebViewCookieManager(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final WebViewCookieManager _cookieManager;
  final Future<SharedPreferences> Function() _preferencesLoader;
  String? _lastCookieHeader;
  ForumAccessMode? _lastCookieMode;

  static const _cachedDirectCookieHeaderKey =
      'forum.auth.cached_cookie_header.direct';
  static const _cachedWebVpnCookieHeaderKey =
      'forum.auth.cached_cookie_header.webvpn';

  Future<String?> cookieHeader() async {
    String? webViewHeader;
    try {
      webViewHeader = await _webViewCookieHeader();
    } on Object {
      webViewHeader = null;
    }
    if (webViewHeader != null && webViewHeader.isNotEmpty) {
      _rememberLastHeader(webViewHeader);
      return webViewHeader;
    }
    final cachedHeader = await _cachedCookieHeader();
    if (cachedHeader != null && cachedHeader.isNotEmpty) {
      _rememberLastHeader(cachedHeader);
      return cachedHeader;
    }
    return null;
  }

  Future<void> persistLastCookieHeader() async {
    final header = _lastCookieHeader;
    if (header == null || header.isEmpty) {
      return;
    }
    final prefs = await _preferencesLoader();
    await prefs.setString(
        _cacheKey(_lastCookieMode ?? ForumUrlResolver.mode), header);
  }

  Future<void> clearCachedCookies() async {
    final prefs = await _preferencesLoader();
    await Future.wait([
      prefs.remove(_cachedDirectCookieHeaderKey),
      prefs.remove(_cachedWebVpnCookieHeaderKey),
    ]);
    _lastCookieHeader = null;
    _lastCookieMode = null;
  }

  Future<String?> _webViewCookieHeader() async {
    final cookies = [
      if (ForumUrlResolver.usesWebVpn)
        ...await _cookieManager.getCookies(
          domain: Uri.parse(ForumUrlResolver.webVpnPortalUrl),
        ),
      ...await _cookieManager.getCookies(
        domain: ForumUrlResolver.baseUri,
      ),
    ];
    final values = <String, String>{};
    for (final cookie in cookies) {
      if (cookie.name.isNotEmpty && cookie.value.isNotEmpty) {
        values[cookie.name] = cookie.value;
      }
    }
    if (values.isEmpty) {
      return null;
    }
    return values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  Future<String?> _cachedCookieHeader() async {
    final prefs = await _preferencesLoader();
    final header = prefs.getString(_cacheKey(ForumUrlResolver.mode));
    if (header == null || header.trim().isEmpty) {
      return null;
    }
    return header;
  }

  String _cacheKey(ForumAccessMode mode) {
    return switch (mode) {
      ForumAccessMode.direct => _cachedDirectCookieHeaderKey,
      ForumAccessMode.webVpn => _cachedWebVpnCookieHeaderKey,
    };
  }

  void _rememberLastHeader(String header) {
    _lastCookieHeader = header;
    _lastCookieMode = ForumUrlResolver.mode;
  }

  Future<bool> hasForumCookies() async {
    final header = await cookieHeader();
    return header != null && header.isNotEmpty;
  }

  Future<void> clearCookies() async {
    await _cookieManager.clearCookies();
    await clearCachedCookies();
  }
}
