import 'package:webview_flutter/webview_flutter.dart';

import '../../core/academic_constants.dart';

class AcademicAuthService {
  AcademicAuthService({WebViewCookieManager? cookieManager})
      : _cookieManager = cookieManager ?? WebViewCookieManager();

  final WebViewCookieManager _cookieManager;

  Future<String?> cookieHeader() async {
    final cookies = [
      ...await _cookieManager.getCookies(
        domain: Uri.parse(
          '${AcademicConstants.baseUrl}${AcademicConstants.scheduleIndexPath}',
        ),
      ),
      ...await _cookieManager.getCookies(
        domain: Uri.parse(AcademicConstants.baseUrl),
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
