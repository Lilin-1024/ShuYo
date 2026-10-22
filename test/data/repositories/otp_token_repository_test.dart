import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/otp_token.dart';
import 'package:shuyo/data/repositories/otp_token_repository.dart';
import 'package:shuyo/data/services/otp_token_api_client.dart';

class _FakeClient extends OtpTokenApiClient {
  _FakeClient(this.response);

  final Future<OtpToken> response;
  bool wasDisposed = false;

  @override
  Future<OtpToken> fetchToken() => response;

  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}

OtpToken _token(String code) => OtpToken(
      code: code,
      account: '25120000',
      remaining: 30,
      period: 30,
    );

void main() {
  test('session reset rebuilds the client for the next account', () async {
    final clients = <_FakeClient>[];
    final repository = OtpTokenRepository(clientFactory: () {
      final client = _FakeClient(Future.value(_token(
        clients.isEmpty ? '111111' : '222222',
      )));
      clients.add(client);
      return client;
    });
    addTearDown(repository.dispose);

    expect((await repository.fetchToken()).code, '111111');
    repository.resetSession();
    expect(clients.single.wasDisposed, isTrue);
    expect((await repository.fetchToken()).code, '222222');
    expect(clients.length, 2);
  });

  test('session reset rejects an in-flight result from the old account',
      () async {
    final pending = Completer<OtpToken>();
    final oldClient = _FakeClient(pending.future);
    final repository = OtpTokenRepository(
      clientFactory: () => oldClient,
    );
    addTearDown(repository.dispose);

    final oldRead = repository.fetchToken();
    final rejection = expectLater(
      oldRead,
      throwsA(isA<OtpTokenException>().having(
        (error) => error.code,
        'code',
        OtpTokenException.sessionNotReused,
      )),
    );
    repository.resetSession();
    pending.complete(_token('111111'));
    await rejection;
  });

  test('signed-out session cannot start another token request', () async {
    var created = 0;
    final repository = OtpTokenRepository(clientFactory: () {
      created++;
      return _FakeClient(Future.value(_token('111111')));
    });
    addTearDown(repository.dispose);

    repository.resetSession(sessionActive: false);
    await expectLater(
        repository.fetchToken(), throwsA(isA<OtpTokenException>()));
    expect(created, 0);

    repository.resetSession();
    expect((await repository.fetchToken()).code, '111111');
    expect(created, 1);
  });
}
