import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/services/http_timeout.dart';

void main() {
  test('network timeout policy uses the expected duration tiers', () {
    expect(HttpTimeout.probe, const Duration(seconds: 3));
    expect(HttpTimeout.connect, const Duration(seconds: 5));
    expect(HttpTimeout.normal, const Duration(seconds: 10));
    expect(HttpTimeout.longPoll, const Duration(seconds: 45));
    expect(HttpTimeout.composed, const Duration(seconds: 20));
    expect(HttpTimeout.authentication, const Duration(seconds: 30));
    expect(HttpTimeout.oauthCompletion, const Duration(seconds: 45));
    expect(HttpTimeout.transfer, const Duration(seconds: 30));
    expect(HttpTimeout.streamIdle, const Duration(seconds: 10));
  });

  test('request reports the configured timeout and message', () async {
    const duration = Duration(milliseconds: 1);
    final future = Completer<void>().future;

    await expectLater(
      HttpTimeout.request(
        future,
        timeout: duration,
        message: 'custom timeout',
      ),
      throwsA(
        isA<TimeoutException>()
            .having((error) => error.message, 'message', 'custom timeout')
            .having((error) => error.duration, 'duration', duration),
      ),
    );
  });
}
