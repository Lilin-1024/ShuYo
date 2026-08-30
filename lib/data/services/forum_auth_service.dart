import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/forum_url_resolver.dart';

class ForumAuthService {
  ForumAuthService({
    WebViewCookieManager? cookieManager,
    Future<SharedPreferences> Function()? preferencesLoader,
    Future<List<WebViewCookie>> Function(Uri domain)? cookieLoader,
    Future<void> Function(WebViewCookie cookie)? cookieSetter,
  })  : _cookieManager = cookieManager ??
            (cookieLoader == null || cookieSetter == null
                ? WebViewCookieManager()
                : null),
        _preferencesLoader =
            preferencesLoader ?? SharedPreferences.getInstance {
    _cookieLoader =
        cookieLoader ?? (domain) => _cookieManager!.getCookies(domain: domain);
    _cookieSetter = cookieSetter ?? _cookieManager!.setCookie;
  }

  final WebViewCookieManager? _cookieManager;
  final Future<SharedPreferences> Function() _preferencesLoader;
  late final Future<List<WebViewCookie>> Function(Uri domain) _cookieLoader;
  late final Future<void> Function(WebViewCookie cookie) _cookieSetter;

  static const _cachedDirectCookieHeaderKey =
      'forum.auth.cached_cookie_header.direct';
  static const _cachedWebVpnCookieHeaderKey =
      'forum.auth.cached_cookie_header.webvpn';
  static const _storedDirectCookiesKey = 'forum.auth.cookies.v2.direct';
  static const _storedWebVpnCookiesKey = 'forum.auth.cookies.v2.webvpn';

  Future<String?> cookieHeader() async {
    final mode = ForumUrlResolver.mode;
    final cookies = await _loadAndMergeCookies(mode);
    await _persistCookies(cookies, mode);
    return _cookieHeaderFor(ForumUrlResolver.baseUri, cookies);
  }

  Future<void> persistLastCookieHeader() async {
    final mode = ForumUrlResolver.mode;
    final cookies = await _loadAndMergeCookies(mode);
    await _persistCookies(cookies, mode);
  }

  /// Imports cookies created by the OAuth completion WebView.
  ///
  /// This is called explicitly after a new login so a new browser session can
  /// replace an older persisted forum session. During normal API requests the
  /// structured native store remains authoritative.
  Future<void> refreshFromWebView() async {
    final mode = ForumUrlResolver.mode;
    final cached = await _loadStoredCookies(mode);
    final live = await _loadWebViewCookies(mode);
    final merged = <String, _StoredForumCookie>{
      for (final cookie in cached) cookie.key: cookie,
      for (final cookie in live) cookie.key: cookie,
    };
    await _persistCookies(merged.values.toList(), mode);
  }

  /// Applies cookies returned by a native forum API response.
  ///
  /// `package:http` does not maintain a browser cookie jar. Persisting each
  /// Set-Cookie response here keeps rotating Discourse sessions alive and
  /// makes the latest session available after an app restart.
  Future<void> updateFromSetCookieHeaders(
    Uri responseUri,
    Iterable<String> headerValues,
  ) async {
    final values = headerValues.where((value) => value.trim().isNotEmpty);
    if (values.isEmpty) return;

    final mode = ForumUrlResolver.mode;
    final now = DateTime.now().toUtc();
    final stored = <String, _StoredForumCookie>{
      for (final cookie in await _loadStoredCookies(mode)) cookie.key: cookie,
    };
    final changed = <_StoredForumCookie>[];
    final removedNames = <String>{};
    for (final value in values) {
      Cookie parsed;
      try {
        parsed = Cookie.fromSetCookieValue(value);
      } on Object {
        continue;
      }
      final cookie = _StoredForumCookie.fromSetCookie(
        parsed,
        responseUri: responseUri,
        now: now,
      );
      if (cookie.name.isEmpty) continue;
      if (cookie.value.isEmpty || cookie.isExpiredAt(now)) {
        stored.remove(cookie.key);
        removedNames.add(cookie.name);
      } else {
        stored[cookie.key] = cookie;
        changed.add(cookie);
      }
    }
    await _persistCookies(stored.values.toList(), mode);
    if (kDebugMode && (changed.isNotEmpty || removedNames.isNotEmpty)) {
      final updatedNames = changed.map((cookie) => cookie.name).toSet();
      debugPrint(
        '[LEHU_FORUM_COOKIE] mode=${mode.name} '
        'updated=$updatedNames removed=$removedNames',
      );
    }
    for (final cookie in changed) {
      if (cookie.httpOnly) continue;
      try {
        await _cookieSetter(cookie.toWebViewCookie());
      } on Object {
        // Native requests keep using the structured store if WebView syncing
        // is unavailable on the current platform.
      }
    }
  }

