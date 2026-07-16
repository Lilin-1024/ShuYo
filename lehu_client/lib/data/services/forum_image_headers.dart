import 'dart:io';

import '../../core/forum_url_resolver.dart';
import 'forum_auth_service.dart';

class ForumImageHeaders {
  ForumImageHeaders._();

  static final ForumAuthService _authService = ForumAuthService();
  static DateTime? _cachedAt;
  static Map<String, String>? _cachedHeaders;

  static Future<Map<String, String>?> forUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !ForumUrlResolver.isKnownForumHost(uri.host)) {
      return null;
    }
    final cachedAt = _cachedAt;
    final cached = _cachedHeaders;
    if (cachedAt != null &&
        cached != null &&
        DateTime.now().difference(cachedAt) < const Duration(seconds: 30)) {
      return cached.isEmpty ? null : cached;
    }
    final cookie = await _authService.cookieHeader();
    final headers = <String, String>{
      HttpHeaders.refererHeader: ForumUrlResolver.baseUrl,
      HttpHeaders.userAgentHeader:
          'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      if (cookie != null && cookie.isNotEmpty) HttpHeaders.cookieHeader: cookie,
    };
    _cachedAt = DateTime.now();
    _cachedHeaders = headers;
    return headers;
  }

  static void clearCache() {
    _cachedAt = null;
    _cachedHeaders = null;
  }
}
