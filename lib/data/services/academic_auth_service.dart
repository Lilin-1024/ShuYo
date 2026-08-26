import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/academic_constants.dart';
import '../../core/academic_url_resolver.dart';
import '../../core/client_user_agent.dart';
import '../../core/forum_url_resolver.dart';

enum WebVpnSessionStatus { valid, loginRequired, unavailable }

class AcademicAuthService {
  AcademicAuthService({
    WebViewCookieManager? cookieManager,
    Future<SharedPreferences> Function()? preferencesLoader,
    Future<List<WebViewCookie>> Function(Uri domain)? cookieLoader,
    Future<void> Function(WebViewCookie cookie)? cookieSetter,
    Future<WebVpnSessionStatus> Function(String cookieHeader)?
        webVpnSessionValidator,
  })  : _cookieManager = cookieManager ??
            (cookieLoader == null || cookieSetter == null
                ? WebViewCookieManager()
                : null),
        _preferencesLoader =
            preferencesLoader ?? SharedPreferences.getInstance {
    _cookieLoader =
        cookieLoader ?? (domain) => _cookieManager!.getCookies(domain: domain);
    _cookieSetter = cookieSetter ?? _cookieManager!.setCookie;
    _webVpnSessionValidator =
        webVpnSessionValidator ?? _validateWebVpnSessionOverNetwork;
  }

  static const _cachedDirectCookiesKey = 'academic.auth.cached_cookies.direct';
  static const _cachedWebVpnCookiesKey = 'academic.auth.cached_cookies.webvpn';
  static const _portalGroup = 'portal';
  static const _academicGroup = 'academic';

  final WebViewCookieManager? _cookieManager;
  final Future<SharedPreferences> Function() _preferencesLoader;
  late final Future<List<WebViewCookie>> Function(Uri domain) _cookieLoader;
  late final Future<void> Function(WebViewCookie cookie) _cookieSetter;
  late final Future<WebVpnSessionStatus> Function(String cookieHeader)
      _webVpnSessionValidator;

  Future<Set<String>> clearCookies() async {
    // These shared authentication cookies may only exist in the persisted
    // native cache after a partial WebView restore, so remove them from the
    // forum store even when the live cookie query returns nothing.
    final clearedSharedNames = <String>{'webvpn-token', 'SHU_OAUTH2'};
    final domains = <(Uri, bool)>[
      (Uri.parse(ForumUrlResolver.webVpnPortalUrl), true),
      (Uri.parse(AcademicConstants.baseUrl), false),
      (Uri.parse(AcademicUrlResolver.webVpnBaseUrl), false),
      (Uri.parse('https://oauth.shu.edu.cn'), true),
      (Uri.parse('https://https-oauth-shu-edu-cn-443.webvpn.shu.edu.cn'), true),
      (
        Uri.parse('https://https-newsso-shu-edu-cn-443.webvpn.shu.edu.cn'),
        true
      ),
    ];
    for (final (domain, sharedWithForum) in domains) {
      List<WebViewCookie> cookies;
      try {
        cookies = await _cookieLoader(domain);
      } on Object {
        continue;
      }
      for (final cookie in cookies) {
        if (sharedWithForum) clearedSharedNames.add(cookie.name);
        await _cookieSetter(
          WebViewCookie(
            name: cookie.name,
            value: '',
            domain: cookie.domain,
            path: cookie.path,
          ),
        );
      }
    }
    final prefs = await _preferencesLoader();
    await Future.wait([
      prefs.remove(_cachedDirectCookiesKey),
      prefs.remove(_cachedWebVpnCookiesKey),
    ]);
    return clearedSharedNames;
  }

  Future<bool> hasWebVpnSession() async {
    final status = await validateWebVpnSession();
    // A transport failure does not prove that the user was logged out. Keep
    // the cached account available and retry validation with the next forum
    // recovery instead of destroying a potentially valid session.
    return status != WebVpnSessionStatus.loginRequired;
  }

