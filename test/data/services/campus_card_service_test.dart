import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/models/campus_card.dart';
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

  for (final inclusiveDays in [1, 90, 91, 180, 181]) {
    test('bill requests cover $inclusiveDays dates in ranges of at most 90',
        () async {
      intercept = (method, uri) {
        if (uri.path != _billsPath) return null;
        expect(method, 'GET');
        return _ok({'bills': <Map<String, dynamic>>[]});
      };
      final first = DateTime.utc(2026, 1, 1);
      final last = first.add(Duration(days: inclusiveDays - 1));

      final bills = await service.fetchBills(
        startDate: DateTime(first.year, first.month, first.day, 23, 59),
        endDate: DateTime(last.year, last.month, last.day, 1),
      );

      final requests =
          http.seen.where((uri) => uri.path == _billsPath).toList();
      expect(requests, hasLength((inclusiveDays / 90).ceil()));
      final covered = <DateTime>[];
      for (final uri in requests) {
        final first = DateTime.parse(uri.queryParameters['StartDate']!);
        final last = DateTime.parse(uri.queryParameters['EndDate']!);
        final rangeStart = DateTime.utc(first.year, first.month, first.day);
        final rangeEnd = DateTime.utc(last.year, last.month, last.day);
        final count = rangeEnd.difference(rangeStart).inDays + 1;
        expect(count, inInclusiveRange(1, 90));
        for (var day = 0; day < count; day++) {
          covered.add(rangeStart.add(Duration(days: day)));
        }
      }
      expect(
        requests.first.queryParameters['EndDate'],
        last.toIso8601String().substring(0, 10),
      );
      expect(requests.last.queryParameters['StartDate'], '2026-01-01');
      covered.sort((a, b) => a.compareTo(b));
      expect(
        covered.map((date) => (date.year, date.month, date.day)),
        List.generate(inclusiveDays, (day) {
          final date = first.add(Duration(days: day));
          return (date.year, date.month, date.day);
        }),
      );
      expect(bills, isEmpty);
      expect(http.seen.where((uri) => uri.path == _profilePath), hasLength(1));
      expect(account.authorizations, 0);
    });
  }

  test('a full leap year crossing December covers every date exactly once',
      () async {
    intercept = (_, uri) => uri.path == _billsPath
        ? _ok({
            'bills': [
              {
                'billname': uri.queryParameters['StartDate'],
                'paytime': uri.queryParameters['StartDate'],
                'amount': '-1',
              },
            ],
          })
        : null;

    final bills = await service.fetchBills(
      startDate: DateTime(2023, 12, 20),
      endDate: DateTime(2024, 12, 19),
    );

    final requests = http.seen.where((uri) => uri.path == _billsPath).toList();
    expect(requests, hasLength(5));
    final covered = <String>[];
    for (final uri in requests) {
      final first = DateTime.parse(uri.queryParameters['StartDate']!);
      final last = DateTime.parse(uri.queryParameters['EndDate']!);
      var date = DateTime.utc(first.year, first.month, first.day);
      final end = DateTime.utc(last.year, last.month, last.day);
      expect(end.difference(date).inDays, inInclusiveRange(0, 89));
      while (!date.isAfter(end)) {
        covered.add(date.toIso8601String().substring(0, 10));
        date = date.add(const Duration(days: 1));
      }
    }
    expect(requests.first.queryParameters['EndDate'], '2024-12-19');
    expect(requests.last.queryParameters['StartDate'], '2023-12-20');
    covered.sort();
    final first = DateTime.utc(2023, 12, 20);
    expect(
      covered,
      List.generate(
          366,
          (day) => first
              .add(Duration(days: day))
              .toIso8601String()
              .substring(0, 10)),
    );
    expect(covered.where((day) => day == '2024-02-29'), hasLength(1));
    expect(bills, hasLength(5));
    expect(http.seen.where((uri) => uri.path == _profilePath), hasLength(1));
    expect(account.authorizations, 0);
  });

  test('invalid bill dates fail before any session or HTTP request', () async {
    await expectLater(
      service.fetchBills(
        startDate: DateTime(2026, 10, 2),
        endDate: DateTime(2026, 10, 1),
      ),
      throwsA(isA<CampusCardException>()
          .having((error) => error.code, 'code', 'invalidDates')),
    );

    expect(http.seen, isEmpty);
    expect(account.authorizations, 0);
  });

  for (final errorCode in ['businessError', 'invalidResponse']) {
    test('a later bill range $errorCode rejects the whole query', () async {
      var ranges = 0;
      intercept = (_, uri) {
        if (uri.path != _billsPath) return null;
        if (++ranges == 2) {
          return errorCode == 'businessError'
              ? (
                  status: 200,
                  body: {'type': 3, 'errorcode': 0, 'message': 'fault'}
                )
              : _ok({
                  'bills': [
                    {'billname': 'malformed record'}
                  ]
                });
        }
        return _ok({
          'bills': [
            {
              'billname': 'first range',
              'paytime': '2026-01-01',
              'amount': '-1'
            },
          ],
        });
      };

      await expectLater(
        service.fetchBills(
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 7, 1),
        ),
        throwsA(isA<CampusCardException>()
            .having((error) => error.code, 'code', errorCode)),
      );

      expect(ranges, 2);
      expect(http.seen.where((uri) => uri.path == _profilePath), hasLength(1));
      expect(account.authorizations, 0);
    });
  }

  test('identical bill records remain separate transactions', () async {
    intercept = (_, uri) {
      if (uri.path != _billsPath) return null;
      final day = uri.queryParameters['StartDate']!;
      final bill = {
        'billname': '食堂',
        'paytime': '$day 12:00:00',
        'amount': '-5.00',
      };
      return _ok({
        'bills': [bill, bill]
      });
    };

    final bills = await service.fetchBills(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 4, 2),
    );

    expect(bills, hasLength(4));
    expect(bills.map((bill) => bill.payTime), [
      '2026-01-03 12:00:00',
      '2026-01-03 12:00:00',
      '2026-01-01 12:00:00',
      '2026-01-01 12:00:00',
    ]);
    expect(
        bills.every((bill) => bill.name == '食堂' && bill.amount == -5), isTrue);
    expect(() => bills.clear(), throwsUnsupportedError);
  });

  test('an account switch during a later range rejects all bill records',
      () async {
    var ranges = 0;
    intercept = (_, uri) async {
      if (uri.path != _billsPath) return null;
      if (++ranges == 2) {
        await AcademicAccountStore().saveStudentId('STUDENT_2');
      }
      return _ok({
        'bills': [
          {'billname': '食堂', 'paytime': '2026-01-01', 'amount': '-1'},
        ],
      });
    };

    await expectLater(
      service.fetchBills(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 7, 1),
      ),
      throwsA(isA<CampusCardException>()
          .having((error) => error.code, 'code', 'accountMismatch')),
    );

    expect(ranges, 2);
    expect(account.authorizations, 0);
    expect(http.seen.where((uri) => uri.path == _loginPath), isEmpty);
  });

  test('expiry in a later range resets cumulative progress before retrying',
      () async {
    final snapshots = <List<CampusCardBill>>[];
    var oldRanges = 0;
    intercept = (_, uri) {
      if (uri.path != _billsPath) return null;
      final token = uri.queryParameters['access_token'];
      if (token == _oldToken && ++oldRanges == 2) return _expired;
      return _ok({
        'bills': [
          {
            'billname': token == _oldToken ? 'discarded old result' : '食堂',
            'paytime': uri.queryParameters['StartDate'],
            'amount': '-1',
          },
        ],
      });
    };

    final bills = await service.fetchBills(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 4, 2),
      onProgress: snapshots.add,
    );

    expect(snapshots.map((snapshot) => snapshot.length), [0, 1, 0, 1, 2]);
    expect(snapshots[1].single.name, 'discarded old result');
    expect(snapshots[3].single.name, '食堂');
    expect(snapshots.last, bills);
    expect(() => snapshots[1].clear(), throwsUnsupportedError);
    expect(bills, hasLength(2));
    expect(bills.every((bill) => bill.name == '食堂'), isTrue);
    final requests = http.seen.where((uri) => uri.path == _billsPath).toList();
    expect(requests.map((uri) => uri.queryParameters['StartDate']), [
      '2026-01-03',
      '2026-01-01',
      '2026-01-03',
      '2026-01-01',
    ]);
    expect(requests.map((uri) => uri.queryParameters['access_token']), [
      _oldToken,
      _oldToken,
      _newToken,
      _newToken,
    ]);
    expect(http.seen.where((uri) => uri.path == _profilePath), hasLength(1));
    expect(account.authorizations, 1);
    expect(http.seen.where((uri) => uri.path == _loginPath), hasLength(1));
  });

  test('expiry in a replacement range still stops after one SSO recovery',
      () async {
    final rangesByToken = <String, int>{};
    intercept = (_, uri) {
      if (uri.path != _billsPath) return null;
      final token = uri.queryParameters['access_token']!;
      final ranges = (rangesByToken[token] ?? 0) + 1;
      rangesByToken[token] = ranges;
      if (ranges == 2) return _expired;
      return _ok({
        'bills': [
          {'billname': '食堂', 'paytime': '2026-01-01', 'amount': '-1'},
        ],
      });
    };

    await expectLater(
      service.fetchBills(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 4, 2),
      ),
      throwsA(isA<CampusCardAuthRequiredException>()),
    );

    expect(rangesByToken, {_oldToken: 2, _newToken: 2});
    expect(account.authorizations, 1);
    expect(http.seen.where((uri) => uri.path == _loginPath), hasLength(1));
  });

  test('bill progress exposes immutable cumulative snapshots after each range',
      () async {
    final snapshots = <List<CampusCardBill>>[];
    intercept = (_, uri) => uri.path == _billsPath
        ? _ok({
            'bills': [
              {
                'billname': uri.queryParameters['EndDate'],
                'paytime': uri.queryParameters['EndDate'],
                'amount': '-1',
              },
            ],
          })
        : null;

    final bills = await service.fetchBills(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 7, 1),
      onProgress: snapshots.add,
    );

    expect(snapshots.map((snapshot) => snapshot.length), [0, 1, 2, 3]);
    expect(snapshots[1].single.payTime, '2026-07-01');
    expect(snapshots.last, bills);
    expect(bills.map((bill) => bill.payTime), [
      '2026-07-01',
      '2026-04-02',
      '2026-01-02',
    ]);
    expect(() => snapshots[1].clear(), throwsUnsupportedError);
    expect(http.seen.where((uri) => uri.path == _profilePath), hasLength(1));
  });

  test('empty ranges keep scanning without publishing unchanged progress',
      () async {
    final snapshots = <List<CampusCardBill>>[];
    var ranges = 0;
    intercept = (_, uri) {
      if (uri.path != _billsPath) return null;
      final range = ++ranges;
      if (range != 2 && range != 5) {
        return _ok({'bills': <Map<String, dynamic>>[]});
      }
      return _ok({
        'bills': [
          {
            'billname': range == 2 ? 'recent' : 'older',
            'paytime': uri.queryParameters['EndDate'],
            'amount': '-1',
          },
        ],
      });
    };

    final bills = await service.fetchBills(
      startDate: DateTime(2023, 12, 20),
      endDate: DateTime(2024, 12, 19),
      onProgress: snapshots.add,
    );

    expect(ranges, 5);
    final requests = http.seen.where((uri) => uri.path == _billsPath).toList();
    expect(requests.last.queryParameters['StartDate'], '2023-12-20');
    expect(snapshots.map((snapshot) => snapshot.length), [0, 1, 2]);
    expect(snapshots[1].single.name, 'recent');
    expect(snapshots.last, bills);
    expect(bills.map((bill) => bill.name), ['recent', 'older']);
    expect(http.seen.where((uri) => uri.path == _profilePath), hasLength(1));
  });

  test('a cancelled bill query starts no session or requests', () async {
    final snapshots = <List<CampusCardBill>>[];

    await expectLater(
      service.fetchBills(
        startDate: DateTime(1900),
        endDate: DateTime(2026, 10, 28),
        onProgress: snapshots.add,
        shouldCancel: () => true,
      ),
      throwsA(isA<CampusCardException>()
          .having((error) => error.code, 'code', 'cancelled')),
    );

    expect(snapshots, isEmpty);
    expect(http.seen, isEmpty);
    expect(account.authorizations, 0);
  });

  test('cancelling a long history after progress stops before the next range',
      () async {
    var cancelled = false;
    final snapshots = <List<CampusCardBill>>[];
    intercept = (_, uri) => uri.path == _billsPath
        ? _ok({
            'bills': [
              {'billname': '食堂', 'paytime': '2026-10-28', 'amount': '-1'},
            ],
          })
        : null;

    await expectLater(
      service.fetchBills(
        startDate: DateTime(1900),
        endDate: DateTime(2026, 10, 28),
        onProgress: (snapshot) {
          snapshots.add(snapshot);
          if (snapshot.isNotEmpty) cancelled = true;
        },
        shouldCancel: () => cancelled,
      ),
      throwsA(isA<CampusCardException>()
          .having((error) => error.code, 'code', 'cancelled')),
    );

    expect(snapshots.map((snapshot) => snapshot.length), [0, 1]);
    expect(http.seen.where((uri) => uri.path == _billsPath), hasLength(1));
    expect(http.seen.where((uri) => uri.path == _profilePath), hasLength(1));
    expect(account.authorizations, 0);
  });

  test('cancelling an in-flight range suppresses its result and SSO recovery',
      () async {
    var cancelled = false;
    final snapshots = <List<CampusCardBill>>[];
    intercept = (_, uri) {
      if (uri.path != _billsPath) return null;
      cancelled = true;
      return _expired;
    };

    await expectLater(
      service.fetchBills(
        startDate: DateTime(1900),
        endDate: DateTime(2026, 10, 28),
        onProgress: snapshots.add,
        shouldCancel: () => cancelled,
      ),
      throwsA(isA<CampusCardException>()
          .having((error) => error.code, 'code', 'cancelled')),
    );

    expect(snapshots.map((snapshot) => snapshot.length), [0]);
    expect(http.seen.where((uri) => uri.path == _billsPath), hasLength(1));
    expect(http.seen.where((uri) => uri.path == _loginPath), isEmpty);
    expect(account.authorizations, 0);
  });

  test('cancelling during validation does not reauthorize an expired session',
      () async {
    var cancelled = false;
    intercept = (_, uri) {
      if (uri.path != _profilePath) return null;
      cancelled = true;
      return _expired;
    };

    await expectLater(
      service.fetchBills(
        startDate: DateTime(1900),
        endDate: DateTime(2026, 10, 28),
        shouldCancel: () => cancelled,
      ),
      throwsA(isA<CampusCardException>()
          .having((error) => error.code, 'code', 'cancelled')),
    );

    expect(http.seen, hasLength(1));
    expect(http.seen.single.path, _profilePath);
    expect(account.authorizations, 0);
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
