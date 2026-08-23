import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/features/onboarding/startup_onboarding.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app({
    required bool completed,
    bool academicLoggedIn = false,
    bool forumLoggedIn = false,
    StartupOnboardingController? controller,
  }) {
    return MaterialApp(
      home: StartupOnboarding(
        initiallyCompleted: completed,
        initialAcademicLoggedIn: academicLoggedIn,
        initialForumLoggedIn: forumLoggedIn,
        onAcademicLoginCompleted: () {},
        onForumLoginCompleted: () {},
        controller: controller ?? StartupOnboardingController(),
        child: const Scaffold(body: Text('主页')),
      ),
    );
  }

  testWidgets('shows onboarding while logged out', (tester) async {
    await tester.pumpWidget(app(completed: false));

    expect(find.text('主页'), findsOneWidget);
    expect(find.text('欢迎使用 ShuYo'), findsOneWidget);
    final panel = find.byKey(const ValueKey('startup-onboarding-panel'));
    final initialTop = tester.getTopLeft(panel).dy;

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    final middleTop = tester.getTopLeft(panel).dy;
    await tester.pumpAndSettle();
    final finalTop = tester.getTopLeft(panel).dy;

    expect(middleTop, lessThan(initialTop));
    expect(finalTop, lessThan(middleTop));
    expect(find.textContaining('继续即表示您已同意'), findsOneWidget);
    final termsTop = tester.getTopLeft(find.textContaining('继续即表示您已同意')).dy;
    final continueTop = tester.getTopLeft(find.text('继续')).dy;
    expect(termsTop, lessThan(continueTop));
    expect(
      tester.getSize(find.byType(Image).first).width,
      greaterThan(tester.getSize(find.byIcon(Icons.calendar_month)).width),
    );
  });

  testWidgets('skips onboarding after it has been completed', (tester) async {
    await tester.pumpWidget(app(completed: true));

    expect(find.text('主页'), findsOneWidget);
    expect(find.text('欢迎使用 ShuYo'), findsNothing);
  });

  testWidgets('third page shows account actions and allows forum skip',
      (tester) async {
    await tester.pumpWidget(app(completed: false, academicLoggedIn: true));
    await tester.pumpAndSettle();

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

  testWidgets('onboarding asks for the campus account first', (tester) async {
    await tester.pumpWidget(app(completed: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('乐乎账户'));
    await tester.pump();

    expect(find.text('请先登录上大校园账户'), findsOneWidget);
  });

  testWidgets('second and third pages can return to the previous page',
      (tester) async {
    await tester.pumpWidget(app(completed: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('开启通知'), findsOneWidget);
    expect(find.byTooltip('返回上一页'), findsOneWidget);

    await tester.tap(find.byTooltip('返回上一页'));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用 ShuYo'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('登录'), findsOneWidget);

    await tester.tap(find.byTooltip('返回上一页'));
    await tester.pumpAndSettle();
    expect(find.text('开启通知'), findsOneWidget);
  });

  testWidgets('reopens completed onboarding on the account page',
      (tester) async {
    final controller = StartupOnboardingController();
    await tester.pumpWidget(
      app(
        completed: true,
        academicLoggedIn: true,
        forumLoggedIn: true,
        controller: controller,
      ),
    );

    controller.openAccountManager(
      academicLoggedIn: true,
      forumLoggedIn: true,
    );
    await tester.pumpAndSettle();

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('已登录'), findsNWidgets(2));
    expect(find.text('完成'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('登录'), findsNothing);
  });

  testWidgets('keeps onboarding content top-aligned on an iPhone 17 viewport',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(completed: false));
    await tester.pumpAndSettle();

    final subtitleBottom = tester.getBottomLeft(find.text('让校园生活更简单')).dy;
    final firstItemTop = tester.getTopLeft(find.text('课表与空教室')).dy;
    final secondItemTop = tester.getTopLeft(find.text('乐乎论坛')).dy;
    final pages = find.byKey(const ValueKey('startup-onboarding-pages'));
    final initialPagesSize = tester.getSize(pages);
    expect(firstItemTop - subtitleBottom, lessThan(60));
    expect(secondItemTop - firstItemTop, greaterThanOrEqualTo(76));

    final panelTopBefore = tester
        .getTopLeft(find.byKey(const ValueKey('startup-onboarding-panel')))
        .dy;
    await tester.tap(find.text('继续'));
    await tester.pump(const Duration(milliseconds: 160));
    final panelTopDuring = tester
        .getTopLeft(find.byKey(const ValueKey('startup-onboarding-panel')))
        .dy;
    expect(panelTopDuring, panelTopBefore);
    await tester.pumpAndSettle();
    expect(tester.getSize(pages), initialPagesSize);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(tester.getSize(pages), initialPagesSize);
    expect(tester.takeException(), isNull);
  });
}
