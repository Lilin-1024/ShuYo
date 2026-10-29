import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/app/app_shell.dart';
import 'package:shuyo/core/classroom_url_resolver.dart';
import 'package:shuyo/data/services/client_settings_service.dart';
import 'package:shuyo/data/services/unified_account_service.dart';
import 'package:shuyo/features/home/empty_classroom_page.dart';
import 'package:shuyo/features/onboarding/startup_onboarding.dart';

class _PendingAccount extends UnifiedAccountService {
  final recovery = Completer<WebVpnRecoveryOutcome>();
  int recoveries = 0;

  @override
  Future<WebVpnRecoveryOutcome> recoverWebVpn() {
    recoveries++;
    return recovery.future;
  }
}

void main() {
  setUp(() {
    ClassroomUrlResolver.configure(useWebVpn: true);
    SharedPreferences.setMockInitialValues({
      'client.network.webvpn.enabled': true,
    });
  });
  tearDown(() => ClassroomUrlResolver.configure(useWebVpn: false));

  testWidgets('automatic recovery cannot undo a user disabling WebVPN',
      (tester) async {
    final controller = StartupOnboardingController();
    final account = _PendingAccount();
    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        initialWebVpnEnabled: true,
        selectedThemeId: 'default',
        followSystemTheme: false,
        onThemeChanged: (_) async {},
        onFollowSystemThemeChanged: (_) async {},
        academicLoginSignal: 0,
        initialHasAcademicSession: false,
        initialAcademicStudentId: null,
        onboardingController: controller,
        unifiedAccountService: account,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('空教室'), 180);
    await tester.tap(find.text('空教室'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // No stored token: opening the page starts automatic recovery. Keep
    // that recovery pending while the user turns WebVPN off.
    for (var frame = 0; frame < 10 && account.recoveries == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final page = tester.widget<EmptyClassroomPage>(
      find.byType(EmptyClassroomPage),
    );

    expect(account.recoveries, 1);
    expect(await controller.setWebVpnEnabled(false), isTrue);
    account.recovery.complete(WebVpnRecoveryOutcome.recovered);
    await tester.pumpAndSettle();

    expect(controller.webVpnEnabled, isFalse);
    expect(ClassroomUrlResolver.usesWebVpn, isFalse);
    expect(
      (await ClientSettingsService().loadNetworkSettings()).webVpnEnabled,
      isFalse,
    );
    expect(await page.onWebVpnRecoveryRequired!(false), isFalse);
    expect(account.recoveries, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    controller.dispose();
  });
}
