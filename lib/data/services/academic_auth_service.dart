import 'package:webview_flutter/webview_flutter.dart';

import '../../core/academic_constants.dart';
import '../../core/academic_url_resolver.dart';
import '../../core/forum_url_resolver.dart';

class AcademicAuthService {
  AcademicAuthService({WebViewCookieManager? cookieManager})
      : _cookieManager = cookieManager ?? WebViewCookieManager();

  final WebViewCookieManager _cookieManager;

  Future<Set<String>> clearCookies() async {
    final clearedSharedNames = <String>{};
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
        cookies = await _cookieManager.getCookies(domain: domain);
      } on Object {
        continue;
      }
      for (final cookie in cookies) {
        if (sharedWithForum) clearedSharedNames.add(cookie.name);
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
    return clearedSharedNames;
  }

  Future<bool> hasWebVpnSession() async {
    try {
      final cookies = await _cookieManager.getCookies(
        domain: Uri.parse(ForumUrlResolver.webVpnPortalUrl),
      );
      return cookies.any(
        (cookie) => cookie.name == 'webvpn-token' && cookie.value.isNotEmpty,
      );
    } on Object {
      return false;
    }
  }

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
