import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/services/recovery_auth_service.dart';

void main() {
  late HttpServer server;
  late RecoveryAuthService service;
  late List<({String method, String path, String cookie, String body})>
      requests;
  late int status;
  late String payload;

  setUp(() async {
    requests = [];
    status = 200;
    payload = jsonEncode({
      'message': 'success',
      'methods': {'sms': '短信提示', 'wecom': '企业微信提示'},
      'csrfToken': 'test-csrf',
    });
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      requests.add((
        method: request.method,
        path: request.uri.path,
        cookie: request.headers.value(HttpHeaders.cookieHeader) ?? '',
        body: body,
      ));
      if (request.method == 'GET') {
        request.response.cookies
            .add(Cookie('recovery', 'test-session')..path = '/');
        request.response.write('page');
      } else {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/verifyCode') ||
            request.uri.path.endsWith('/verifyOldCode')) {
          request.response.cookies
              .add(Cookie('verified', 'test-verified')..path = '/');
        }
        request.response.write(payload);
      }
      await request.response.close();
    });
    service = RecoveryAuthService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    );
  });

  tearDown(() async {
    service.dispose();
    await server.close(force: true);
  });

  test('reset verifies the exact fields and retains the recovery session',
      () async {
    final challenge = await service.verifyResetInfo(
      username: 'test-user',
      realName: 'test-name',
      identityID: 'test-identity',
      cardID: 'test-card',
    );
    expect(requests.map((request) => request.path), [
      '/oauth2/resetPassword',
      '/oauth/resetPassword/verifyInfo',
    ]);
    expect(requests.last.cookie, contains('recovery=test-session'));
    expect(jsonDecode(requests.last.body), {
      'username': 'test-user',
      'realName': 'test-name',
      'identityID': 'test-identity',
      'cardID': 'test-card',
    });
    expect(challenge.methods, {'sms': '短信提示', 'wecom': '企业微信提示'});
    expect(service.hasVerifiedSession, isTrue);
  });

  test('change phone encrypts the password and accepts empty methods',
      () async {
    payload = jsonEncode(
        {'message': 'success', 'methods': {}, 'csrfToken': 'test-csrf'});
    final challenge = await service.verifyChangePhoneUser(
      username: 'test-user',
      password: 'test-password',
    );
    expect(requests.last.path, '/oauth/changePhone/verifyUser');
    expect(requests.last.cookie, contains('recovery=test-session'));
    final submitted = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(submitted['username'], 'test-user');
    expect(submitted['password'], isNot('test-password'));
    expect(base64Decode(submitted['password'] as String), hasLength(128));
    expect(challenge.methods, isEmpty);
    expect(service.hasVerifiedSession, isTrue);
  });

  test('maps a server rejection and does not establish a session', () async {
    status = 400;
    payload = jsonEncode({'message': 'userNotFound'});
    await expectLater(
      service.verifyResetInfo(
        username: 'test-user',
        realName: 'test-name',
        identityID: 'test-identity',
        cardID: 'test-card',
      ),
      throwsA(isA<RecoveryAuthException>()
          .having((e) => e.code, 'code', 'userNotFound')
          .having((e) => e.message, 'message', '用户不存在')),
    );
    expect(service.hasVerifiedSession, isFalse);
  });

  test('rejects HTTP 200 with an explicit failure or missing token', () async {
    payload = jsonEncode({'success': false, 'message': 'invalidPassword'});
    await expectLater(
      service.verifyChangePhoneUser(
          username: 'test-user', password: 'test-password'),
      throwsA(isA<RecoveryAuthException>()
          .having((e) => e.message, 'message', '学工号或密码不正确')),
    );
    payload = jsonEncode({'message': 'success'});
    await expectLater(
      service.verifyChangePhoneUser(
          username: 'test-user', password: 'test-password'),
      throwsA(isA<RecoveryAuthException>()
          .having((e) => e.code, 'code', 'invalidResponse')),
    );
    expect(service.hasVerifiedSession, isFalse);
  });

  test('reset sends and verifies a code and submits two encrypted passwords',
      () async {
    await service.verifyResetInfo(
      username: 'test-user',
      realName: 'test-name',
      identityID: 'test-identity',
      cardID: 'test-card',
    );
    payload = jsonEncode({'message': 'success'});
    await service.sendVerificationCode(method: 'wecom');
    expect(requests.last.path, '/oauth/resetPassword/sendCode');
    expect(jsonDecode(requests.last.body),
        {'method': 'wecom', 'csrfToken': 'test-csrf'});
    await service.verifyVerificationCode(method: 'wecom', code: '123456');
    expect(requests.last.path, '/oauth/resetPassword/verifyCode');
    expect(jsonDecode(requests.last.body),
        {'method': 'wecom', 'code': '123456', 'csrfToken': 'test-csrf'});
    await service.resetPassword(
        password: 'test-password', confirmPassword: 'test-password');
    expect(requests.last.path, '/oauth/resetPassword/submit');
    expect(requests.last.cookie, contains('recovery=test-session'));
    expect(requests.last.cookie, contains('verified=test-verified'));
    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(body['csrfToken'], 'test-csrf');
    expect(base64Decode(body['password'] as String), hasLength(128));
    expect(base64Decode(body['confirmPassword'] as String), hasLength(128));
    expect(body['password'], isNot(body['confirmPassword']));
  });

  test('phone change carries the same session through all later requests',
      () async {
    await service.verifyChangePhoneUser(
        username: 'test-user', password: 'test-password');
    payload = jsonEncode({'message': 'success'});
    await service.sendVerificationCode(method: 'sms');
    expect(requests.last.path, '/oauth/changePhone/sendOldCode');
    expect(jsonDecode(requests.last.body),
        {'method': 'sms', 'csrfToken': 'test-csrf'});
    await service.verifyVerificationCode(method: 'sms', code: '123456');
    expect(requests.last.path, '/oauth/changePhone/verifyOldCode');
    expect(jsonDecode(requests.last.body),
        {'method': 'sms', 'code': '123456', 'csrfToken': 'test-csrf'});
    await service.sendNewPhoneCode(phone: '13800000000');
    expect(requests.last.path, '/oauth/changePhone/sendNewCode');
    expect(requests.last.cookie, contains('verified=test-verified'));
    expect(jsonDecode(requests.last.body),
        {'phone': '13800000000', 'csrfToken': 'test-csrf'});
    await service.submitNewPhone(phone: '13800000000', code: '654321');
    expect(requests.last.path, '/oauth/changePhone/submit');
    expect(requests.last.cookie, contains('recovery=test-session'));
    expect(requests.last.cookie, contains('verified=test-verified'));
    expect(jsonDecode(requests.last.body), {
      'phone': '13800000000',
      'code': '654321',
      'csrfToken': 'test-csrf',
    });
  });

  test('later requests map errors and reject ambiguous reset results',
      () async {
    await service.verifyResetInfo(
      username: 'test-user',
      realName: 'test-name',
      identityID: 'test-identity',
      cardID: 'test-card',
    );
    status = 400;
    payload = jsonEncode({'message': 'invalidCode'});
    await expectLater(
      service.verifyVerificationCode(method: 'sms', code: '123456'),
      throwsA(isA<RecoveryAuthException>()
          .having((e) => e.message, 'message', '验证码不正确或已过期')),
    );
    status = 200;
    payload = '{}';
    await expectLater(
      service.resetPassword(password: 'test', confirmPassword: 'test'),
      throwsA(isA<RecoveryAuthException>()
          .having((e) => e.code, 'code', 'invalidResponse')
          .having((e) => e.message, 'message', contains('无法确认'))),
    );
    payload = jsonEncode({'success': true, 'message': 'completed'});
    await service.resetPassword(password: 'test', confirmPassword: 'test');
    payload = jsonEncode({'message': 'sendTooRecently'});
    await expectLater(
      service.sendVerificationCode(method: 'wecom'),
      throwsA(isA<RecoveryAuthException>()
          .having((e) => e.message, 'message', '验证码发送过于频繁，请稍后再试')),
    );
  });

  test('rejects the wrong flow and maps the same-phone response', () async {
    expect(() => service.sendNewPhoneCode(phone: '13800000000'),
        throwsA(isA<RecoveryAuthException>()));
    await service.verifyChangePhoneUser(
        username: 'test-user', password: 'test-password');
    status = 400;
    payload = jsonEncode({'message': 'samePhoneNumber'});
    await expectLater(
      service.sendNewPhoneCode(phone: '13800000000'),
      throwsA(isA<RecoveryAuthException>()
          .having((e) => e.message, 'message', '新手机号不能与旧手机号相同')),
    );
    expect(
      () => service.resetPassword(password: 'test', confirmPassword: 'test'),
      throwsA(isA<RecoveryAuthException>()),
    );
  });
}
