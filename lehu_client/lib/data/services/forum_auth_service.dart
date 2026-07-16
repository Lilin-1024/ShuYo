import 'package:webview_flutter/webview_flutter.dart';

import '../../core/forum_url_resolver.dart';

class ForumAuthService {
  ForumAuthService({WebViewCookieManager? cookieManager})
      : _cookieManager = cookieManager ?? WebViewCookieManager();

  final WebViewCookieManager _cookieManager;

  Future<String?> cookieHeader() async {
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

  Future<bool> hasForumCookies() async {
    final header = await cookieHeader();
    return header != null && header.isNotEmpty;
  }

  Future<void> clearCookies() async {
    await _cookieManager.clearCookies();
  }
}
