import 'package:flutter/foundation.dart';
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
    final cachedHeader = await _cachedCookieHeader();
    String? webViewHeader;
    try {
      webViewHeader = await _webViewCookieHeader();
    } on Object {
      webViewHeader = null;
    }
    final merged = mergeCookieHeaders(cachedHeader, webViewHeader);
    if (merged != null) {
      _rememberLastHeader(merged);
    }
    return merged;
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
    for (final domain in [
      Uri.parse('https://${ForumUrlResolver.webVpnHost}'),
      Uri.parse('https://bbs.shu.edu.cn'),
    ]) {
      List<WebViewCookie> cookies;
      try {
        cookies = await _cookieManager.getCookies(domain: domain);
      } on Object {
        continue;
      }
      for (final cookie in cookies) {
        await _cookieManager.setCookie(
          WebViewCookie(
            name: cookie.name,
            value: '',
            domain: cookie.domain,
            path: cookie.path,
          ),
        );
      }
    }
    await clearCachedCookies();
  }

  @visibleForTesting
  static String? mergeCookieHeaders(String? cached, String? webView) {
    final values = _parseCookieHeader(cached)
      ..addAll(_parseCookieHeader(webView));
    return values.isEmpty ? null : _encodeCookieHeader(values);
  }

  static Map<String, String> _parseCookieHeader(String? header) {
    final values = <String, String>{};
    if (header == null || header.trim().isEmpty) return values;
    for (final part in header.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final name = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) values[name] = value;
    }
    return values;
  }

  static String _encodeCookieHeader(Map<String, String> values) =>
      values.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
}

extension ForumAuthCookieMaintenance on ForumAuthService {
  Future<void> removeCachedCookieNames(Set<String> names) async {
    if (names.isEmpty) return;
    final prefs = await _preferencesLoader();
    for (final mode in ForumAccessMode.values) {
      final key = _cacheKey(mode);
      final filtered = ForumAuthService._parseCookieHeader(prefs.getString(key))
        ..removeWhere((name, _) => names.contains(name));
      if (filtered.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(
          key,
          ForumAuthService._encodeCookieHeader(filtered),
        );
      }
    }
    final current = _lastCookieHeader;
    if (current != null) {
      final filtered = ForumAuthService._parseCookieHeader(current)
        ..removeWhere((name, _) => names.contains(name));
      _lastCookieHeader = filtered.isEmpty
          ? null
          : ForumAuthService._encodeCookieHeader(filtered);
    }
  }
}
