import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/repositories/academic_schedule_repository.dart';
import 'package:shuyo/data/repositories/client_backend_repository.dart';
import 'package:shuyo/data/services/academic_schedule_notification_service.dart';
import 'package:shuyo/data/services/academic_schedule_api_client.dart';
import 'package:shuyo/data/services/academic_auth_service.dart';
import 'package:shuyo/data/services/client_settings_service.dart';
import 'package:shuyo/features/settings/client_settings_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('settings exposes independent account logout actions',
      (tester) async {
    var forumLoggedOut = false;
    var academicLoggedOut = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ClientSettingsPage(
          settingsService: ClientSettingsService(),
          scheduleNotificationService: AcademicScheduleNotificationService(
            repository: AcademicScheduleRepository(
              apiClient: AcademicScheduleApiClient(
                authService: _FakeAcademicAuthService(),
                httpClient: MockClient(
                  (_) async => http.Response('{}', 200),
                ),
              ),
            ),
          ),
          backendRepository: ClientBackendRepository(),
          selectedThemeId: 'default',
          followSystemTheme: false,
          onThemeChanged: (_) async {},
          onFollowSystemThemeChanged: (_) async {},
          hasLocalAccount: true,
          hasAcademicAccount: true,
          onForumLogout: () async => forumLoggedOut = true,
          onAcademicLogout: () async => academicLoggedOut = true,
        ),
      ),
    );

    expect(find.text('退出乐乎论坛账户'), findsOneWidget);
    expect(find.text('退出上大校园账户'), findsOneWidget);

    await tester.tap(find.text('退出乐乎论坛账户'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出'));
    await tester.pumpAndSettle();

    expect(forumLoggedOut, isTrue);
    expect(academicLoggedOut, isFalse);
  });
}

class _FakeAcademicAuthService implements AcademicAuthService {
  @override
  Future<Set<String>> clearCookies() async => {};

  @override
  Future<String?> cookieHeader() async => null;

  @override
  Future<bool> hasWebVpnSession() async => false;
}
