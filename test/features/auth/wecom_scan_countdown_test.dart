import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/features/auth/widgets/wecom_scan_countdown.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';

void main() {
  testWidgets('counts down using elapsed time and stops at zero',
      (tester) async {
    var now = DateTime(2026);
    DateTime clock() => now;
    await tester.pumpWidget(MaterialApp(
      theme: ShuYoThemes.byId('blue_light').themeData(),
      home: Scaffold(
        body: WeComScanCountdown(
          duration: const Duration(seconds: 10),
          clock: clock,
        ),
      ),
    ));

    double value() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    expect(value(), 1);
    expect(find.text('剩余'), findsOneWidget);
    expect(find.text('10s'), findsOneWidget);
    now = now.add(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(value(), closeTo(0.6, 0.00001));
    expect(find.text('6s'), findsOneWidget);
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 1));
    expect(value(), 0);
    expect(find.text('0s'), findsOneWidget);
    now = now.subtract(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 5));
    expect(value(), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('progress decreases continuously between second changes',
      (tester) async {
    var now = DateTime(2026);
    DateTime clock() => now;
    await tester.pumpWidget(MaterialApp(
      theme: ShuYoThemes.byId('blue_light').themeData(),
      home: Scaffold(
        body: WeComScanCountdown(
          duration: const Duration(seconds: 10),
          clock: clock,
        ),
      ),
    ));

    double value() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    expect(value(), 1);
    expect(find.text('10s'), findsOneWidget);

    now = now.add(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    final first = value();
    expect(first, closeTo(0.975, 0.00001));
    expect(find.text('10s'), findsOneWidget);

    now = now.add(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(value(), closeTo(0.95, 0.00001));
    expect(value(), lessThan(first));
    expect(find.text('10s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('countdown keeps real duration when animations are disabled',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    var now = DateTime(2026);
    DateTime clock() => now;
    await tester.pumpWidget(MaterialApp(
      theme: ShuYoThemes.byId('blue_light').themeData(),
      home: Scaffold(
        body: WeComScanCountdown(
          duration: const Duration(seconds: 10),
          clock: clock,
        ),
      ),
    ));

    double value() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    now = now.add(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    expect(value(), closeTo(0.975, 0.00001));
    expect(find.text('10s'), findsOneWidget);

    now = now.add(const Duration(milliseconds: 4750));
    await tester.pump(const Duration(milliseconds: 4750));
    expect(value(), closeTo(0.5, 0.00001));
    expect(find.text('5s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rounds up seconds and keeps their display area fixed',
      (tester) async {
    var now = DateTime(2026);
    DateTime clock() => now;
    await tester.pumpWidget(MaterialApp(
      theme: ShuYoThemes.byId('blue_light').themeData(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 180,
            child: WeComScanCountdown(
              duration: const Duration(seconds: 90),
              clock: clock,
            ),
          ),
        ),
      ),
    ));

    final indicator = find.byType(LinearProgressIndicator);
    final initialProgressRect = tester.getRect(indicator);
    final initialSecondsArea = tester.getRect(
      find
          .ancestor(of: find.text('90s'), matching: find.byType(SizedBox))
          .first,
    );
    expect(tester.getTopLeft(find.text('90s')).dx,
        closeTo(initialProgressRect.right + 4, 0.1));
    expect(initialProgressRect.center.dx,
        closeTo(tester.getCenter(find.byType(WeComScanCountdown)).dx, 0.1));
    expect(
      tester.widget<Text>(find.text('90s')).style!.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );

    now = now.add(const Duration(seconds: 81, milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('9s'), findsOneWidget);
    expect(tester.getRect(indicator), initialProgressRect);
    expect(tester.getTopLeft(find.text('9s')).dx,
        closeTo(initialProgressRect.right + 4, 0.1));
    expect(
      tester.getRect(
        find
            .ancestor(of: find.text('9s'), matching: find.byType(SizedBox))
            .first,
      ),
      initialSecondsArea,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resume corrects for time spent in the background',
      (tester) async {
    var now = DateTime(2026);
    DateTime clock() => now;
    await tester.pumpWidget(MaterialApp(
      theme: ShuYoThemes.byId('blue_light').themeData(),
      home: Scaffold(
        body: WeComScanCountdown(
          duration: const Duration(seconds: 20),
          clock: clock,
        ),
      ),
    ));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 2));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.25);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('uses supplied start time and theme tokens', (tester) async {
    final now = DateTime(2026);
    DateTime clock() => now;
    final light = ShuYoThemes.byId('blue_light');
    final dark = ShuYoThemes.byId('ink_teal');
    Widget page(ShuYoThemeSpec theme) => MaterialApp(
          theme: theme.themeData(),
          home: Scaffold(
            body: WeComScanCountdown(
              duration: const Duration(seconds: 20),
              startedAt: now.subtract(const Duration(seconds: 5)),
              clock: clock,
            ),
          ),
        );
    await tester.pumpWidget(page(light));
    var progress = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progress.value, 0.75);
    expect(progress.color, light.colors.accent);
    expect(progress.backgroundColor, light.colors.accentSoft);
    expect(progress.minHeight, 3);
    expect(tester.widget<Text>(find.text('剩余')).style!.color,
        light.colors.textSecondary);
    await tester.pumpWidget(page(dark));
    await tester.pump(const Duration(milliseconds: 300));
    progress = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(progress.value, 0.75);
    expect(progress.color, dark.colors.accent);
    expect(progress.backgroundColor, dark.colors.accentSoft);
    expect(tester.widget<Text>(find.text('剩余')).style!.color,
        dark.colors.textSecondary);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expired and zero-duration sessions have no progress',
      (tester) async {
    final now = DateTime(2026);
    DateTime clock() => now;
    await tester.pumpWidget(MaterialApp(
      theme: ShuYoThemes.byId('blue_light').themeData(),
      home: Scaffold(
        body: WeComScanCountdown(
          duration: Duration.zero,
          clock: clock,
        ),
      ),
    ));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0);
    expect(find.text('0s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(MaterialApp(
      theme: ShuYoThemes.byId('blue_light').themeData(),
      home: Scaffold(
        body: WeComScanCountdown(
          duration: const Duration(seconds: 10),
          startedAt: now.subtract(const Duration(seconds: 20)),
          clock: clock,
        ),
      ),
    ));
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0);
    await tester.pumpWidget(const SizedBox());
  });
}
