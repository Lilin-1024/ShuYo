import 'academic_constants.dart';
import 'forum_url_resolver.dart';

class AcademicUrlResolver {
  const AcademicUrlResolver._();

  static const webVpnHost = 'https-jwxt-shu-edu-cn-443.webvpn.shu.edu.cn';
  static const webVpnBaseUrl = 'https://$webVpnHost';
  static const homePath = '/jwglxt/xtgl/index_initMenu.html';

  static bool get usesWebVpn => ForumUrlResolver.usesWebVpn;

  static String get baseUrl =>
      usesWebVpn ? webVpnBaseUrl : AcademicConstants.baseUrl;

  static Uri get baseUri => Uri.parse(baseUrl);

  static Uri get entryUri => Uri.parse('$baseUrl/');

  static Uri get homeUri {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return Uri.parse(
      '$baseUrl$homePath?jsdm=xs&_t=$timestamp&echarts=1',
    );
  }

  static Uri get scheduleIndexUri => uri(AcademicConstants.scheduleIndexPath);

  static bool isTicketLoginUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.host == webVpnHost &&
        uri.path.endsWith('/jwglxt/ticketlogin');
  }

  static bool isPreparedWebVpnAcademicUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host != webVpnHost) {
      return false;
    }
    final path = uri.path;
    return path.startsWith('/jwglxt/') &&
        !path.endsWith('/jwglxt/xtgl/login_slogin.html');
  }

  static Uri uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized');
  }
}