  Future<void> clearCachedCookies() async {
    final prefs = await _preferencesLoader();
    await Future.wait([
      prefs.remove(_cachedDirectCookieHeaderKey),
      prefs.remove(_cachedWebVpnCookieHeaderKey),
      prefs.remove(_storedDirectCookiesKey),
      prefs.remove(_storedWebVpnCookiesKey),
    ]);
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
        cookies = await _cookieLoader(domain);
      } on Object {
        continue;
      }
      for (final cookie in cookies) {
        await _cookieSetter(
          WebViewCookie(
            name: cookie.name,
            value: '',
            domain: _normalizeCookieDomain(cookie.domain, domain.host),
            path: cookie.path,
          ),
        );
      }
    }
    await clearCachedCookies();
  }

  Future<List<_StoredForumCookie>> _loadAndMergeCookies(
    ForumAccessMode mode,
  ) async {
    final cached = await _loadStoredCookies(mode);
    final live = await _loadWebViewCookies(mode);
    final now = DateTime.now().toUtc();
    final merged = <String, _StoredForumCookie>{};

    // Browser cookies fill gaps left by a partial restore. The native store is
    // authoritative for forum cookies because it also receives Set-Cookie
    // rotation from API responses.
    for (final cookie in live) {
      if (!cookie.isExpiredAt(now)) merged[cookie.key] = cookie;
    }
    for (final cookie in cached) {
      if (!cookie.isExpiredAt(now)) merged[cookie.key] = cookie;
    }

    // The WebVPN portal token is shared with campus login and may be replaced
    // outside the forum client, so prefer its current browser value.
    for (final cookie in live) {
      if (cookie.name == 'webvpn-token' && !cookie.isExpiredAt(now)) {
        merged[cookie.key] = cookie;
      }
    }
    return merged.values.toList();
  }

  Future<List<_StoredForumCookie>> _loadStoredCookies(
    ForumAccessMode mode,
  ) async {
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(_storedKey(mode));
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map(_StoredForumCookie.fromJson)
              .whereType<_StoredForumCookie>()
              .toList();
        }
      } on Object {
        // Fall through to the legacy header migration.
      }
    }

    final legacy = prefs.getString(_legacyKey(mode));
    final parsed = _parseCookieHeader(legacy);
    if (parsed.isEmpty) return const [];
    final now = DateTime.now().toUtc();
    final activeHost = switch (mode) {
      ForumAccessMode.direct => 'bbs.shu.edu.cn',
      ForumAccessMode.webVpn => ForumUrlResolver.webVpnHost,
    };
    final migrated = parsed.entries
        .map(
          (entry) => _StoredForumCookie(
            name: entry.key,
            value: entry.value,
            domain:
                entry.key == 'webvpn-token' ? 'webvpn.shu.edu.cn' : activeHost,
            path: '/',
            expiresAt: null,
            secure: true,
            httpOnly: false,
            updatedAt: now,
          ),
        )
        .toList();
    await _persistCookies(migrated, mode);
    return migrated;
  }

  Future<List<_StoredForumCookie>> _loadWebViewCookies(
    ForumAccessMode mode,
  ) async {
    final domains = <Uri>[
      if (mode == ForumAccessMode.webVpn)
        Uri.parse(ForumUrlResolver.webVpnPortalUrl),
      Uri.parse(
        mode == ForumAccessMode.webVpn
            ? ForumUrlResolver.webVpnBaseUrl
            : 'https://bbs.shu.edu.cn',
      ),
    ];
    final now = DateTime.now().toUtc();
    final values = <String, _StoredForumCookie>{};
    for (final domain in domains) {
      List<WebViewCookie> cookies;
      try {
        cookies = await _cookieLoader(domain);
      } on Object {
        continue;
      }
      if (kDebugMode) {
        debugPrint(
          '[LEHU_FORUM_COOKIE] webview-read mode=${mode.name} '
          'domain=${domain.host} '
          'cookies=${cookies.map((cookie) => '${cookie.name}@${cookie.domain}[${cookie.path}]#${cookie.value.length}').toList()}',
        );
      }
      for (final cookie in cookies) {
        if (cookie.name.isEmpty || cookie.value.isEmpty) continue;
        final stored = _StoredForumCookie(
          name: cookie.name,
          value: cookie.value,
          domain: _normalizeCookieDomain(cookie.domain, domain.host),
          path: cookie.path.isEmpty ? '/' : cookie.path,
          expiresAt: null,
          secure: true,
          httpOnly: false,
          updatedAt: now,
        );
        values[stored.key] = stored;
      }
    }
    return values.values.toList();
  }

  Future<void> _persistCookies(
    List<_StoredForumCookie> cookies,
    ForumAccessMode mode,
  ) async {
    final now = DateTime.now().toUtc();
    final active = cookies.where((cookie) => !cookie.isExpiredAt(now)).toList();
    final prefs = await _preferencesLoader();
    if (active.isEmpty) {
      await prefs.remove(_storedKey(mode));
      await prefs.remove(_legacyKey(mode));
      return;
    }
    await prefs.setString(
      _storedKey(mode),
      jsonEncode(active.map((cookie) => cookie.toJson()).toList()),
    );
    // Keep the old key during one compatibility cycle for installations that
    // downgrade, but always write the latest non-expired values.
    await prefs.setString(
      _legacyKey(mode),
      _encodeCookieHeader({
        for (final cookie in active) cookie.name: cookie.value,
      }),
    );
  }

  String? _cookieHeaderFor(Uri uri, List<_StoredForumCookie> cookies) {
    final now = DateTime.now().toUtc();
    final matching = cookies
        .where((cookie) => !cookie.isExpiredAt(now) && cookie.matches(uri))
        .toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    if (matching.isEmpty) return null;
    return matching
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  String _normalizeCookieDomain(String value, String fallbackHost) {
    if (value.isEmpty) return fallbackHost;
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.host.isNotEmpty) return parsed.host;
    final withoutScheme = value.replaceFirst(RegExp(r'^https?://'), '');
    final host = withoutScheme.split('/').first.split(':').first;
    return host.isEmpty ? fallbackHost : host;
  }

  String _storedKey(ForumAccessMode mode) => switch (mode) {
        ForumAccessMode.direct => _storedDirectCookiesKey,
        ForumAccessMode.webVpn => _storedWebVpnCookiesKey,
      };

  String _legacyKey(ForumAccessMode mode) => switch (mode) {
        ForumAccessMode.direct => _cachedDirectCookieHeaderKey,
        ForumAccessMode.webVpn => _cachedWebVpnCookieHeaderKey,
      };

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
      final filtered = (await _loadStoredCookies(mode))
          .where((cookie) => !names.contains(cookie.name))
          .toList();
      await _persistCookies(filtered, mode);
      final legacy = ForumAuthService._parseCookieHeader(
        prefs.getString(_legacyKey(mode)),
      )..removeWhere((name, _) => names.contains(name));
      if (legacy.isEmpty) {
        await prefs.remove(_legacyKey(mode));
      } else {
        await prefs.setString(
          _legacyKey(mode),
          ForumAuthService._encodeCookieHeader(legacy),
        );
      }
    }
  }
}

