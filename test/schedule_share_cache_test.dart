import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/schedule_share_cache.dart';
import 'package:shuyo/data/services/schedule_share_service.dart';
import 'package:shuyo/data/services/student_identity_service.dart';

final _start = DateTime.utc(2030, 1, 1);

StudentIdentitySession _session(String studentId) => StudentIdentitySession(
      token: 'token-$studentId',
      studentId: studentId,
      maskedStudentId: studentId,
      expiresAt: _start.add(const Duration(days: 1)),
    );

ShareCodeInfo _code(String code,
        {Duration lifetime = const Duration(days: 1)}) =>
    ShareCodeInfo(
      id: 'share-$code',
      code: code,
      expiresAt: _start.add(lifetime),
      termLabel: '2030 春',
      includeNote: false,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final current in [_code('ABC123'), null]) {
    test('reuses memory and disk for ${current?.code ?? 'no share code'}',
        () async {
      final identity = _Identity(_session('student-a'));
      final api = _Api(() async => current);
      final first =
          ScheduleShareCache(identityService: identity, now: () => _start);
      final reopened =
          ScheduleShareCache(identityService: identity, now: () => _start);
      addTearDown(() {
        first.dispose();
        reopened.dispose();
        identity.dispose();
      });

      await first.refresh(api);
      await first.refresh(api);
      await reopened.refresh(api);

      expect(first.code, current);
      expect(reopened.code, current);
      expect(api.calls, 1);
      expect(identity.checks, 1);
    });
  }

  test('keeps stale data on failure and replaces it on the next success',
      () async {
    var now = _start;
    final identity = _Identity(_session('student-a'));
    final oldCode = _code('ABC123');
    final newCode = _code('XYZ789');
    final api = _Api(() async => oldCode);
    final cache = ScheduleShareCache(identityService: identity, now: () => now);
    addTearDown(() {
      cache.dispose();
      identity.dispose();
    });
    await cache.refresh(api);

    now = now.add(ScheduleShareCache.freshness);
    api.lookup = () async => throw StateError('offline');
    await cache.refresh(api);
    expect(cache.code, oldCode);

    final response = Completer<ShareCodeInfo?>();
    api.lookup = () => response.future;
    final refresh = cache.refresh(api);
    expect(cache.code, oldCode);
    response.complete(newCode);
    await refresh;
    expect(cache.code, newCode);
    expect(api.calls, 3);
  });

  for (final replacement in [_code('XYZ789'), null]) {
    test('a late lookup cannot undo ${replacement?.code ?? 'destruction'}',
        () async {
      var now = _start;
      final identity = _Identity(_session('student-a'));
      final oldCode = _code('ABC123');
      final api = _Api(() async => oldCode);
      final cache =
          ScheduleShareCache(identityService: identity, now: () => now);
      final reopened =
          ScheduleShareCache(identityService: identity, now: () => now);
      addTearDown(() {
        cache.dispose();
        reopened.dispose();
        identity.dispose();
      });
      await cache.refresh(api);

      now = now.add(ScheduleShareCache.freshness);
      final started = Completer<void>();
      final response = Completer<ShareCodeInfo?>();
      api.lookup = () {
        started.complete();
        return response.future;
      };
      final refresh = cache.refresh(api);
      await started.future;
      expect(await cache.replace(identity.session!, replacement), isTrue);
      response.complete(oldCode);
      await refresh;
      await reopened.refresh(api);

      expect(cache.code, replacement);
      expect(reopened.code, replacement);
      expect(api.calls, 2);
    });
  }

  test('a different account cannot reuse a persisted share code', () async {
    final firstIdentity = _Identity(_session('student-a'));
    final secondIdentity = _Identity(_session('student-b'));
    final firstCache =
        ScheduleShareCache(identityService: firstIdentity, now: () => _start);
    final secondCache =
        ScheduleShareCache(identityService: secondIdentity, now: () => _start);
    addTearDown(() {
      firstCache.dispose();
      secondCache.dispose();
      firstIdentity.dispose();
      secondIdentity.dispose();
    });
    await firstCache.refresh(_Api(() async => _code('ABC123')));
    final api = _Api(() async => null);
    await secondCache.refresh(api);

    expect(secondCache.code, isNull);
    expect(api.calls, 1);
  });

  test('identity loss clears the code and rejects an in-flight response',
      () async {
    final identity = _Identity(_session('student-a'));
    final cache =
        ScheduleShareCache(identityService: identity, now: () => _start);
    addTearDown(() {
      cache.dispose();
      identity.dispose();
    });
    final oldCode = _code('ABC123');
    await cache.refresh(_Api(() async => oldCode));
    final started = Completer<void>();
    final response = Completer<ShareCodeInfo?>();
    final refresh = cache.refresh(_Api(() {
      started.complete();
      return response.future;
    }), force: true);
    await started.future;
    identity.clearSession();
    expect(cache.code, isNull);
    response.complete(oldCode);
    await refresh;
    expect(cache.code, isNull);

    identity.session = _session('student-a');
    final api = _Api(() async => null);
    await cache.refresh(api);
    expect(api.calls, 1);
    expect(cache.code, isNull);
  });

  test('an expired code is hidden and rechecked before the five-minute limit',
      () async {
    var now = _start;
    final identity = _Identity(_session('student-a'));
    final api =
        _Api(() async => _code('ABC123', lifetime: const Duration(minutes: 1)));
    final cache = ScheduleShareCache(identityService: identity, now: () => now);
    addTearDown(() {
      cache.dispose();
      identity.dispose();
    });
    await cache.refresh(api);
    now = now.add(const Duration(minutes: 1));
    expect(cache.code, isNull);
    api.lookup = () async => null;
    await cache.refresh(api);
    expect(api.calls, 2);
    expect(cache.code, isNull);
  });
}

class _Identity extends StudentIdentityService {
  _Identity(this.session)
      : super(httpClient: MockClient((_) async => http.Response('{}', 200)));

  StudentIdentitySession? session;
  int checks = 0;

  @override
  bool get isVerified => session != null;

  @override
  Future<StudentIdentitySession?> loadLocalSession() async => session;

  @override
  Future<StudentIdentitySession?> checkCurrentSession() async {
    checks++;
    return session;
  }

  void clearSession() {
    session = null;
    notifyListeners();
  }
}

class _Api extends ScheduleShareApi {
  _Api(this.lookup)
      : super(client: MockClient((_) async => http.Response('{}', 200)));

  Future<ShareCodeInfo?> Function() lookup;
  int calls = 0;

  @override
  Future<ShareCodeInfo?> current(String token) {
    calls++;
    return lookup();
  }
}
