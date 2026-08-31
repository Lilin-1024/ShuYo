import 'dart:io';

import 'package:flutter/foundation.dart';

import 'certificate_policy.dart';

class LehuHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (defaultTargetPlatform == TargetPlatform.android) {
      client.badCertificateCallback = (certificate, host, port) {
        return CertificatePolicy.allowsHost(host);
      };
    }
    return client;
  }
}
