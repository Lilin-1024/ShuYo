import 'package:flutter/foundation.dart';

class ClientUserAgent {
  const ClientUserAgent._();

  static const android =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  static const ios = 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 '
      'Mobile/15E148 Safari/604.1';

  static String get mobileBrowser => forPlatform(defaultTargetPlatform);

  @visibleForTesting
  static String forPlatform(TargetPlatform platform) {
    return platform == TargetPlatform.iOS ? ios : android;
  }
}
