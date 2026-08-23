import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/features/onboarding/startup_onboarding.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app({required bool completed, bool academicLoggedIn = false}) {
    return MaterialApp(
      home: StartupOnboarding(
        initiallyCompleted: completed,
        initialAcademicLoggedIn: academicLoggedIn,
        initialForumLoggedIn: false,
        onAcademicLoginCompleted: () {},
        child: const Scaffold(body: Text('主页')),
      ),
    );
  }

  testWidgets('shows onboarding while logged out', (tester) async {
    await tester.pumpWidget(app(completed: false));

    expect(find.text('欢迎使用 ShuYo'), findsOneWidget);
  });

  testWidgets('skips onboarding after it has been completed', (tester) async {
    await tester.pumpWidget(app(completed: true));

    expect(find.text('主页'), findsOneWidget);
    expect(find.text('欢迎使用 ShuYo'), findsNothing);
  });

  testWidgets('third page shows account actions and allows forum skip',
      (tester) async {
    await tester.pumpWidget(app(completed: false, academicLoggedIn: true));

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(find.text('上大校园账户'), findsOneWidget);
    expect(find.text('乐乎账户'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(find.text('主页'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'client.onboarding.startup.completed',
      ),
      isTrue,
    );
  });
}