  Future<WebVpnSessionStatus> validateWebVpnSession() async {
    final cached = await _loadCachedCookies(webVpn: true);
    final live = await _loadLiveCookies(webVpn: true);
    final merged = _mergeCookieGroups(cached, live);
    await _persistCookies(merged, webVpn: true);
    await _restoreCookies(merged);
    final hasToken = merged[_portalGroup]?.any(
          (cookie) => cookie.name == 'webvpn-token' && cookie.value.isNotEmpty,
        ) ==
        true;
    if (!hasToken) return WebVpnSessionStatus.loginRequired;
    final header = (merged[_portalGroup] ?? const <WebViewCookie>[])
        .where((cookie) => cookie.name.isNotEmpty && cookie.value.isNotEmpty)
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
    if (header.isEmpty) return WebVpnSessionStatus.loginRequired;
    final status = await _webVpnSessionValidator(header);
    if (kDebugMode) {
      debugPrint('[LEHU_WEBVPN] portal-session validation=${status.name}');
    }
    return status;
  }

  Future<WebVpnSessionStatus> _validateWebVpnSessionOverNetwork(
    String cookieHeader,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    var current = Uri.parse('${ForumUrlResolver.webVpnBaseUrl}/latest');
    try {
      for (var redirectCount = 0; redirectCount < 10; redirectCount++) {
        final request = await client.getUrl(current).timeout(
              const Duration(seconds: 5),
            );
        request.followRedirects = false;
        request.headers
          ..set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml')
          ..set(HttpHeaders.userAgentHeader, ClientUserAgent.mobileBrowser)
          ..set(HttpHeaders.cookieHeader, cookieHeader);
        final response = await request.close().timeout(
              const Duration(seconds: 7),
            );
        final location = response.headers.value(HttpHeaders.locationHeader);
        final statusCode = response.statusCode;
        await response.drain<void>().timeout(const Duration(seconds: 7));
        if (statusCode >= 300 && statusCode < 400 && location != null) {
          current = current.resolve(location);
          continue;
        }
        if (current.host == ForumUrlResolver.webVpnHost) {
          return WebVpnSessionStatus.valid;
        }
        if (_isWebVpnLoginUri(current) ||
            statusCode == 401 ||
            statusCode == 403) {
          return WebVpnSessionStatus.loginRequired;
        }
        return WebVpnSessionStatus.unavailable;
      }
      return WebVpnSessionStatus.unavailable;
    } on TimeoutException {
      return WebVpnSessionStatus.unavailable;
    } on SocketException {
      return WebVpnSessionStatus.unavailable;
    } on HandshakeException {
      return WebVpnSessionStatus.unavailable;
    } on HttpException {
      return WebVpnSessionStatus.unavailable;
    } on Object {
      return WebVpnSessionStatus.unavailable;
    } finally {
      client.close(force: true);
    }
  }

