import 'forum_constants.dart';

class CertificatePolicy {
  const CertificatePolicy._();

  // Temporary workaround for the forum's expired certificate during MVP tests.
  // Do not broaden this to OAuth or arbitrary hosts.
  static const allowInvalidForumCertificate =
      bool.fromEnvironment('LEHU_ALLOW_INVALID_FORUM_CERT', defaultValue: true);

  static bool allowsHost(String host) {
    return allowInvalidForumCertificate && host == ForumConstants.host;
  }

  static bool allowsUri(Uri? uri) {
    return uri != null && allowsHost(uri.host);
  }
}
