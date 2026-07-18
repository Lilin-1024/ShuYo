import 'forum_url_resolver.dart';

class ClassroomUrlResolver {
  const ClassroomUrlResolver._();

  static const directHost = 'classroom.cc.shu.edu.cn';
  static const directBaseUrl = 'https://$directHost';
  static const webVpnHost =
      'https-classroom-cc-shu-edu-cn-443.webvpn.shu.edu.cn';
  static const webVpnBaseUrl = 'https://$webVpnHost';

  static bool get usesWebVpn => ForumUrlResolver.usesWebVpn;

  static String get baseUrl => usesWebVpn ? webVpnBaseUrl : directBaseUrl;

  static Uri get baseUri => Uri.parse(baseUrl);

  static Uri uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized');
  }
}
