import 'dart:io';

import 'certificate_policy.dart';

class LehuHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (certificate, host, port) {
      return CertificatePolicy.allowsHost(host);
    };
    return client;
  }
}
