import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/features/home/campus_card_date_range_sheet.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';

void main() {
  final today = DateUtils.dateOnly(DateTime.now());
  final start = DateTime(today.year, today.month - 1, 25);
  final end = DateTime(today.year, today.month, 1);

  Future<void> open(
    WidgetTester tester,
    ValueChanged<DateTimeRange?> onResult,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ShuYoThemes.byId(ShuYoThemes.defaultId).themeData(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showCampusCardDateRangeSheet(
                context,
                initialRange: DateTimeRange(start: start, end: end),
              ),
            ),
            child: const Text('选择日期'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('选择日期'));
    await tester.pumpAndSettle();
  }

  testWidgets('cross-month endpoints stay visible and querying returns edits',
      (tester) async {
    DateTimeRange? result;
    await open(tester, (value) => result = value);
    expect(find.text('开始'), findsOneWidget);
    await tester.tap(find.byTooltip('下个月'));
    await tester.pumpAndSettle();
    expect(find.text('结束'), findsOneWidget);

    await tester.tap(find.text('开始日期'));
    await tester.pumpAndSettle();
    final pickedStart = DateTime(start.year, start.month, 26);
    await tester.tap(find.byKey(ValueKey<DateTime>(pickedStart)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<DateTime>(end)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查询消费记录'));
    await tester.pumpAndSettle();
    expect(result, DateTimeRange(start: pickedStart, end: end));
  });

  testWidgets('cancel does not apply edited dates', (tester) async {
    DateTimeRange? result;
    var completed = false;
    await open(tester, (value) {
      result = value;
      completed = true;
    });
    await tester.tap(
        find.byKey(ValueKey<DateTime>(DateTime(start.year, start.month, 26))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消选择日期'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
  });
}
