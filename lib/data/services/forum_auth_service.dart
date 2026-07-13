import 'package:webview_flutter/webview_flutter.dart';

import '../../core/forum_constants.dart';

class ForumAuthService {
  ForumAuthService({WebViewCookieManager? cookieManager})
      : _cookieManager = cookieManager ?? WebViewCookieManager();

  final WebViewCookieManager _cookieManager;

  Future<String?> cookieHeader() async {
    final cookies = await _cookieManager.getCookies(
      domain: Uri.parse(ForumConstants.baseUrl),
    );
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
