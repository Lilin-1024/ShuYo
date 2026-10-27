import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/academic_native_auth_service.dart';
import 'package:shuyo/features/auth/native_login_page.dart';
import 'package:shuyo/features/auth/widgets/two_step_verification.dart';
import 'package:shuyo/shared/widgets/wecom_icon.dart';

void main() {
  testWidgets('native login enters the shared verification UI', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var loginCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: NativeLoginPage(loginForTesting: ({
        required username,
        required password,
      }) async {
        loginCalls++;
        expect(username, 'sample-user');
        expect(password, 'sample-password');
        return const AcademicLoginResult(
          challenge: AcademicLoginChallenge(methods: {
            AcademicVerificationMethod.wecom: 'sample-user',
            AcademicVerificationMethod.sms: '13800001234',
          }),
        );
      }),
    ));
    final inputs = find.byType(TextFormField);
    await tester.enterText(inputs.first, 'sample-user');
    await tester.enterText(inputs.last, 'sample-password');
    await tester.ensureVisible(find.text('继续'));
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(loginCalls, 1);
    expect(find.byType(TwoStepVerification), findsOneWidget);
    expect(find.text('验证码将发送至企业微信'), findsOneWidget);
    expect(find.textContaining('sample-user'), findsNothing);
    expect(find.byType(WeComIcon), findsOneWidget);
    expect(find.byIcon(Icons.phone_android), findsOneWidget);
    await tester.tap(find.text('手机号'));
    await tester.pumpAndSettle();
    expect(find.text('验证码将发送至手机号 138****1234'), findsOneWidget);
    expect(find.textContaining('13800001234'), findsNothing);
  });

  testWidgets('native login reports invalid and failed codes in snackbars',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: NativeLoginPage(
          loginForTesting: ({
        required username,
        required password,
      }) async =>
              const AcademicLoginResult(
                challenge: AcademicLoginChallenge(methods: {
                  AcademicVerificationMethod.wecom: 'sample-user',
                }),
              )),
    ));
    final loginFields = find.byType(TextFormField);
    await tester.enterText(loginFields.first, 'sample-user');
    await tester.enterText(loginFields.last, 'sample-password');
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    final code = find.byType(TextFormField);
    await tester.tap(find.text('完成验证'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.descendant(
            of: find.byType(SnackBar), matching: find.text('请输入验证码')),
        findsOneWidget);
    await tester.enterText(code, '123');
    await tester.tap(find.text('完成验证'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.descendant(
            of: find.byType(SnackBar), matching: find.text('请输入6位验证码')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('code-error')), findsNothing);
    // The injected login result has no real service session, so verification
    // fails locally before any HTTP request is made.
    await tester.enterText(code, '123456');
    await tester.tap(find.text('完成验证'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('登录状态已失效，请重新输入账号密码')),
        findsOneWidget);
    expect(find.byType(TwoStepVerification), findsOneWidget);
  });

  testWidgets(
      'native verification loads the requested button and restores on errors',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final send = Completer<void>();
    final verify = Completer<Uri>();
    var sendCalls = 0;
    var verifyCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: NativeLoginPage(
        loginForTesting: ({required username, required password}) async =>
            const AcademicLoginResult(
          challenge: AcademicLoginChallenge(methods: {
            AcademicVerificationMethod.wecom: 'sample-user',
          }),
        ),
        sendCodeForTesting: (method) {
          expect(method, AcademicVerificationMethod.wecom);
          sendCalls++;
          return send.future;
        },
        verifyCodeForTesting: ({required method, required code}) {
          expect(method, AcademicVerificationMethod.wecom);
          expect(code, '123456');
          verifyCalls++;
          return verify.future;
        },
      ),
    ));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'sample-user');
    await tester.enterText(fields.last, 'sample-password');
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    final sendButton = find.byType(TextButton);
    final verifyButton = find.byType(FilledButton);
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    expect(sendCalls, 1);
    expect(
        find.descendant(
            of: sendButton, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    expect(
        find.descendant(
            of: verifyButton, matching: find.byType(CircularProgressIndicator)),
        findsNothing);
    expect(tester.widget<TextButton>(sendButton).onPressed, isNull);
    expect(tester.widget<FilledButton>(verifyButton).onPressed, isNull);
    await tester.tap(sendButton, warnIfMissed: false);
    await tester.tap(verifyButton, warnIfMissed: false);
    expect(sendCalls, 1);
    expect(verifyCalls, 0);
    send.completeError(const AcademicNativeAuthException('test', '发码失败'));
    await tester.pumpAndSettle();
    expect(find.text('发码失败'), findsOneWidget);
    expect(find.text('发送验证码'), findsOneWidget);
    expect(tester.widget<TextButton>(sendButton).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(verifyButton).onPressed, isNotNull);

    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('完成验证'));
    await tester.pump();
    expect(verifyCalls, 1);
    expect(
        find.descendant(
            of: verifyButton, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    expect(
        find.descendant(
            of: sendButton, matching: find.byType(CircularProgressIndicator)),
        findsNothing);
    expect(tester.widget<TextButton>(sendButton).onPressed, isNull);
    expect(tester.widget<FilledButton>(verifyButton).onPressed, isNull);
    await tester.tap(verifyButton, warnIfMissed: false);
    expect(verifyCalls, 1);
    verify.completeError(const AcademicNativeAuthException('test', '验证失败'));
    await tester.pumpAndSettle();
    expect(find.text('验证失败'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<TextButton>(sendButton).onPressed, isNotNull);
    expect(tester.widget<FilledButton>(verifyButton).onPressed, isNotNull);
  });

  testWidgets('shared verification switches method and dispatches actions',
      (tester) async {
    final code = TextEditingController();
    final focus = FocusNode();
    addTearDown(code.dispose);
    addTearDown(focus.dispose);
    var selected = 'wecom';
    var sent = 0;
    var verified = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return TwoStepVerification(
            methods: const {'wecom': 'student-account', 'sms': '13800001234'},
            selectedMethod: selected,
            codeController: code,
            codeFocusNode: focus,
            onMethodChanged: (method) => setState(() => selected = method),
            onSendCode: () => sent++,
            onVerifyCode: () => verified++,
          );
        }),
      ),
    ));

    expect(find.text('验证码将发送至企业微信'), findsOneWidget);
    expect(find.textContaining('student-account'), findsNothing);
    expect(find.byType(WeComIcon), findsOneWidget);
    expect(find.byIcon(Icons.phone_android), findsOneWidget);
    await tester.tap(find.text('手机号'));
    await tester.pumpAndSettle();
    expect(selected, 'sms');
    expect(find.text('验证码将发送至手机号 138****1234'), findsOneWidget);
    expect(find.textContaining('13800001234'), findsNothing);
    await tester.tap(find.text('发送验证码'));
    await tester.tap(find.text('完成验证'));
    expect(sent, 1);
    expect(verified, 1);
  });

  testWidgets('shared verification shows loading on the initiating button',
      (tester) async {
    final code = TextEditingController();
    final focus = FocusNode();
    addTearDown(code.dispose);
    addTearDown(focus.dispose);
    var sending = false;
    var verifying = false;
    var sent = 0;
    var verified = 0;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return TwoStepVerification(
          methods: const {'sms': '138****1234'},
          selectedMethod: 'sms',
          codeController: code,
          codeFocusNode: focus,
          busy: sending || verifying,
          sending: sending,
          verifying: verifying,
          onMethodChanged: (_) {},
          onSendCode: () => setState(() {
            sending = true;
            sent++;
          }),
          onVerifyCode: () => setState(() {
            verifying = true;
            verified++;
          }),
        );
      })),
    ));
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    expect(sent, 1);
    expect(
        find.descendant(
            of: find.byType(TextButton),
            matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(CircularProgressIndicator)),
        findsNothing);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.byType(TextButton), warnIfMissed: false);
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    expect(sent, 1);
    expect(verified, 0);
    update(() => sending = false);
    await tester.pump();
    await tester.tap(find.text('完成验证'));
    await tester.pump();
    expect(verified, 1);
    expect(
        find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(TextButton),
            matching: find.byType(CircularProgressIndicator)),
        findsNothing);
    update(() => verifying = false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNotNull);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  testWidgets('large text on a narrow screen keeps both methods usable',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final code = TextEditingController();
    final focus = FocusNode();
    addTearDown(code.dispose);
    addTearDown(focus.dispose);
    var selected = 'wecom';

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return TwoStepVerification(
            methods: const {'wecom': 'account', 'sms': '138****1234'},
            selectedMethod: selected,
            codeController: code,
            codeFocusNode: focus,
            onMethodChanged: (method) => setState(() => selected = method),
            onSendCode: () {},
            onVerifyCode: () {},
          );
        }),
      ),
    ));
    await tester.ensureVisible(find.text('手机号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手机号'));
    await tester.pumpAndSettle();
    expect(selected, 'sms');
    await tester.ensureVisible(find.text('完成验证'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
