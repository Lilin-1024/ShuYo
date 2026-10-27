import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/demo/demo_session.dart';
import 'package:shuyo/core/wecom_constants.dart';
import 'package:shuyo/data/services/wecom_auth_service.dart';
import 'package:shuyo/data/services/academic_native_auth_service.dart';
import 'package:shuyo/data/services/student_identity_service.dart';
import 'package:shuyo/features/auth/native_login_page.dart';
import 'package:shuyo/features/auth/login_help_page.dart';
import 'package:shuyo/features/auth/recovery_form_page.dart';
import 'package:shuyo/features/auth/wecom_scan_page.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';

class _WaitingWeComAuthService extends WeComAuthService {
  final result = Completer<WeComScanResult>();

  @override
  Future<WeComScanResult> waitForScan(
    String key, {
    Duration timeout = WeComAuthService.scanTimeout,
    void Function(WeComScanStatus status)? onStatusChanged,
    bool Function()? isCancelled,
  }) =>
      result.future;
}

/// 企微扫码登录 WebVPN 的产物：握手已在扫码页内完成，回调地址是落地页。
final _webVpnLandingResult = WeComRedeemResult(
  callbackUri: Uri.parse(WeComConstants.webVpnLanding),
  sessionCookies: const [],
);

void main() {
  const accountNotice = '你的上海大学账户用于登录并访问校园服务。'
      'ShuYo 会在设备上保存登录状态，以便你继续使用相关功能。';

  test('WebVPN WeCom login skips the callback exchange', () {
    expect(
      weComEstablishedWebVpnSession(
        destination: NativeLoginDestination.webVpn,
        weComRedeem: _webVpnLandingResult,
      ),
      isTrue,
    );
    // 教务系统的企微流程只拿到授权码，仍须跟随回调兑换会话。
    expect(
      weComEstablishedWebVpnSession(
        destination: NativeLoginDestination.academic,
        weComRedeem: _webVpnLandingResult,
      ),
      isFalse,
    );
    // 账密登录不经过扫码页，始终需要兑换回调。
    expect(
      weComEstablishedWebVpnSession(
        destination: NativeLoginDestination.webVpn,
        weComRedeem: null,
      ),
      isFalse,
    );
  });

  testWidgets('campus login shows the WeCom login entry button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativeLoginPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('使用企业微信登录'), findsOneWidget);
    expect(find.text('上海大学校园账户'), findsOneWidget);
    expect(find.text('使用企业微信扫码或跳转至企业微信登录'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('我已阅读并同意 ShuYo 的'), findsNothing);
    expect(find.text('登录问题？'), findsOneWidget);
    expect(
      find.text('你的上海大学账户用于登录并访问校园服务。'
          'ShuYo 会在设备上保存登录状态，以便你继续使用相关功能。'),
      findsOneWidget,
    );
  });

  testWidgets('account notice rests above the bottom safe area',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
    await tester.pumpAndSettle();

    final noticeBottom = tester.getBottomLeft(find.text(accountNotice)).dy;
    expect(844 - 34 - noticeBottom, inInclusiveRange(0, 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('account notice stays fixed when the keyboard appears',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).last);
    await tester.pumpAndSettle();

    final notice = find.text(accountNotice);
    expect(notice, findsOneWidget);
    final originalRect = tester.getRect(notice);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.view.padding = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);
    final keyboardRect = tester.getRect(notice);
    expect(keyboardRect.left, closeTo(originalRect.left, 0.01));
    expect(keyboardRect.top, closeTo(originalRect.top, 0.01));
    expect(keyboardRect.right, closeTo(originalRect.right, 0.01));
    expect(keyboardRect.bottom, closeTo(originalRect.bottom, 0.01));
    expect(keyboardRect.top, greaterThanOrEqualTo(844 - 300));
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = const FakeViewPadding();
    tester.view.padding = const FakeViewPadding(bottom: 34);
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);
    final restoredRect = tester.getRect(notice);
    expect(restoredRect.left, closeTo(originalRect.left, 0.01));
    expect(restoredRect.top, closeTo(originalRect.top, 0.01));
    expect(restoredRect.right, closeTo(originalRect.right, 0.01));
    expect(restoredRect.bottom, closeTo(originalRect.bottom, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('login validation snackbar stays above the keyboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).last);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final snackbar = find.byType(SnackBar);
    expect(snackbar, findsOneWidget);
    expect(find.descendant(of: snackbar, matching: find.text('请输入学/工号')),
        findsOneWidget);
    final error = find.descendant(
      of: snackbar,
      matching: find.text('请输入学/工号'),
    );
    expect(tester.getBottomLeft(error).dy, lessThanOrEqualTo(844 - 300));
  });

  testWidgets('short screen can scroll between credentials and login button',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    final scroll = find.byKey(const ValueKey('credentials'));
    await tester.drag(scroll, const Offset(0, -500));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(scroll);
    final buttonRect = tester.getRect(find.text('使用企业微信登录'));
    expect(buttonRect.top, greaterThanOrEqualTo(viewport.top));
    expect(buttonRect.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);

    await tester.drag(scroll, const Offset(0, 500));
    await tester.pumpAndSettle();
    final fieldRect = tester.getRect(find.byType(TextFormField).first);
    expect(fieldRect.top, greaterThanOrEqualTo(viewport.top));
    expect(fieldRect.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('WeCom login shows loading on its own button and recovers',
      (tester) async {
    final session = Completer<WeComQrSession>();
    var starts = 0;
    await tester.pumpWidget(MaterialApp(
      home: NativeLoginPage(startWeComSession: () {
        starts++;
        return session.future;
      }),
    ));
    await tester.pumpAndSettle();

    final continueButton = find.widgetWithText(FilledButton, '继续');
    final weComButton =
        find.byWidgetPredicate((widget) => widget is OutlinedButton);
    await tester.tap(find.text('使用企业微信登录'));
    await tester.pump();

    expect(find.text('继续'), findsOneWidget);
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(weComButton).onPressed, isNull);
    expect(
      find.descendant(
        of: weComButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: continueButton,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );

    await tester.tap(weComButton, warnIfMissed: false);
    await tester.tap(continueButton, warnIfMissed: false);
    await tester.pump();
    expect(starts, 1);

    session.completeError(const WeComAuthException('test', '登录失败'));
    await tester.pumpAndSettle();

    expect(find.text('登录失败'), findsOneWidget);
    expect(find.text('使用企业微信登录'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(weComButton).onPressed, isNotNull);
  });

  testWidgets('credential login loads its own button and restores after error',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final result = Completer<AcademicLoginResult>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: NativeLoginPage(loginForTesting: ({
        required username,
        required password,
      }) {
        calls++;
        return result.future;
      }),
    ));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'test-user');
    await tester.enterText(fields.last, 'test-password');
    final continueButton = find.byType(FilledButton);
    final weComButton = find.byType(OutlinedButton);
    await tester.tap(find.text('继续'));
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(weComButton).onPressed, isNull);
    expect(
        find.descendant(
            of: continueButton,
            matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    expect(
        find.descendant(
            of: weComButton, matching: find.byType(CircularProgressIndicator)),
        findsNothing);
    await tester.tap(continueButton, warnIfMissed: false);
    await tester.tap(weComButton, warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);
    result.completeError(const AcademicNativeAuthException('test', '登录失败'));
    await tester.pumpAndSettle();
    expect(find.text('登录失败'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    expect(tester.widget<OutlinedButton>(weComButton).onPressed, isNotNull);
  });

  testWidgets('credentials can log in without agreement selection',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));
    await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, DemoSession.username);
    await tester.enterText(fields.last, DemoSession.password);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(await DemoSession.isEnabled(), isTrue);
  });

  testWidgets('login help remains accessible alongside validation errors',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
    await tester.pumpAndSettle();
    final continueButton = find.widgetWithText(FilledButton, '继续');
    final buttonBefore = tester.getRect(continueButton);

    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
          of: find.byType(SnackBar), matching: find.text('请输入学/工号')),
      findsOneWidget,
    );
    expect(find.text('校园用户注册'), findsOneWidget);
    expect(find.text('登录问题？'), findsOneWidget);
    expect(tester.getRect(continueButton), buttonBefore);
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);

    await tester.enterText(find.byType(TextFormField).first, 'test-user');
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.text('请输入密码')),
      findsOneWidget,
    );
    expect(find.text('校园用户注册'), findsOneWidget);
    expect(find.text('登录问题？'), findsOneWidget);

    await tester.tap(find.text('登录问题？'));
    await tester.pumpAndSettle();
    expect(find.text('重置密码'), findsOneWidget);
    expect(find.text('修改手机号'), findsOneWidget);
  });

  testWidgets('registration opens the external page and reports failure',
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

    await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
    await tester.pumpAndSettle();

    final register = find.text('校园用户注册');
    final help = find.text('登录问题？');
    expect(register, findsOneWidget);
    expect(help, findsOneWidget);
    expect(
        tester.getTopLeft(register).dx, lessThan(tester.getTopLeft(help).dx));

    await tester.tap(register);
    await tester.pumpAndSettle();
    final call = calls.singleWhere((call) => call.method == 'launch');
    expect(
        call.arguments['url'], 'https://services.shu.edu.cn/oauth2/register');
    expect(call.arguments['useSafariVC'], isFalse);
    expect(call.arguments['useWebView'], isFalse);

    launchSucceeds = false;
    await tester.tap(register);
    await tester.pumpAndSettle();
    expect(find.text('无法打开注册页面'), findsOneWidget);
  });

  testWidgets('login links and validation fit on a narrow large-text screen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: const NativeLoginPage(),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('继续'));
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('请输入学/工号'), findsOneWidget);
    expect(find.text('校园用户注册'), findsOneWidget);
    expect(find.text('登录问题？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recovery options open local first steps and return to help',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginHelpPage()));
    for (final option in [
      (title: '重置密码', labels: ['学/工号', '姓名', '证件号码', '校园卡号']),
      (title: '修改手机号', labels: ['学/工号', '密码']),
    ]) {
      await tester.tap(find.text(option.title));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryFormPage), findsOneWidget);
      expect(find.text(option.title), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(option.title),
        ),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNWidgets(option.labels.length));
      for (final label in option.labels) {
        expect(find.text(label), findsOneWidget);
      }

      final fields = find.byType(TextFormField);
      for (var i = 0; i < option.labels.length; i++) {
        final input = find.descendant(
          of: fields.at(i),
          matching: find.byType(TextField),
        );
        final decoration = tester.widget<TextField>(input).decoration;
        expect(
          find.descendant(
            of: fields.at(i),
            matching: find.text(option.labels[i]),
          ),
          findsOneWidget,
        );
        expect(decoration?.border, isNot(InputBorder.none));
        expect(decoration?.enabledBorder, isNot(InputBorder.none));
        expect(decoration?.focusedBorder, isNot(InputBorder.none));

        await tester.tap(fields.at(i));
        await tester.pumpAndSettle();
        final labelRect = tester.getRect(find.text(option.labels[i]));
        final fieldRect = tester.getRect(fields.at(i));
        // A floating label straddles the outline rather than sitting wholly
        // inside the input's bounds.
        expect(labelRect.center.dy, greaterThanOrEqualTo(fieldRect.top));
        expect(labelRect.center.dy, lessThan(fieldRect.bottom));
        await tester.enterText(fields.at(i), 'test$i');
      }
      await tester.ensureVisible(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryFormPage), findsOneWidget);
      for (var i = 0; i < option.labels.length; i++) {
        expect(tester.widget<TextFormField>(fields.at(i)).controller?.text,
            'test$i');
      }
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(LoginHelpPage), findsOneWidget);
      expect(find.text('重置密码'), findsOneWidget);
      expect(find.text('修改手机号'), findsOneWidget);
    }
  });

  testWidgets('campus card number help works before and after focusing field',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RecoveryFormPage.resetPassword()),
    );

    final help = find.byTooltip('校园卡号说明');
    final cardField = find.ancestor(
      of: find.text('校园卡号'),
      matching: find.byType(TextFormField),
    );
    expect(help, findsOneWidget);
    expect(cardField, findsOneWidget);

    for (final focus in [false, true]) {
      if (focus) {
        await tester.tap(cardField);
        await tester.pumpAndSettle();
      }
      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(find.textContaining('卡号在校园卡人像面左下角'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.textContaining('卡号在校园卡人像面左下角'), findsNothing);
    }
  });

  testWidgets('login help has an app bar title and descriptive icon rows',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginHelpPage()));

    expect(find.text('登录问题'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('登录问题')),
      findsOneWidget,
    );
    expect(
      find.text('如果你遇到密码错误、无法完成两步验证等问题，可以尝试以下选项。'),
      findsOneWidget,
    );
    final colors = tester.element(find.byType(LoginHelpPage)).shuyoColors;
    for (final title in ['重置密码', '修改手机号']) {
      final tileFinder = find.ancestor(
        of: find.text(title),
        matching: find.byType(ListTile),
      );
      final tile = tester.widget<ListTile>(tileFinder);
      expect(tile.leading, isA<Icon>());
      expect((tile.leading! as Icon).color, colors.textSecondary);
      expect(tile.subtitle, isA<Text>());
      final subtitle = tile.subtitle! as Text;
      expect(subtitle.data, isNotEmpty);
      expect(subtitle.style?.color, colors.textSecondary);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('WeCom scan page keeps its heading out of the app bar',
      (tester) async {
    final service = _WaitingWeComAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
      home: WeComScanPage(
        session: const WeComQrSession(
          key: 'test',
          qrImageUrl: 'https://example.invalid/qr',
          confirmUrl: 'https://example.invalid/confirm',
          wxWorkSchemeUrl: 'wxwork://test',
        ),
        authService: service,
        target: WeComOAuthTarget.academic,
      ),
    ));
    expect(tester.widget<AppBar>(find.byType(AppBar)).title, isNull);
    expect(find.text('使用企业微信扫一扫'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    service.result.complete(const WeComScanResult.expired());
    await tester.pump();
  });

  testWidgets('change phone keeps account and password input types distinct',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RecoveryFormPage.changePhone()),
    );
    final fields = find.byType(TextFormField);
    await tester.tap(fields.first);
    await tester.pumpAndSettle();
    var configuration = tester.testTextInput.setClientArgs!;
    expect(configuration['inputType']['name'], 'TextInputType.text');
    expect(configuration['obscureText'], isFalse);
    expect(configuration['enableSuggestions'], isTrue);

    await tester.tap(fields.last);
    await tester.pumpAndSettle();
    configuration = tester.testTextInput.setClientArgs!;
    expect(configuration['obscureText'], isTrue);
    expect(configuration['enableSuggestions'], isFalse);
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.setClientArgs!['obscureText'], isFalse);
  });

  testWidgets('reset form remains usable on a short screen with keyboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      const MaterialApp(home: RecoveryFormPage.resetPassword()),
    );
    await tester.tap(find.byType(TextFormField).first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '001234');
    await tester.ensureVisible(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('下一步'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('credential fields keep their text input configurations',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.tap(fields.first);
    await tester.pumpAndSettle();
    var configuration = tester.testTextInput.setClientArgs!;
    expect(configuration['inputType']['name'], 'TextInputType.text');
    expect(configuration['obscureText'], isFalse);
    expect(configuration['enableSuggestions'], isTrue);
    expect(configuration['autocorrect'], isFalse);
    expect(configuration['autofill']['hints'], contains('username'));

    await tester.tap(fields.last);
    await tester.pumpAndSettle();
    configuration = tester.testTextInput.setClientArgs!;
    expect(configuration['inputType']['name'], 'TextInputType.visiblePassword');
    expect(configuration['obscureText'], isTrue);
    expect(configuration['enableSuggestions'], isFalse);
    expect(configuration['autocorrect'], isFalse);
    expect(configuration['autofill']['hints'], contains('password'));

    await tester.tap(find.byTooltip('显示密码'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.setClientArgs!['obscureText'], isFalse);
    expect(tester.testTextInput.setClientArgs!['enableSuggestions'], isFalse);
  });

  testWidgets('WebVPN login shows the WeCom login entry button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativeLoginPage.webVpn(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('使用企业微信登录'), findsOneWidget);
  });

  testWidgets('booking login names the feature being authorized',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NativeLoginPage.there()),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录图书馆预约'), findsOneWidget);
    expect(find.text('使用企业微信登录'), findsOneWidget);
  });

  testWidgets('data deletion uses a separate school login without QR reuse',
      (tester) async {
    final identity = StudentIdentityService();
    addTearDown(identity.dispose);
    await tester.pumpWidget(MaterialApp(
      home: NativeLoginPage.dataDeletion(studentIdentityService: identity),
    ));
    await tester.pumpAndSettle();
    expect(find.text('验证学校身份'), findsOneWidget);
    expect(find.text('重新登录上海大学账户，以确认本人操作'), findsOneWidget);
    expect(find.text('使用企业微信登录'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  for (final page in const [
    NativeLoginPage(),
    NativeLoginPage.webVpn(),
    NativeLoginPage.there(),
  ]) {
    testWidgets('${page.destination.name} shows errors without changing rows',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      final continueButton = find.widgetWithText(FilledButton, '继续');
      final buttonBefore = tester.getRect(continueButton);
      final dividerBefore = tester.getRect(find.byType(Divider));
      final studentIdLabelColor =
          tester.widget<Text>(find.text('学/工号')).style?.color;
      final passwordLabelColor =
          tester.widget<Text>(find.text('密码')).style?.color;

      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('请输入学/工号'),
        ),
        findsOneWidget,
      );
      expect(tester.getRect(find.byType(Divider)), dividerBefore);
      expect(tester.getRect(continueButton), buttonBefore);
      expect(tester.widget<Text>(find.text('学/工号')).style?.color,
          studentIdLabelColor);
      expect(tester.widget<Text>(find.text('密码')).style?.color,
          passwordLabelColor);

      await tester.enterText(fields.first, '123456');
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
            of: find.byType(SnackBar), matching: find.text('请输入密码')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
      expect(tester.getRect(find.byType(Divider)), dividerBefore);
      expect(tester.getRect(continueButton), buttonBefore);

      await tester.enterText(fields.last, 'password');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
      expect(tester.getRect(continueButton), buttonBefore);
    });
  }

  testWidgets(
      'credential card keeps labels and reveals password action on focus',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('上海大学校园账户'));
    final body = tester.getRect(find.byType(SingleChildScrollView));
    expect(title.top, lessThan(body.center.dy - 160));
    expect(find.text('学/工号'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);

    final passwordAction = find.ancestor(
      of: find.byTooltip('显示密码'),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(passwordAction).opacity, 0);

    await tester.tap(find.byType(TextFormField).last);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(passwordAction).opacity, 1);

    await tester.enterText(find.byType(TextFormField).first, '123456');
    await tester.pumpAndSettle();
    expect(find.text('学/工号'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(passwordAction).opacity, 0);

    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('上海大学校园账户'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });
}
