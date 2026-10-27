import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/services/recovery_auth_service.dart';

void main() {
  test('an old response cannot add cookies to a later recovery session',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final oldSendStarted = Completer<void>();
    final releaseOldSend = Completer<void>();
    var session = 0;
    String? verificationCookie;
    String? verificationToken;
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      final path = request.uri.path;
      if (request.method == 'GET') {
        session++;
        request.response.cookies
            .add(Cookie('recovery', 'session$session')..path = '/');
        request.response.write('page');
      } else if (path.endsWith('/verifyInfo')) {
        request.response.write(jsonEncode({
          'message': 'success',
          'methods': {'sms': 'masked'},
          'csrfToken': 'token$session',
        }));
      } else if (path.endsWith('/sendCode')) {
        oldSendStarted.complete();
        await releaseOldSend.future;
        request.response.cookies.add(Cookie('recovery', 'stale')..path = '/');
        request.response.write('{"message":"success"}');
      } else if (path.endsWith('/verifyCode')) {
        verificationCookie = request.headers.value(HttpHeaders.cookieHeader);
        verificationToken = (jsonDecode(body) as Map)['csrfToken'] as String?;
        request.response.write('{"message":"success"}');
      }
      await request.response.close();
    });
    final service = RecoveryAuthService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    addTearDown(() async {
      service.dispose();
      await server.close(force: true);
    });

    Future<void> verifyInfo() async {
      await service.verifyResetInfo(
        username: 'test',
        realName: 'test',
        identityID: 'test',
        cardID: 'test',
      );
    }

    await verifyInfo();
    final oldSend = service.sendVerificationCode(method: 'sms');
    await oldSendStarted.future;
    await verifyInfo();
    releaseOldSend.complete();
    await oldSend;
    await service.verifyVerificationCode(method: 'sms', code: '123456');

    expect(verificationCookie, contains('recovery=session2'));
    expect(verificationCookie, isNot(contains('stale')));
    expect(verificationToken, 'token2');
  });

  test('send failures use operation-specific fallback and retain known errors',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var responseCode = 'unexpectedServerValue';
    server.listen((request) async {
      await request.drain<void>();
      if (request.method == 'GET') {
        request.response.write('page');
      } else if (request.uri.path.endsWith('/verifyInfo') ||
          request.uri.path.endsWith('/verifyUser')) {
        request.response.write(jsonEncode({
          'message': 'success',
          'methods': {'sms': 'masked'},
          'csrfToken': 'test-token',
        }));
      } else {
        request.response.statusCode = 400;
        request.response.write(jsonEncode({'message': responseCode}));
      }
      await request.response.close();
    });
    final service = RecoveryAuthService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
    addTearDown(() async {
      service.dispose();
      await server.close(force: true);
    });

    await service.verifyResetInfo(
        username: 'test', realName: 'test', identityID: 'test', cardID: 'test');
    await expectLater(
      service.sendVerificationCode(method: 'sms'),
      throwsA(isA<RecoveryAuthException>()
          .having((error) => error.message, 'message', '验证码发送失败，请稍后重试')),
    );
    responseCode = 'sendTooRecently';
    await expectLater(
      service.sendVerificationCode(method: 'sms'),
      throwsA(isA<RecoveryAuthException>()
          .having((error) => error.message, 'message', '验证码发送过于频繁，请稍后再试')),
    );
    responseCode = 'unexpectedServerValue';
    await service.verifyChangePhoneUser(username: 'test', password: 'test');
    for (final send in [
      () => service.sendVerificationCode(method: 'sms'),
      () => service.sendNewPhoneCode(phone: '13800000000'),
    ]) {
      await expectLater(
        send(),
        throwsA(isA<RecoveryAuthException>()
            .having((error) => error.message, 'message', '验证码发送失败，请稍后重试')),
      );
    }
  });
}