  bool _isWebVpnLoginUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host == Uri.parse(ForumUrlResolver.webVpnPortalUrl).host) return true;
    return host == 'oauth.shu.edu.cn' ||
        host.endsWith('.oauth.shu.edu.cn') ||
        host.contains('oauth-shu-edu-cn') ||
        host.contains('newsso-shu-edu-cn');
  }

  Future<String?> cookieHeader() async {
    final webVpn = AcademicUrlResolver.usesWebVpn;
    final cached = await _loadCachedCookies(webVpn: webVpn);
    final live = await _loadLiveCookies(webVpn: webVpn);
    final merged = _mergeCookieGroups(cached, live);
    await _persistCookies(merged, webVpn: webVpn);

    final values = <String, String>{};
    for (final group in [if (webVpn) _portalGroup, _academicGroup]) {
      for (final cookie in merged[group] ?? const <WebViewCookie>[]) {
        if (cookie.name.isNotEmpty && cookie.value.isNotEmpty) {
          values[cookie.name] = cookie.value;
        }
      }
    }
    if (values.isEmpty) return null;
    return values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  Future<Map<String, List<WebViewCookie>>> _loadLiveCookies({
    required bool webVpn,
  }) async {
    final groups = <String, List<WebViewCookie>>{};
    if (webVpn) {
      groups[_portalGroup] = await _cookiesFor(
        Uri.parse(ForumUrlResolver.webVpnPortalUrl),
      );
    }
    groups[_academicGroup] = await _cookiesFor(
      Uri.parse(
        webVpn ? AcademicUrlResolver.webVpnBaseUrl : AcademicConstants.baseUrl,
      ),
    );
    return groups;
  }

  Future<List<WebViewCookie>> _cookiesFor(Uri domain) async {
    try {
      return (await _cookieLoader(domain))
          .where((cookie) => cookie.name.isNotEmpty && cookie.value.isNotEmpty)
          .map(
            (cookie) => WebViewCookie(
              name: cookie.name,
              value: cookie.value,
              domain: cookie.domain.isEmpty ? domain.host : cookie.domain,
              path: cookie.path.isEmpty ? '/' : cookie.path,
            ),
          )
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<Map<String, List<WebViewCookie>>> _loadCachedCookies({
    required bool webVpn,
  }) async {
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(_cacheKey(webVpn));
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final groups = <String, List<WebViewCookie>>{};
      for (final entry in decoded.entries) {
        if (entry.value is! List) continue;
        final cookies = <WebViewCookie>[];
        for (final item in entry.value as List) {
          if (item is! Map) continue;
          final name = item['name']?.toString() ?? '';
          final value = item['value']?.toString() ?? '';
          final domain = item['domain']?.toString() ?? '';
          final path = item['path']?.toString() ?? '/';
          if (name.isEmpty || value.isEmpty || domain.isEmpty) continue;
          cookies.add(
            WebViewCookie(
              name: name,
              value: value,
              domain: domain,
              path: path.isEmpty ? '/' : path,
            ),
          );
        }
        if (cookies.isNotEmpty) groups[entry.key.toString()] = cookies;
      }
      return groups;
    } on Object {
      return const {};
    }
  }

  Map<String, List<WebViewCookie>> _mergeCookieGroups(
    Map<String, List<WebViewCookie>> cached,
    Map<String, List<WebViewCookie>> live,
  ) {
    final groups = <String, List<WebViewCookie>>{};
    for (final group in {...cached.keys, ...live.keys}) {
      final values = <String, WebViewCookie>{};
      for (final cookie in cached[group] ?? const <WebViewCookie>[]) {
        values[_cookieKey(cookie)] = cookie;
      }
      for (final cookie in live[group] ?? const <WebViewCookie>[]) {
        values[_cookieKey(cookie)] = cookie;
      }
      if (values.isNotEmpty) groups[group] = values.values.toList();
    }
    return groups;
  }

  String _cookieKey(WebViewCookie cookie) =>
      '${cookie.name}\u0000${cookie.domain}\u0000${cookie.path}';

  Future<void> _persistCookies(
    Map<String, List<WebViewCookie>> groups, {
    required bool webVpn,
  }) async {
    if (groups.values.every((cookies) => cookies.isEmpty)) return;
    final encoded = <String, Object>{};
    for (final entry in groups.entries) {
      if (entry.value.isEmpty) continue;
      encoded[entry.key] = entry.value
          .map(
            (cookie) => {
              'name': cookie.name,
              'value': cookie.value,
              'domain': cookie.domain,
              'path': cookie.path,
            },
          )
          .toList();
    }
    final prefs = await _preferencesLoader();
    await prefs.setString(_cacheKey(webVpn), jsonEncode(encoded));
  }

  Future<void> _restoreCookies(
    Map<String, List<WebViewCookie>> groups,
  ) async {
    for (final cookies in groups.values) {
      for (final cookie in cookies) {
        try {
          await _cookieSetter(cookie);
        } on Object {
          // HTTP 请求仍可使用缓存，WebView 恢复失败不应清除登录态。
        }
      }
    }
  }

  String _cacheKey(bool webVpn) =>
      webVpn ? _cachedWebVpnCookiesKey : _cachedDirectCookiesKey;
}
