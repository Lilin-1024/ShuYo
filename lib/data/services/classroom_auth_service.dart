import 'package:webview_flutter/webview_flutter.dart';

import '../../core/classroom_url_resolver.dart';
import '../../core/forum_url_resolver.dart';

class ClassroomAuthService {
  ClassroomAuthService({WebViewCookieManager? cookieManager})
      : _cookieManager = cookieManager ?? WebViewCookieManager();

  final WebViewCookieManager _cookieManager;

  Future<String?> cookieHeader() async {
    if (!ClassroomUrlResolver.usesWebVpn) {
      return null;
    }
    final cookies = [
      ...await _cookieManager.getCookies(
        domain: Uri.parse(ForumUrlResolver.webVpnPortalUrl),
      ),
      ...await _cookieManager.getCookies(
        domain: ClassroomUrlResolver.baseUri,
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
}
