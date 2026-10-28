import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/campus_card.dart';
import 'package:shuyo/data/services/campus_card_service.dart'
    show CampusCardAuthRequiredException, CampusCardException;
import 'package:shuyo/features/home/campus_card_spending_chart.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';

final _end = DateTime(2026, 1, 3);

CampusCardBill _bill(String date, double amount) => CampusCardBill(
      name: '测试消费',
      payTime: date,
      amount: amount,
    );

List<CampusCardBill> _bills() => [
      _bill('2025-12-28 00:00:00', 1.25),
      _bill('2025-12-28 00:00:00', 1.25),
      _bill('2026-01-03 23:59:59', 4.2),
      _bill('2025-12-10 12:00:00', 12),
    ];

void main() {
  group('daily spending aggregation', () {
    test('uses inclusive calendar dates, fills gaps and keeps repeated charges',
        () {
      final result = aggregateCampusCardDailySpending([
        ..._bills(),
        _bill('2025-12-28 12:00:00', -99),
        _bill('2025-12-29', 0),
        _bill('2025-12-27 23:59:59', 40),
        _bill('2026-01-04 00:00:00', 50),
        _bill('2025-12-32 12:00:00', 60),
        _bill('2026-01-03 24:00:00', 70),
        _bill('2026-01-03 12:60:00', 80),
        _bill('not-a-date', 90),
        _bill('2026-01-03', double.nan),
        _bill('2026-01-03', double.infinity),
      ], endDate: DateTime(2026, 1, 3, 8), days: 7);

      expect(result, hasLength(7));
      expect(result.first.date, DateTime(2025, 12, 28));
      expect(result.last.date, _end);
      expect(result.map((day) => day.amount), [2.5, 0, 0, 0, 0, 0, 4.2]);
      expect(result.map((day) => day.creditAmount), [99, 0, 0, 0, 0, 0, 0]);
      expect(() => result.clear(), throwsUnsupportedError);
    });

    test('30 days crosses leap day and rejects normalized impossible dates',
        () {
      final result = aggregateCampusCardDailySpending([
        _bill('2024-02-01', 0.1),
        _bill('2024-02-01', 0.2),
        _bill('2024-02-29  12:00:00', 2),
        _bill('2024-03-01T23:59:59', 3),
        _bill('2024-02-30 12:00:00', 100),
        _bill('2024-01-31', 100),
      ], endDate: DateTime.utc(2024, 3, 1, 1), days: 30);
      expect(result.first.date, DateTime(2024, 2, 1));
      expect(result[28].date, DateTime(2024, 2, 29));
      expect(result[28].amount, 2);
      expect(result.last.amount, 3);
      expect(result.first.amount, closeTo(0.3, 0.000001));
    });

    test('spending and incoming funds never cancel and duplicates remain', () {
      final result = aggregateCampusCardDailySpending([
        _bill('2026-01-03', 10),
        _bill('2026-01-03', 4),
        _bill('2026-01-03', -50),
        _bill('2026-01-03', -3),
        _bill('2026-01-03', -3),
        _bill('2026-01-03', -0.0),
        _bill('2026-01-04', -999),
        _bill('2025-12-32', -999),
        _bill('2026-01-03', double.negativeInfinity),
      ], endDate: _end, days: 7);
      expect(result.last.amount, 14);
      expect(result.last.creditAmount, 56);
      expect(result.take(6).map((day) => day.creditAmount), everyElement(0));
    });

    test('empty input is zero-filled and invalid day counts are rejected', () {
      final result =
          aggregateCampusCardDailySpending(const [], endDate: _end, days: 7);
      expect(result.map((day) => day.amount), everyElement(0));
      expect(result.map((day) => day.creditAmount), everyElement(0));
      expect(
          () => aggregateCampusCardDailySpending(const [],
              endDate: _end, days: 0),
          throwsArgumentError);
    });
  });

  testWidgets('defaults to seven days and switches locally to thirty days',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester, bills: _bills());
      expect(find.text('消费趋势'), findsOneWidget);
      expect(find.byKey(const ValueKey('campus-card-chart-selected-date')),
          findsNothing);
      expect(find.text('消费'), findsOneWidget);
      expect(find.text('充值'), findsOneWidget);
      expect(find.semantics.byLabel(RegExp(r'^202[56]年.*，消费 ¥ ')),
          findsExactly(7));
      expect(find.semantics.byLabel('2025年12月10日，消费 ¥ 12.00，充值入账 ¥ 0.00'),
          findsNothing);

      await tester
          .tap(find.byKey(const ValueKey('campus-card-chart-range-30')));
      await tester.pump();
      expect(find.semantics.byLabel(RegExp(r'^202[56]年.*，消费 ¥ ')),
          findsExactly(30));
      final olderDay =
          find.semantics.byLabel('2025年12月10日，消费 ¥ 12.00，充值入账 ¥ 0.00');
      final node = olderDay.evaluate().single;
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(find.text('2025-12-10'), findsOneWidget);
      expect(_selectedValue(tester, 'amount'), '¥ 12.00');

      await tester.tap(find.byKey(const ValueKey('campus-card-chart-range-7')));
      await tester.pump();
      expect(find.byKey(const ValueKey('campus-card-chart-selected-date')),
          findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('tap and horizontal drag select dates at both plot edges',
      (tester) async {
    await _pump(tester, bills: _bills());
    final plot = find.byKey(const ValueKey('campus-card-chart-plot'));
    final bounds = tester.getRect(plot);
    final chart = find.byKey(const ValueKey('campus-card-spending-chart'));
    final chartBounds = tester.getRect(chart);
    await tester.tapAt(Offset(bounds.left + 1, bounds.center.dy));
    await tester.pump();
    expect(tester.getRect(plot), bounds);
    expect(tester.getRect(chart), chartBounds);
    expect(
        tester
            .getBottomRight(
                find.byKey(const ValueKey('campus-card-chart-selection')))
            .dy,
        lessThanOrEqualTo(bounds.top));
    expect(find.text('2025-12-28'), findsOneWidget);
    expect(_selectedValue(tester, 'amount'), '¥ 2.50');
    final date = find.byKey(const ValueKey('campus-card-chart-selected-date'));
    final spending =
        find.byKey(const ValueKey('campus-card-chart-selected-amount-row'));
    final credit = find
        .byKey(const ValueKey('campus-card-chart-selected-credit-amount-row'));
    expect(tester.getTopRight(date).dx,
        lessThanOrEqualTo(tester.getTopLeft(spending).dx));
    expect(
        tester.getCenter(date).dy,
        closeTo(
            (tester.getTopLeft(spending).dy + tester.getBottomLeft(credit).dy) /
                2,
            0.01));
    final dateCenter = tester.getCenter(date).dx;
    expect(tester.getTopLeft(credit).dy,
        greaterThan(tester.getBottomLeft(spending).dy));
    expect(find.descendant(of: spending, matching: find.text('消费')),
        findsOneWidget);
    expect(
        find.descendant(of: credit, matching: find.text('充值')), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsWidgets);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsWidgets);
    expect(
        find.byKey(const ValueKey('campus-card-chart-currency')), findsNothing);

    final drag =
        await tester.startGesture(Offset(bounds.left + 1, bounds.center.dy));
    await drag.moveTo(Offset(bounds.right - 1, bounds.center.dy));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(find.text('2026-01-03'), findsOneWidget);
    expect(_selectedValue(tester, 'amount'), '¥ 4.20');
    expect(tester.getCenter(date).dx, closeTo(dateCenter, 0.01));
    expect(tester.getRect(plot), bounds);
    expect(tester.getRect(chart), chartBounds);
  });

  testWidgets('screen readers can select a zero-spending day', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester, bills: _bills());
      final label = find.semantics.byLabel('2025年12月29日，消费 ¥ 0.00，充值入账 ¥ 0.00');
      final node = label.evaluate().single;
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(find.text('2025-12-29'), findsOneWidget);
      expect(_selectedValue(tester, 'amount'), '¥ 0.00');
      expect(
          label
              .evaluate()
              .single
              .getSemanticsData()
              .flagsCollection
              .isSelected
              .toBoolOrNull(),
          isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('initial loading reserves chart space and errors hide amounts',
      (tester) async {
    var retries = 0;
    await _pump(tester, bills: null, loading: true);
    expect(find.byKey(const ValueKey('campus-card-chart-loading')),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('campus-card-chart-plot')), findsNothing);
    expect(find.byKey(const ValueKey('campus-card-chart-selected-amount')),
        findsNothing);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('campus-card-chart-loading')))
            .height,
        greaterThanOrEqualTo(184));
    await tester.tap(find.byKey(const ValueKey('campus-card-chart-range-30')));
    await tester.pump();
    expect(find.text('¥ 4.20'), findsNothing);

    await _pump(tester,
        bills: _bills(),
        error: StateError('private diagnostic'),
        onRetry: () => retries++);
    expect(find.text('消费趋势暂时无法加载'), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
    expect(find.byKey(const ValueKey('campus-card-chart-plot')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('campus-card-chart-retry')));
    expect(retries, 1);

    await _pump(tester, bills: _bills());
    expect(
        find.byKey(const ValueKey('campus-card-chart-plot')), findsOneWidget);
    expect(find.text('消费'), findsOneWidget);
  });

  testWidgets('refresh retains completed chart, selection and painter data',
      (tester) async {
    final bills = _bills();
    await _pump(tester, bills: bills);
    await tester.tap(find.byKey(const ValueKey('campus-card-chart-range-30')));
    await tester.pump();
    final plot = find.byKey(const ValueKey('campus-card-chart-plot'));
    final bounds = tester.getRect(plot);
    await tester.tapAt(Offset(bounds.left + 1, bounds.center.dy));
    await tester.pump();
    final oldPainter = tester.widget<CustomPaint>(plot).painter!;
    final selectedDate = tester
        .widget<Text>(
            find.byKey(const ValueKey('campus-card-chart-selected-date')))
        .data;
    final chartSize = tester
        .getSize(find.byKey(const ValueKey('campus-card-spending-chart')));

    await _pump(tester, bills: bills, loading: true);
    final newPainter = tester.widget<CustomPaint>(plot).painter!;
    expect(newPainter.shouldRepaint(oldPainter), isFalse);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('campus-card-spending-chart'))),
        chartSize);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('campus-card-chart-selected-date')))
            .data,
        selectedDate);
    expect(
        find.byKey(const ValueKey('campus-card-chart-loading')), findsNothing);
    expect(find.text('充值含其他入账（如退款）'), findsNothing);

    // An account reset removes the snapshot even if loading has stopped.
    await _pump(tester, bills: null);
    expect(plot, findsNothing);
    expect(find.text('暂无消费趋势'), findsOneWidget);
  });

  testWidgets('an empty completed snapshot remains visible during refresh',
      (tester) async {
    const bills = <CampusCardBill>[];
    await _pump(tester, bills: bills);
    expect(find.text('近7天暂无收支'), findsOneWidget);
    await _pump(tester, bills: bills, loading: true);
    expect(find.text('近7天暂无收支'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('campus-card-chart-plot')), findsOneWidget);
  });

  testWidgets('authentication and account mismatch expose the login action',
      (tester) async {
    var logins = 0;
    for (final error in [
      const CampusCardAuthRequiredException(),
      const CampusCardException('accountMismatch', 'private identity'),
    ]) {
      await _pump(tester,
          bills: _bills(), error: error, onRetry: () => logins++);
      expect(find.text('登录校园账户'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(find.byKey(const ValueKey('campus-card-chart-selected-amount')),
          findsNothing);
      await tester.tap(find.byKey(const ValueKey('campus-card-chart-retry')));
      await tester.pump();
    }
    expect(logins, 2);
  });

  testWidgets('empty and incoming-only data preserve both series',
      (tester) async {
    await _pump(tester, bills: const []);
    expect(find.text('近7天暂无收支'), findsOneWidget);
    await _selectLastDay(tester);
    expect(_selectedValue(tester, 'amount'), '¥ 0.00');
    await _pump(tester, bills: [_bill('2026-01-03', -120)]);
    await tester.tap(find.byKey(const ValueKey('campus-card-chart-range-30')));
    await tester.pump();
    await _selectLastDay(tester);
    expect(find.byKey(const ValueKey('campus-card-chart-empty')), findsNothing);
    expect(_selectedValue(tester, 'amount'), '¥ 0.00');
    expect(_selectedValue(tester, 'credit-amount'), '¥ 120.00');
    expect(_recordedBars(tester), isEmpty);
    expect(_recordedOutlines(tester), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px with large text and a single spending day remains usable',
      (tester) async {
    await _pump(tester, bills: [_bill('2026-01-03', 123.45)], textScale: 2);
    final plot = find.byKey(const ValueKey('campus-card-chart-plot'));
    final plotBounds = tester.getRect(plot);
    final chart = find.byKey(const ValueKey('campus-card-spending-chart'));
    final chartBounds = tester.getRect(chart);
    await _selectLastDay(tester);
    expect(tester.getRect(plot), plotBounds);
    expect(tester.getRect(chart), chartBounds);
    expect(_selectedValue(tester, 'amount'), '¥ 123.45');
    expect(
        tester
            .getBottomRight(
                find.byKey(const ValueKey('campus-card-chart-selection')))
            .dy,
        lessThanOrEqualTo(tester
            .getTopLeft(find.byKey(const ValueKey('campus-card-chart-plot')))
            .dy));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('campus-card-chart-plot')))
            .height,
        150);
    await tester.ensureVisible(
        find.byKey(const ValueKey('campus-card-chart-range-30')));
    await tester.tap(find.byKey(const ValueKey('campus-card-chart-range-30')));
    await tester.pump();
    await _selectLastDay(tester);
    expect(_selectedValue(tester, 'amount'), '¥ 123.45');
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart starts with legend and without persistent metrics',
      (tester) async {
    await _pump(tester, bills: [
      _bill('2026-01-03', 21),
      _bill('2026-01-03', -50),
    ]);
    expect(find.text('消费'), findsOneWidget);
    expect(find.text('充值'), findsOneWidget);
    final spending = find.byKey(const ValueKey('campus-card-chart-legend-消费'));
    final credit = find.byKey(const ValueKey('campus-card-chart-legend-充值'));
    expect(tester.getTopLeft(credit).dy,
        greaterThan(tester.getBottomLeft(spending).dy));
    expect(tester.getTopLeft(credit).dx, tester.getTopLeft(spending).dx);
    expect(
        find.byKey(const ValueKey('campus-card-chart-currency')), findsNothing);
    expect(find.text('消费合计'), findsNothing);
    expect(find.text('日均消费'), findsNothing);
    expect(find.byKey(const ValueKey('campus-card-chart-selected-date')),
        findsNothing);
    expect(find.textContaining('充值含其他'), findsNothing);
  });

  testWidgets(
      'daily grouped columns use theme tokens and a shared zero baseline',
      (tester) async {
    await _pump(tester, bills: [
      _bill('2026-01-03', 10),
      _bill('2026-01-03', -20),
    ]);
    final bars = _recordedBars(tester);
    final outlines = _recordedOutlines(tester);
    final colors = ShuYoThemes.byId(ShuYoThemes.defaultId).colors;
    expect(bars, hasLength(1));
    expect(bars[0].color.toARGB32(), colors.accent.toARGB32());
    expect(outlines, hasLength(1));
    expect(outlines.single.color.toARGB32(), colors.accent.toARGB32());
    final spendingLegend = tester.widget<Container>(
        find.byKey(const ValueKey('campus-card-chart-legend-消费')));
    final creditLegend = tester.widget<Container>(
        find.byKey(const ValueKey('campus-card-chart-legend-充值')));
    expect((spendingLegend.decoration! as BoxDecoration).border, isNull);
    expect((creditLegend.decoration! as BoxDecoration).border, isNotNull);
    expect((creditLegend.decoration! as BoxDecoration).color, isNull);
    expect(
        ((creditLegend.decoration! as BoxDecoration).border! as Border)
            .top
            .color
            .toARGB32(),
        colors.accent.toARGB32());
    await _selectLastDay(tester);
    expect(
        tester
            .widget<Text>(find.byKey(
                const ValueKey('campus-card-chart-selected-credit-amount')))
            .style!
            .color!
            .toARGB32(),
        colors.accent.toARGB32());
    final creditShape =
        outlines.single.shape.inflate(outlines.single.strokeWidth / 2);
    expect(bars[0].shape.bottom, closeTo(creditShape.bottom, 0.001));
    expect(bars[0].shape.height / creditShape.height, closeTo(0.5, 0.001));
    expect(bars[0].shape.right, lessThan(creditShape.left));
    final plot = find.byKey(const ValueKey('campus-card-chart-plot'));
    expect(plot, paintsExactlyCountTimes(#drawPath, 0));
    expect(plot, paintsExactlyCountTimes(#drawCircle, 0));
    await _pump(tester, themeId: 'ink_teal', bills: [
      _bill('2026-01-03', 10),
      _bill('2026-01-03', -20),
    ]);
    await tester.pumpAndSettle();
    final darkBars = _recordedBars(tester);
    final darkColors = ShuYoThemes.byId('ink_teal').colors;
    expect(darkBars[0].color.toARGB32(), darkColors.accent.toARGB32());
    final darkOutlines = _recordedOutlines(tester);
    expect(darkBars, hasLength(1));
    expect(darkOutlines.single.color.toARGB32(), darkColors.accent.toARGB32());
    expect(darkOutlines.single.color.toARGB32(),
        isNot(outlines.single.color.toARGB32()));
    await _pump(tester, themeId: ShuYoThemes.systemDarkId, bills: [
      _bill('2026-01-03', 10),
      _bill('2026-01-03', -20),
    ]);
    await tester.pumpAndSettle();
    final similarThemeBars = _recordedBars(tester);
    final similarThemeOutlines = _recordedOutlines(tester);
    final similarColors = ShuYoThemes.byId(ShuYoThemes.systemDarkId).colors;
    expect(
        similarThemeBars[0].color.toARGB32(), similarColors.accent.toARGB32());
    expect(similarThemeBars, hasLength(1));
    expect(similarThemeOutlines.single.color.toARGB32(),
        similarColors.accent.toARGB32());
  });

  testWidgets(
      'thirty paired columns stay separate on narrow screens and select by day',
      (tester) async {
    await _pump(tester, textScale: 2, bills: [
      for (var index = 0; index < 30; index++) ...[
        _bill(DateTime(2026, 1, 3 - 29 + index).toIso8601String(), index + 1.0),
        _bill(DateTime(2026, 1, 3 - 29 + index).toIso8601String(),
            -(index + 1.0) * 2),
      ],
    ]);
    await tester.tap(find.byKey(const ValueKey('campus-card-chart-range-30')));
    await tester.pump();
    final plot = find.byKey(const ValueKey('campus-card-chart-plot'));
    await tester.ensureVisible(plot);
    final bars = _recordedBars(tester);
    final outlines = _recordedOutlines(tester);
    expect(bars, hasLength(30));
    expect(outlines, hasLength(30));
    for (var index = 0; index < outlines.length; index++) {
      final outline = outlines[index];
      expect(outline.strokeWidth, greaterThan(0));
      expect(outline.shape.width, greaterThan(outline.strokeWidth));
      expect(outline.shape.height, greaterThan(outline.strokeWidth));
      expect(bars[index].shape.right, lessThan(outline.shape.left));
    }
    final width = tester.getSize(plot).width;
    for (var index = 0; index < bars.length; index++) {
      final rect = bars[index].shape;
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width));
      if (index > 0) expect(bars[index - 1].shape.right, lessThan(rect.left));
    }
    final localCenter = bars[14].shape.outerRect.center;
    await tester.tapAt(tester.getTopLeft(plot) + localCenter);
    await tester.pump();
    expect(find.text('2025-12-19'), findsOneWidget);
    expect(_selectedValue(tester, 'amount'), '¥ 15.00');
    expect(_selectedValue(tester, 'credit-amount'), '¥ 30.00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('latest selection follows a new end date', (tester) async {
    await _pump(tester, bills: _bills());
    await _selectLastDay(tester);
    await _pump(tester,
        bills: [_bill('2026-01-04', 5)], endDate: DateTime(2026, 1, 4));
    expect(find.text('2026-01-04'), findsOneWidget);
    expect(_selectedValue(tester, 'amount'), '¥ 5.00');
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required List<CampusCardBill>? bills,
  DateTime? endDate,
  bool loading = false,
  Object? error,
  VoidCallback? onRetry,
  double textScale = 1,
  String? themeId,
}) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: ShuYoThemes.byId(themeId ?? ShuYoThemes.defaultId).themeData(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale), disableAnimations: true),
      child: child!,
    ),
    home: Scaffold(
        body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: CampusCardSpendingChart(
        bills: bills,
        endDate: endDate ?? _end,
        loading: loading,
        error: error,
        onRetry: onRetry,
      ),
    )),
  ));
  await tester.pump();
}

