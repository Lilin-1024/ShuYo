import 'package:flutter/foundation.dart';
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
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('settings no longer exposes account logout actions',
      (tester) async {
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
        ),
      ),
    );

    expect(find.text('退出乐乎论坛账户'), findsNothing);
    expect(find.text('退出上大校园账户'), findsNothing);
  });

  testWidgets('iOS cannot disable automatic WebVPN proxy', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      SharedPreferences.setMockInitialValues({
        ClientSettingsService.autoUseWebVpnProxyKey: true,
      });

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
          ),
        ),
      );

      await tester.tap(find.text('WebVPN代理'));
      await tester.pumpAndSettle();
      expect(find.text('自动使用WebVPN代理'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.text('暂不支持，待后续版本接入'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(
        (await ClientSettingsService().loadNetworkSettings())
            .autoUseWebVpnProxy,
        isTrue,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
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