class _StoredForumCookie {
  const _StoredForumCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.expiresAt,
    required this.secure,
    required this.httpOnly,
    required this.updatedAt,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expiresAt;
  final bool secure;
  final bool httpOnly;
  final DateTime updatedAt;

  String get key => '$name\u0000${_normalizedDomain(domain)}\u0000$path';

  factory _StoredForumCookie.fromSetCookie(
    Cookie cookie, {
    required Uri responseUri,
    required DateTime now,
  }) {
    final maxAge = cookie.maxAge;
    final expiresAt = maxAge == null
        ? cookie.expires?.toUtc()
        : now.add(Duration(seconds: maxAge));
    return _StoredForumCookie(
      name: cookie.name,
      value: cookie.value,
      domain:
          cookie.domain?.isNotEmpty == true ? cookie.domain! : responseUri.host,
      path: cookie.path?.isNotEmpty == true ? cookie.path! : '/',
      expiresAt: expiresAt,
      secure: cookie.secure || responseUri.scheme == 'https',
      httpOnly: cookie.httpOnly,
      updatedAt: now,
    );
  }

  static _StoredForumCookie? fromJson(Map<dynamic, dynamic> json) {
    final name = json['name']?.toString() ?? '';
    final value = json['value']?.toString() ?? '';
    final domain = json['domain']?.toString() ?? '';
    if (name.isEmpty || value.isEmpty || domain.isEmpty) return null;
    return _StoredForumCookie(
      name: name,
      value: value,
      domain: domain,
      path: json['path']?.toString().isNotEmpty == true
          ? json['path'].toString()
          : '/',
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '')?.toUtc(),
      secure: json['secure'] != false,
      httpOnly: json['httpOnly'] == true,
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'expiresAt': expiresAt?.toIso8601String(),
        'secure': secure,
        'httpOnly': httpOnly,
        'updatedAt': updatedAt.toIso8601String(),
      };

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  bool matches(Uri uri) {
    if (secure && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    final cookieDomain = _normalizedDomain(domain);
    if (host != cookieDomain && !host.endsWith('.$cookieDomain')) return false;
    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    return requestPath == path ||
        requestPath.startsWith(path.endsWith('/') ? path : '$path/');
  }

  WebViewCookie toWebViewCookie() => WebViewCookie(
        name: name,
        value: value,
        domain: domain,
        path: path,
      );

  static String _normalizedDomain(String value) =>
      value.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
}