String? _selectedValue(WidgetTester tester, String suffix) => tester
    .widget<Text>(find.byKey(ValueKey('campus-card-chart-selected-$suffix')))
    .data;

Future<void> _selectLastDay(WidgetTester tester) async {
  final bounds =
      tester.getRect(find.byKey(const ValueKey('campus-card-chart-plot')));
  await tester.tapAt(Offset(bounds.right - 1, bounds.center.dy));
  await tester.pump();
}

List<({RRect shape, Color color})> _recordedBars(WidgetTester tester) {
  return _recordedShapes(tester)
      .where((shape) => shape.style == PaintingStyle.fill)
      .map((shape) => (shape: shape.shape, color: shape.color))
      .toList();
}

List<({RRect shape, Color color, double strokeWidth})> _recordedOutlines(
    WidgetTester tester) {
  return _recordedShapes(tester)
      .where((shape) => shape.style == PaintingStyle.stroke)
      .map((shape) => (
            shape: shape.shape,
            color: shape.color,
            strokeWidth: shape.strokeWidth,
          ))
      .toList();
}

List<({RRect shape, Color color, PaintingStyle style, double strokeWidth})>
    _recordedShapes(WidgetTester tester) {
  final plot = find.byKey(const ValueKey('campus-card-chart-plot'));
  final painter = tester.widget<CustomPaint>(plot).painter!;
  final canvas = TestRecordingCanvas();
  painter.paint(canvas, tester.getSize(plot));
  return canvas.invocations
      .where((record) => record.invocation.memberName == #drawRRect)
      .map((record) => (
            shape: record.invocation.positionalArguments[0] as RRect,
            color: (record.invocation.positionalArguments[1] as Paint).color,
            style: (record.invocation.positionalArguments[1] as Paint).style,
            strokeWidth:
                (record.invocation.positionalArguments[1] as Paint).strokeWidth,
          ))
      .toList();
}
