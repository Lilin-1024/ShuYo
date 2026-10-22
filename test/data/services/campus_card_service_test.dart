import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/academic_account_store.dart';
import 'package:shuyo/data/services/campus_card_service.dart';
import 'package:shuyo/data/services/secure_app_store.dart';
import 'package:shuyo/data/services/unified_account_service.dart';

const _profilePath = '/api/Identity/User/GetUserInfo';
const _cardPath = '/api/Identity/SchoolCard/GetCardPersonInfo';
const _billsPath = '/api/Identity/SchoolCard/GetCardBillInfo';
const _loginPath = '/api/Identity/User/Login';
const _studentId = 'STUDENT_1';
const _oldToken = 'expired-token';
const _newToken = 'renewed-token';
const _expired = (
  status: 200,
  body: <String, dynamic>{
    'type': 3,
    'errorcode': 500,
    'message': '登录失效',
  },
);

typedef _Reply = ({int status, Map<String, dynamic> body});

_Reply _ok(Map<String, dynamic> data) => (
      status: 200,
      body: {'type': 1, 'errorcode': 0, 'data': data},
    );

void main() {
  late CampusCardService service;
  late _HttpClient http;
  late _AccountService account;
  FutureOr<_Reply?> Function(String, Uri)? intercept;
  final start = DateTime(2026, 10, 1);
  final end = DateTime(2026, 10, 7);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      AcademicAccountStore.studentIdKey: _studentId,
      SecureAppStore.campusCardSessionKey: jsonEncode({
        'access_token': _oldToken,
        'studentId': _studentId,
      }),
    });
    intercept = null;
    account = _AccountService();
    http = _HttpClient((method, uri) async {
      final reply = await intercept?.call(method, uri);
      if (reply != null) return reply;
      switch (uri.path) {
        case _profilePath:
          return _ok({'userid': _studentId});
        case _loginPath:
          expect(method, 'POST');
          expect(uri.queryParameters['code'], 'replacement-code');
          return _ok({'access_token': _newToken, 'userid': _studentId});
        case _cardPath:
          return _ok({
            'schoolCard': {
              'PersonNumber': _studentId,
              'PersonName': '测试用户',
              'CardStatus': '正常',
              'ZhangHYE': '12.50',
              'YouXQ': '2030-01-01',
            },
          });
        case _billsPath:
          expect(uri.queryParameters['StartDate'], '2026-10-01');
          expect(uri.queryParameters['EndDate'], '2026-10-07');
          return _ok({
            'bills': [
              {'billname': '食堂', 'paytime': '2026-10-01', 'amount': '-5.00'},
            ],
          });
        default:
          throw StateError('Unexpected request: $method $uri');
      }
    });
    service = CampusCardService(httpClient: http, accountService: account);
  });

  tearDown(() => service.dispose());

  Future<void> fetch(String path) async {
    if (path == _billsPath) {
      final bills = await service.fetchBills(startDate: start, endDate: end);
      expect(bills.single.amount, -5);
    } else {
      expect((await service.fetchCardInfo()).balance, 12.5);
    }
  }

  test('a valid token does not need SSO authorization', () async {
    await fetch(_cardPath);
    expect(account.authorizations, 0);
  });

  test('a missing token still authorizes through SSO', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SecureAppStore.campusCardSessionKey);

    await fetch(_cardPath);

    expect(account.authorizations, 1);
    expect(http.seen.where((uri) => uri.path == _profilePath), isEmpty);
  });

  test('a rejected first authorization is not automatically repeated',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(SecureAppStore.campusCardSessionKey);
    intercept = (_, uri) => uri.path == _cardPath ? _expired : null;

    await expectLater(
      service.fetchCardInfo(),
      throwsA(isA<CampusCardAuthRequiredException>()),
    );

    expect(account.authorizations, 1);
    expect(http.seen.where((uri) => uri.path == _loginPath), hasLength(1));
  });

  for (final path in [_profilePath, _cardPath, _billsPath]) {
    for (final status in [200, 401, 403]) {
      test('$path expiry ($status) silently reauthorizes and retries',
          () async {
        intercept = (_, uri) {
          if (uri.path == path &&
              uri.queryParameters['access_token'] == _oldToken) {
            return (status: status, body: _expired.body);
          }
          return null;
        };

        await fetch(path);

        expect(account.authorizations, 1);
        expect(http.seen.where((uri) => uri.path == _loginPath), hasLength(1));
        final prefs = await SharedPreferences.getInstance();
        final saved = jsonDecode(
          prefs.getString(SecureAppStore.campusCardSessionKey)!,
        );
        expect(saved['access_token'], _newToken);
      });
    }
  }

  test('concurrent balance and bills share the replacement authorization',
      () async {
    final bothRejected = Completer<void>();
    var rejected = 0;
    intercept = (_, uri) async {
      if ({_cardPath, _billsPath}.contains(uri.path) &&
          uri.queryParameters['access_token'] == _oldToken) {
        if (++rejected == 2) bothRejected.complete();
        await bothRejected.future;
        return _expired;
      }
      return null;
    };

    await Future.wait([fetch(_cardPath), fetch(_billsPath)]);

    expect(account.authorizations, 1);
    expect(http.seen.where((uri) => uri.path == _loginPath), hasLength(1));
  });

  test('concurrent queries share recovery after cached-token validation fails',
      () async {
    intercept = (_, uri) => uri.path == _profilePath &&
            uri.queryParameters['access_token'] == _oldToken
        ? _expired
        : null;

    await Future.wait([fetch(_cardPath), fetch(_billsPath)]);

    expect(account.authorizations, 1);
    expect(http.seen.where((uri) => uri.path == _loginPath), hasLength(1));
  });

  for (final profileExpired in [false, true]) {
    test('recovery waits for in-flight validation (expired=$profileExpired)',
        () async {
      final billStarted = Completer<void>();
      final profileStarted = Completer<void>();
      final releaseBill = Completer<void>();
      final releaseProfile = Completer<void>();
      var profiles = 0;
      intercept = (_, uri) async {
        if (uri.queryParameters['access_token'] == _oldToken) {
          if (uri.path == _profilePath && ++profiles == 2) {
            profileStarted.complete();
            await releaseProfile.future;
            return profileExpired ? _expired : _ok({'userid': _studentId});
          }
          if (uri.path == _billsPath) {
            billStarted.complete();
            await releaseBill.future;
            return _expired;
          }
          if (uri.path == _cardPath) return _expired;
        }
        return null;
      };

      final bills = fetch(_billsPath);
      await billStarted.future;
      final card = fetch(_cardPath);
      await profileStarted.future;
      releaseBill.complete();
      await Future<void>.delayed(Duration.zero);
      releaseProfile.complete();
      await Future.wait([bills, card]);

      expect(account.authorizations, 1);
      expect(http.seen.where((uri) => uri.path == _loginPath), hasLength(1));
    });
  }

  test('a late old-token rejection keeps the already renewed token', () async {
    final oldBillStarted = Completer<void>();
    final releaseOldBill = Completer<void>();
    intercept = (_, uri) async {
      if (uri.queryParameters['access_token'] == _oldToken) {
        if (uri.path == _billsPath) {
          oldBillStarted.complete();
          await releaseOldBill.future;
          return _expired;
        }
        if (uri.path == _cardPath) return _expired;
      }
      return null;
    };
    final bills = fetch(_billsPath);
    await oldBillStarted.future;
    await fetch(_cardPath);
    releaseOldBill.complete();
    await bills;

    expect(account.authorizations, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString(SecureAppStore.campusCardSessionKey)!)[
          'access_token'],
      _newToken,
    );
  });

  test('an unavailable SSO session still asks for manual login', () async {
    account.callback = null;
    intercept = (_, uri) => uri.path == _profilePath ? _expired : null;

    await expectLater(
      service.fetchCardInfo(),
      throwsA(isA<CampusCardAuthRequiredException>()),
    );

    expect(account.authorizations, 1);
    expect(http.seen.where((uri) => uri.path == _loginPath), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SecureAppStore.campusCardSessionKey), isNull);
  });

  test('a rejected replacement token does not loop through SSO', () async {
    intercept = (_, uri) =>
        {_profilePath, _cardPath}.contains(uri.path) ? _expired : null;

    await expectLater(
      service.fetchCardInfo(),
      throwsA(isA<CampusCardAuthRequiredException>()),
    );

    expect(account.authorizations, 1);
    expect(http.seen.where((uri) => uri.path == _loginPath), hasLength(1));
  });

  test('a rejected retried bill request stops after one SSO recovery',
      () async {
    intercept = (_, uri) => uri.path == _billsPath ? _expired : null;

    await expectLater(
      service.fetchBills(startDate: start, endDate: end),
      throwsA(isA<CampusCardAuthRequiredException>()),
    );

    expect(account.authorizations, 1);
    expect(http.seen.where((uri) => uri.path == _billsPath), hasLength(2));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SecureAppStore.campusCardSessionKey), isNull);
  });

  test('an ordinary portal fault is not treated as token expiry', () async {
    intercept = (_, uri) => uri.path == _cardPath
        ? (status: 200, body: {'type': 3, 'errorcode': 500, 'message': 'fault'})
        : null;

    await expectLater(
      service.fetchCardInfo(),
      throwsA(isA<CampusCardException>()
          .having((error) => error.code, 'code', 'businessError')),
    );

    expect(account.authorizations, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SecureAppStore.campusCardSessionKey), isNotNull);
  });

  test('a network failure does not trigger SSO', () async {
    intercept = (_, __) => throw const SocketException('offline');

    await expectLater(
      service.fetchCardInfo(),
      throwsA(isA<CampusCardException>()
          .having((error) => error.code, 'code', 'network')),
    );

    expect(account.authorizations, 0);
  });

  test('an account switch during expiry does not authorize the new account',
      () async {
    intercept = (_, uri) async {
      if (uri.path == _profilePath) {
        await AcademicAccountStore().saveStudentId('STUDENT_2');
        return _expired;
      }
      return null;
    };

    await expectLater(
      service.fetchCardInfo(),
      throwsA(isA<CampusCardException>()
          .having((error) => error.code, 'code', 'accountMismatch')),
    );

    expect(account.authorizations, 0);
  });

  test('SSO must still return the current campus identity', () async {
    intercept = (_, uri) {
      if (uri.path == _profilePath) return _expired;
      if (uri.path == _loginPath) {
        return _ok({'access_token': _newToken, 'userid': 'STUDENT_2'});
      }
      return null;
    };

    await expectLater(
      service.fetchCardInfo(),
      throwsA(isA<CampusCardException>()
          .having((error) => error.code, 'code', 'accountMismatch')),
    );

    expect(account.authorizations, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SecureAppStore.campusCardSessionKey), isNull);
  });
}

class _AccountService extends UnifiedAccountService {
  Uri? callback =
      Uri.parse('https://eportal.shu.edu.cn/login?code=replacement-code');
  int authorizations = 0;

  @override
  Future<Uri?> authorizeCampusCard() async {
    authorizations++;
    return callback;
  }
}

class _HttpClient implements HttpClient {
  _HttpClient(this.reply);

  final Future<_Reply> Function(String, Uri) reply;
  final seen = <Uri>[];

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) async {
    expect(uri.scheme, 'https');
    expect(uri.host, 'eportal.shu.edu.cn');
    seen.add(uri);
    return _Request(() => reply(method, uri));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.reply);

  final Future<_Reply> Function() reply;

  @override
  final HttpHeaders headers = _Headers();

  @override
  bool followRedirects = true;

  @override
  int contentLength = -1;

  @override
  Future<HttpClientResponse> close() async {
    expect(followRedirects, isFalse);
    return _Response(await reply());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.reply);

  final _Reply reply;

  @override
  int get statusCode => reply.status;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(utf8.encode(jsonEncode(reply.body))).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
