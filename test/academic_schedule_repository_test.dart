import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/models/academic_schedule.dart';
import 'package:shuyo/data/repositories/academic_schedule_repository.dart';
import 'package:shuyo/data/services/academic_auth_service.dart';
import 'package:shuyo/data/services/academic_schedule_api_client.dart';

void main() {
  test('first schedule import starts at week one', () async {
    SharedPreferences.setMockInitialValues({
      'academic.schedule.anchorWeek': 7,
    });
    final repository = AcademicScheduleRepository(
      apiClient: _FakeAcademicScheduleApiClient(_schedule),
    );

    await repository.refreshSchedule();

    final state = await repository.loadWeekState();
    expect(state.currentWeek, 1);
  });

  test('repeated schedule import preserves the configured week', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = AcademicScheduleRepository(
      apiClient: _FakeAcademicScheduleApiClient(_schedule),
    );

    await repository.refreshSchedule();
    await repository.setCurrentWeek(7, now: DateTime(2026, 8, 31));
    await repository.refreshSchedule();

    final state = await repository.loadWeekState();
    expect(state.currentWeek, 7);
  });

  test('active week can be the vacation before week one', () {
    final repository = AcademicScheduleRepository(
      apiClient: _FakeAcademicScheduleApiClient(_schedule),
    );
    final state = ScheduleWeekState(
      currentWeek: 1,
      anchorMonday: DateTime(2026, 7, 13),
    );

    expect(
      repository.activeWeekFromState(
        _schedule,
        state,
        now: DateTime(2026, 7, 6),
      ),
      0,
    );
  });
}

class _FakeAcademicScheduleApiClient extends AcademicScheduleApiClient {
  _FakeAcademicScheduleApiClient(this.schedule)
      : super(authService: _FakeAcademicAuthService());

  final AcademicSchedule schedule;

  @override
  Future<AcademicSchedule> fetchCurrentSchedule() async => schedule;
}

class _FakeAcademicAuthService implements AcademicAuthService {
  @override
  Future<Set<String>> clearCookies() async => {};

  @override
  Future<void> markLoggedIn() async {}

  @override
  Future<String?> cookieHeader({Uri? targetUri}) async => null;

  @override
  Future<bool> hasWebVpnSession() async => false;

  @override
  Future<bool> hasAcademicSession() async => false;

  @override
  Future<WebVpnSessionStatus> validateDirectAcademicSession() async =>
      WebVpnSessionStatus.loginRequired;

  @override
  Future<WebVpnSessionStatus> validateWebVpnSession() async =>
      WebVpnSessionStatus.loginRequired;
}

final _schedule = AcademicSchedule(
  term: const AcademicTerm(
    yearCode: '2025',
    termCode: '16',
    academicYearName: '2025-2026',
    termName: '春',
    studentName: '',
    studentId: '',
    className: '',
  ),
  sessions: const [],
  untimedCourses: const [],
  fetchedAt: DateTime(2026, 8, 31),
);
