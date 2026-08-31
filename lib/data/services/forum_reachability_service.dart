import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/forum_constants.dart';

enum ForumReachabilityStatus {
  reachable,
  unreachable,
  unknown,
}

class ForumReachabilityResult {
  const ForumReachabilityResult({
    required this.status,
    this.error,
  });

  final ForumReachabilityStatus status;
  final Object? error;

  bool get isUnavailable => status == ForumReachabilityStatus.unreachable;
}

class ForumReachabilityService {
  const ForumReachabilityService({
    this.timeout = const Duration(seconds: 3),
  });

  final Duration timeout;

  Future<ForumReachabilityResult> checkDirectBbsReachability() async {
    final client = HttpClient()..connectionTimeout = timeout;
    if (defaultTargetPlatform == TargetPlatform.android) {
      client.badCertificateCallback = (certificate, host, port) {
        return host == ForumConstants.host;
      };
    }
    try {
      final request = await client
          .getUrl(Uri.parse(ForumConstants.baseUrl))
          .timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      return const ForumReachabilityResult(
        status: ForumReachabilityStatus.reachable,
      );
    } on TimeoutException catch (error) {
      return ForumReachabilityResult(
        status: ForumReachabilityStatus.unreachable,
        error: error,
      );
    } on SocketException catch (error) {
      return ForumReachabilityResult(
        status: ForumReachabilityStatus.unreachable,
        error: error,
      );
    } on HandshakeException catch (error) {
      return ForumReachabilityResult(
        status: ForumReachabilityStatus.reachable,
        error: error,
      );
    } on Object catch (error) {
      return ForumReachabilityResult(
        status: ForumReachabilityStatus.unknown,
        error: error,
      );
    } finally {
      client.close(force: true);
    }
  }
}
