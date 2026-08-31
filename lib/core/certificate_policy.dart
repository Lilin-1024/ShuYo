import 'package:flutter/foundation.dart';

import 'forum_constants.dart';

class CertificatePolicy {
  const CertificatePolicy._();

  // Temporary workaround for the forum's expired certificate during MVP tests.
  // Do not broaden this to OAuth or arbitrary hosts.
  static const allowInvalidForumCertificate =
      bool.fromEnvironment('LEHU_ALLOW_INVALID_FORUM_CERT', defaultValue: true);

  static bool allowsHost(String host) {
    // iOS/WebKit performs certificate validation in the system security
    // stack. Keep the temporary invalid-certificate exception Android-only.
    return defaultTargetPlatform == TargetPlatform.android &&
        allowInvalidForumCertificate &&
        host.toLowerCase() == ForumConstants.host;
  }

  static bool allowsUri(Uri? uri) {
    return uri != null && allowsHost(uri.host);
  }
}
