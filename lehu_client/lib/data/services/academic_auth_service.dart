import 'package:webview_flutter/webview_flutter.dart';

import '../../core/academic_constants.dart';
import '../../core/academic_url_resolver.dart';
import '../../core/forum_url_resolver.dart';

class AcademicAuthService {
  AcademicAuthService({WebViewCookieManager? cookieManager})
      : _cookieManager = cookieManager ?? WebViewCookieManager();

  final WebViewCookieManager _cookieManager;

  Future<String?> cookieHeader() async {
    final cookies = [
      if (AcademicUrlResolver.usesWebVpn)
        ...await _cookieManager.getCookies(
          domain: Uri.parse(ForumUrlResolver.webVpnPortalUrl),
        ),
      ...await _cookieManager.getCookies(
        domain: Uri.parse(
          '${AcademicUrlResolver.baseUrl}${AcademicConstants.scheduleIndexPath}',
        ),
      ),
      ...await _cookieManager.getCookies(
        domain: AcademicUrlResolver.baseUri,
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
