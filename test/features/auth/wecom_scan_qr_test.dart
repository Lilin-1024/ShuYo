import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shuyo/core/wecom_constants.dart';
import 'package:shuyo/data/services/wecom_auth_service.dart';
import 'package:shuyo/features/auth/wecom_scan_page.dart';
import 'package:shuyo/features/auth/widgets/wecom_login_qr.dart';
import 'package:shuyo/features/auth/widgets/wecom_scan_countdown.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';
import 'package:shuyo/shared/widgets/wecom_icon.dart';

const _session = WeComQrSession(
  key: 'test-session',
  qrImageUrl: 'https://example.invalid/image',
  confirmUrl: 'https://example.invalid/confirm?k=test-session',
  wxWorkSchemeUrl: 'wxwork://test',
);

class _WaitingWeComAuthService extends WeComAuthService {
  final result = Completer<WeComScanResult>();
  void Function(WeComScanStatus status)? statusChanged;

  @override
  Future<WeComScanResult> waitForScan(
    String key, {
    Duration timeout = WeComAuthService.scanTimeout,
    void Function(WeComScanStatus status)? onStatusChanged,
    bool Function()? isCancelled,
  }) {
    statusChanged = onStatusChanged;
    return result.future;
  }
}

void main() {
  testWidgets('generates the confirmation QR locally without a network image',
      (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    await _pumpPage(tester, service, ShuYoThemes.byId(ShuYoThemes.defaultId));

    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    await _expectQrContent(tester, qr, _session.confirmUrl);
    expect(find.byType(Image), findsNothing);
    expect(qr.eyeStyle.eyeShape, QrEyeShape.square);
    final qrStack = tester.widget<Stack>(find
        .descendant(
          of: find.byType(WeComLoginQr),
          matching: find.byType(Stack),
        )
        .first);
    expect(qrStack.children, hasLength(2));
    expect(qrStack.children.first, isA<QrImageView>());
    expect(qrStack.children.last, isA<IgnorePointer>());
    expect(qr.dataModuleStyle.dataModuleShape, QrDataModuleShape.circle);
    expect(qr.errorCorrectionLevel, QrErrorCorrectLevel.H);
    expect(find.byType(WeComIcon), findsOneWidget);
    expect(tester.getSize(find.byType(WeComIcon)), const Size.square(30));
    expect(tester.getCenter(find.byType(WeComIcon)),
        tester.getCenter(find.byType(QrImageView)));
    final countdown = find.byType(WeComScanCountdown);
    expect(countdown, findsOneWidget);
    expect(tester.widget<WeComScanCountdown>(countdown).duration,
        WeComAuthService.scanTimeout);
    expect(tester.getTopLeft(countdown).dy,
        greaterThan(tester.getBottomLeft(find.byType(WeComLoginQr)).dy));
    expect(tester.getBottomLeft(countdown).dy,
        lessThan(tester.getTopLeft(find.text('等待扫码...')).dy));
    expect(tester.takeException(), isNull);

    await _closePage(tester, service);
  });

  testWidgets('QR colors update when the app theme changes', (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    await _pumpPage(tester, service, ShuYoThemes.byId('blue_light'));
    final light = tester.widget<QrImageView>(find.byType(QrImageView));
    _expectFrame(tester, ShuYoThemes.byId('blue_light'));

    await _pumpPage(tester, service, ShuYoThemes.byId('ink_teal'));
    final dark = tester.widget<QrImageView>(find.byType(QrImageView));
    _expectFrame(tester, ShuYoThemes.byId('ink_teal'));

    await _expectQrContent(tester, dark, _session.confirmUrl);
    expect(dark.dataModuleStyle.color, isNot(light.dataModuleStyle.color));
    expect(tester.takeException(), isNull);
    await _closePage(tester, service);
  });

  testWidgets('all themes keep the QR high contrast on the page',
      (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    for (final theme in ShuYoThemes.all) {
      await _pumpPage(tester, service, theme);
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      final foreground = qr.dataModuleStyle.color!;
      final background = qr.backgroundColor;
      final contrast = (background.computeLuminance() + 0.05) /
          (foreground.computeLuminance() + 0.05);

      expect(qr.eyeStyle.eyeShape, QrEyeShape.square, reason: theme.id);
      expect(qr.dataModuleStyle.dataModuleShape, QrDataModuleShape.circle,
          reason: theme.id);
      expect(qr.eyeStyle.color, foreground, reason: theme.id);
      final iconTheme = tester.widget<IconTheme>(find
          .ancestor(
            of: find.byType(WeComIcon),
            matching: find.byType(IconTheme),
          )
          .first);
      expect(iconTheme.data.color, foreground, reason: theme.id);
      expect(foreground.a, 1, reason: theme.id);
      expect(background.a, 1, reason: theme.id);
      expect(background.computeLuminance(), greaterThan(0.5), reason: theme.id);
      expect(foreground.computeLuminance(),
          lessThan(background.computeLuminance()),
          reason: theme.id);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: theme.id);
      _expectFrame(tester, theme);
      expect(tester.takeException(), isNull, reason: theme.id);
    }
    await _closePage(tester, service);
  });

  testWidgets('a transparent scaffold retains a solid QR background',
      (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    final lightTheme = ShuYoThemes.byId(ShuYoThemes.defaultId);
    final imageTheme = ShuYoThemeSpec(
      id: ShuYoThemes.customBackgroundId,
      name: 'Test image background',
      colors: lightTheme.colors,
    );
    await _pumpPage(tester, service, imageTheme);
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.backgroundColor.a, 1);
    _expectFrame(tester, imageTheme);
    await _closePage(tester, service);
  });

  testWidgets('open button fills the page width up to 440 pixels',
      (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpPage(tester, service, ShuYoThemes.byId(ShuYoThemes.defaultId));

    expect(tester.getSize(_openButton()), const Size(440, 50));
    expect(tester.getSize(find.byType(WeComScanCountdown)).width, 440);
    expect(tester.takeException(), isNull);
    await _closePage(tester, service);
  });

  testWidgets('QR page fits a narrow screen', (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpPage(tester, service, ShuYoThemes.byId(ShuYoThemes.defaultId));

    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
    final openButton = find.text('打开企业微信登录');
    await tester.ensureVisible(openButton);
    await _pumpPageAnimations(tester);
    expect(openButton.hitTestable(), findsOneWidget);
    expect(tester.getSize(_openButton()), const Size(272, 50));
    expect(tester.getSize(find.byType(WeComScanCountdown)).width, 272);
    final policy = _policyText();
    await tester.ensureVisible(policy);
    await _pumpPageAnimations(tester);
    expect(policy.hitTestable(), findsOneWidget);
    await _closePage(tester, service);
  });

  testWidgets('narrow screen with large text keeps scan controls accessible',
      (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ShuYoThemes.byId(ShuYoThemes.defaultId).themeData(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: WeComScanPage(
        session: _session,
        authService: service,
        target: WeComOAuthTarget.academic,
      ),
    ));
    await _pumpPageAnimations(tester);
    service.statusChanged!(WeComScanStatus.confirmedPending);
    await tester.pump();

    for (final element in [
      find.byType(WeComScanCountdown),
      find.text('已扫码，请确认登录'),
      find.text('打开企业微信登录'),
    ]) {
      await tester.ensureVisible(element);
      await _pumpPageAnimations(tester);
      expect(element.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await _closePage(tester, service);
  });

  testWidgets('privacy notice opens the official link in a browser',
      (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    var launchSucceeds = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return launchSucceeds;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    await _pumpPage(tester, service, ShuYoThemes.byId(ShuYoThemes.defaultId));
    expect(find.text('扫码确认后请返回本应用'), findsNothing);
    final policy = _policyText();
    expect(policy, findsOneWidget);
    final richText = tester.widget<RichText>(policy);
    expect(richText.text.toPlainText(), contains('打开企业微信后，你将使用企业微信完成身份验证。'));
    expect(richText.text.toPlainText(), contains('有关个人信息的处理，请查阅'));

    await tester.ensureVisible(policy);
    await _pumpPageAnimations(tester);
    await _tapPolicyLink(tester, policy);
    await _pumpPageAnimations(tester);
    final call = calls.singleWhere((call) => call.method == 'launch');
    expect(call.arguments['url'], 'https://work.weixin.qq.com/nl/privacy');
    expect(call.arguments['useSafariVC'], isFalse);
    expect(call.arguments['useWebView'], isFalse);

    launchSucceeds = false;
    await _tapPolicyLink(tester, policy);
    await _pumpPageAnimations(tester);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('无法打开企业微信隐私保护指引'),
      ),
      findsOneWidget,
    );
    await _closePage(tester, service);
  });

  testWidgets('polling failure returns and shows an error SnackBar',
      (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => WeComScanPage(
                  session: _session,
                  authService: service,
                  target: WeComOAuthTarget.academic,
                ),
              ),
            ),
            child: const Text('进入扫码页'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('进入扫码页'));
    await _pumpPageAnimations(tester);
    service.result.completeError(StateError('test poll error'));
    await tester.pumpAndSettle();
    expect(find.byType(WeComScanPage), findsNothing);
    expect(find.text('进入扫码页'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('无法连接企业微信服务，请稍后再试'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('scan status shows the requested text and icons', (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    await _pumpPage(tester, service, ShuYoThemes.byId(ShuYoThemes.defaultId));

    expect(find.text('等待扫码...'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner_outlined), findsOneWidget);

    service.statusChanged!(WeComScanStatus.confirmedPending);
    await tester.pump();
    expect(find.text('等待扫码...'), findsNothing);
    expect(find.text('已扫码，请确认登录'), findsOneWidget);
    expect(find.byIcon(Icons.smartphone_outlined), findsOneWidget);

    service.statusChanged!(WeComScanStatus.succeeded);
    await tester.pump();
    expect(find.text('已扫码，请确认登录'), findsNothing);
    expect(find.text('企业微信登录成功'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _closePage(tester, service);
  });

  testWidgets('expiration does not display a status and returns with a notice',
      (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => WeComScanPage(
                  session: _session,
                  authService: service,
                  target: WeComOAuthTarget.academic,
                ),
              ),
            ),
            child: const Text('进入扫码页'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('进入扫码页'));
    await _pumpPageAnimations(tester);

    service.statusChanged!(WeComScanStatus.expired);
    await tester.pump();
    expect(find.text('二维码已过期'), findsNothing);
    service.result.complete(const WeComScanResult.expired());
    await tester.pumpAndSettle();
    expect(find.byType(WeComScanPage), findsNothing);
    expect(find.text('进入扫码页'), findsOneWidget);
    expect(find.text('二维码已过期或已取消，请重新尝试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _openButton() => find.ancestor(
      of: find.text('打开企业微信登录'),
      matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
    );

Finder _policyText() => find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('《企业微信隐私保护指引》'),
    );

Future<void> _tapPolicyLink(WidgetTester tester, Finder policy) async {
  const label = '《企业微信隐私保护指引》';
  final paragraph = tester.renderObject<RenderParagraph>(policy);
  final text = paragraph.text.toPlainText();
  final start = text.indexOf(label);
  expect(start, greaterThanOrEqualTo(0));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + label.length),
  );
  expect(boxes, isNotEmpty);
  await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
}

void _expectFrame(WidgetTester tester, ShuYoThemeSpec theme) {
  final qr = find.byType(QrImageView);
  final frame = find.ancestor(
    of: qr,
    matching: find.byWidgetPredicate((widget) {
      if (widget is! DecoratedBox || widget.decoration is! BoxDecoration) {
        return false;
      }
      final decoration = widget.decoration as BoxDecoration;
      return decoration.borderRadius == BorderRadius.circular(24);
    }),
  );
  expect(frame, findsOneWidget, reason: theme.id);
  final decoration =
      tester.widget<DecoratedBox>(frame).decoration as BoxDecoration;
  final qrBackground = tester.widget<QrImageView>(qr).backgroundColor;
  expect(decoration.color, qrBackground, reason: theme.id);
  expect(decoration.border, Border.all(color: theme.colors.accent),
      reason: theme.id);
  expect(tester.getSize(frame), const Size.square(244), reason: theme.id);
  expect(
    find.ancestor(
      of: qr,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ClipRRect &&
            widget.borderRadius == BorderRadius.circular(16),
      ),
    ),
    findsOneWidget,
    reason: theme.id,
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  _WaitingWeComAuthService service,
  ShuYoThemeSpec theme,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme.themeData(),
    home: WeComScanPage(
      session: _session,
      authService: service,
      target: WeComOAuthTarget.academic,
    ),
  ));
  await _pumpPageAnimations(tester);
}

Future<void> _pumpPageAnimations(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _closePage(
  WidgetTester tester,
  _WaitingWeComAuthService service,
) async {
  await tester.pumpWidget(const SizedBox());
  service.result.complete(const WeComScanResult.expired());
  await tester.pump();
}

Future<void> _expectQrContent(
  WidgetTester tester,
  QrImageView qr,
  String data,
) async {
  final paint = tester.widget<CustomPaint>(find.descendant(
    of: find.byType(QrImageView),
    matching: find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is QrPainter,
    ),
  ));
  final expected = QrPainter(
    data: data,
    version: qr.version,
    errorCorrectionLevel: qr.errorCorrectionLevel,
    gapless: qr.gapless,
    eyeStyle: qr.eyeStyle,
    dataModuleStyle: qr.dataModuleStyle,
  );
  await tester.runAsync(() async {
    final actualBytes = await (paint.painter! as QrPainter).toImageData(180);
    final expectedBytes = await expected.toImageData(180);
    expect(
        actualBytes!.buffer.asUint8List(), expectedBytes!.buffer.asUint8List());
  });
}
