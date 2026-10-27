import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/services/recovery_auth_service.dart';
import 'package:shuyo/features/auth/recovery_form_page.dart';
import 'package:shuyo/features/auth/login_help_page.dart';
import 'package:shuyo/features/auth/native_login_page.dart';
import 'package:shuyo/features/auth/recovery_final_page.dart';
import 'package:shuyo/features/auth/recovery_verification_page.dart';
import 'package:shuyo/features/auth/widgets/two_step_verification.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';
import 'package:shuyo/shared/widgets/wecom_icon.dart';

class _FakeRecoveryAuthService extends RecoveryAuthService {
  Completer<RecoveryChallenge> result = Completer<RecoveryChallenge>();
  DateTime? clock;
  @override
  DateTime get currentTime => clock ?? super.currentTime;

  int calls = 0;
  Map<String, String>? submitted;
  final sentMethods = <String>[];
  final verifiedCodes = <Map<String, String>>[];
  final sentPhones = <String>[];
  final submittedPhones = <Map<String, String>>[];
  final submittedPasswords = <Map<String, String>>[];
  Completer<void>? sendResult;
  Completer<void>? verificationResult;
  Completer<void>? sendPhoneResult;
  Completer<void>? finalResult;

  @override
  Future<void> sendVerificationCode({required String method}) {
    sentMethods.add(method);
    return sendResult?.future ?? Future.value();
  }

  @override
  Future<void> verifyVerificationCode(
      {required String method, required String code}) {
    verifiedCodes.add({'method': method, 'code': code});
    return verificationResult?.future ?? Future.value();
  }

  @override
  Future<void> sendNewPhoneCode({required String phone}) {
    sentPhones.add(phone);
    return sendPhoneResult?.future ?? Future.value();
  }

  @override
  Future<void> submitNewPhone({required String phone, required String code}) {
    submittedPhones.add({'phone': phone, 'code': code});
    return finalResult?.future ?? Future.value();
  }

  @override
  Future<void> resetPassword(
      {required String password, required String confirmPassword}) {
    submittedPasswords
        .add({'password': password, 'confirmPassword': confirmPassword});
    return finalResult?.future ?? Future.value();
  }

  @override
  Future<RecoveryChallenge> verifyResetInfo({
    required String username,
    required String realName,
    required String identityID,
    required String cardID,
  }) {
    calls++;
    submitted = {
      'username': username,
      'realName': realName,
      'identityID': identityID,
      'cardID': cardID,
    };
    return result.future;
  }

  @override
  Future<RecoveryChallenge> verifyChangePhoneUser({
    required String username,
    required String password,
  }) {
    calls++;
    submitted = {'username': username, 'password': password};
    return result.future;
  }
}

void _expectSuccessLayout(
    WidgetTester tester, String title, String description) {
  final appBar = tester.widget<AppBar>(find.byType(AppBar));
  expect(appBar.title, isNull);
  final titleFinder = find.text(title);
  final descriptionFinder = find.text(description);
  expect(titleFinder, findsOneWidget);
  expect(descriptionFinder, findsOneWidget);
  final screenCenter = tester.getCenter(find.byType(Scaffold)).dx;
  expect(tester.getCenter(titleFinder).dx, closeTo(screenCenter, 1));
  expect(tester.getCenter(descriptionFinder).dx, closeTo(screenCenter, 1));
  expect(tester.widget<Text>(titleFinder).textAlign, TextAlign.center);
  expect(tester.widget<Text>(descriptionFinder).textAlign, TextAlign.center);
  expect(
    find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Icon),
    ),
    findsNothing,
  );
}

Future<void> _expectSuccessSlide(WidgetTester tester, String title) async {
  // The result page uses the project's normal 240 ms horizontal route on
  // Android. Measure the visible content, not just the route's widget type.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  final titleFinder = find.text(title);
  expect(titleFinder, findsOneWidget);
  final startX = tester.getCenter(titleFinder).dx;
  await tester.pump(const Duration(milliseconds: 100));
  final middleX = tester.getCenter(titleFinder).dx;
  await tester.pumpAndSettle();
  final endX = tester.getCenter(titleFinder).dx;
  expect(startX, greaterThan(middleX));
  expect(middleX, greaterThan(endX + 1));
  expect(
      endX,
      closeTo(tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
          1));
}

void main() {
  for (final themeId in [ShuYoThemes.systemLightId, ShuYoThemes.systemDarkId]) {
    testWidgets('recovery forms use themed floating inputs in $themeId',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      final pages = <(Widget, List<String>)>[
        (
          RecoveryFormPage.resetPassword(service: service),
          ['学/工号', '姓名', '证件号码', '校园卡号']
        ),
        (RecoveryFormPage.changePhone(service: service), ['学/工号', '密码']),
        (RecoveryFinalPage.resetPassword(service: service), ['新密码', '确认新密码']),
        (RecoveryFinalPage.changePhone(service: service), ['新手机号', '验证码']),
      ];
      final theme = ShuYoThemes.byId(themeId).themeData();
      final colors = theme.extension<ShuYoColors>()!;

      for (final (page, labels) in pages) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(theme: theme, home: page));
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        expect(fields, findsNWidgets(labels.length));
        for (var i = 0; i < labels.length; i++) {
          await tester.ensureVisible(fields.at(i));
          await tester.pumpAndSettle();
          final input = tester.widget<TextField>(find.descendant(
            of: fields.at(i),
            matching: find.byType(TextField),
          ));
          final decoration = input.decoration!;
          expect(decoration.labelText, labels[i]);
          expect(decoration.filled, isTrue);
          expect(decoration.fillColor, colors.surface);
          expect(decoration.enabledBorder, isA<OutlineInputBorder>());
          expect(decoration.enabledBorder!.borderSide.color, colors.border);
          expect(decoration.focusedBorder, isA<OutlineInputBorder>());
          expect(decoration.focusedBorder!.borderSide.color, colors.accent);
          final label = find.descendant(
            of: fields.at(i),
            matching: find.text(labels[i]),
          );
          expect(label, findsOneWidget);
          final unfocusedTop = tester.getTopLeft(label).dy;
          await tester.tap(fields.at(i));
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(label).dy, lessThan(unfocusedTop));
          await tester.enterText(fields.at(i), '123456');
          expect(input.controller?.text, '123456');
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final reset in [true, false]) {
    final flow = reset ? 'reset password' : 'change phone';

    testWidgets('$flow requires all fields before submitting', (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      await tester.pumpWidget(MaterialApp(
        home: reset
            ? RecoveryFormPage.resetPassword(service: service)
            : RecoveryFormPage.changePhone(service: service),
      ));
      await tester.ensureVisible(find.text('下一步'));
      await tester.tap(find.text('下一步'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('请填写完整信息'), findsOneWidget);
      expect(service.calls, 0);
    });

    testWidgets('$flow submission loads, reports error, and navigates',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      await tester.pumpWidget(MaterialApp(
        home: reset
            ? RecoveryFormPage.resetPassword(service: service)
            : RecoveryFormPage.changePhone(service: service),
      ));

      final values = reset
          ? ['test-user', 'Test Name', 'test-id', '001234']
          : ['test-user', 'test-password'];
      final fields = find.byType(TextFormField);
      for (var i = 0; i < values.length; i++) {
        await tester.enterText(fields.at(i), values[i]);
      }
      await tester.ensureVisible(find.text('下一步'));
      await tester.tap(find.text('下一步'));
      await tester.pump();

      expect(service.calls, 1);
      expect(
        service.submitted,
        reset
            ? {
                'username': values[0],
                'realName': values[1],
                'identityID': values[2],
                'cardID': values[3],
              }
            : {'username': values[0], 'password': values[1]},
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      expect(service.calls, 1);

      service.result.completeError(
        const RecoveryAuthException('invalid', '测试验证失败'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('测试验证失败'), findsOneWidget);
      expect(find.byType(RecoveryVerificationPage), findsNothing);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);

      service.result = Completer<RecoveryChallenge>();
      await tester.tap(find.text('下一步'));
      await tester.pump();
      expect(service.calls, 2);
      service.result.complete(RecoveryChallenge({'wecom': '测试提示'}));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryVerificationPage), findsOneWidget);
      expect(
          tester
              .widget<RecoveryVerificationPage>(
                find.byType(RecoveryVerificationPage),
              )
              .service,
          same(service));
      expect(find.text('二步验证'), findsOneWidget);
      expect(find.byType(TwoStepVerification), findsOneWidget);
      expect(find.text('验证码将发送至企业微信'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$flow ignores response after the form is disposed',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      await tester.pumpWidget(MaterialApp(
        home: reset
            ? RecoveryFormPage.resetPassword(service: service)
            : RecoveryFormPage.changePhone(service: service),
      ));
      final fields = find.byType(TextFormField);
      for (var i = 0; i < fields.evaluate().length; i++) {
        await tester.enterText(fields.at(i), 'test$i');
      }
      await tester.ensureVisible(find.text('下一步'));
      await tester.tap(find.text('下一步'));
      await tester.pump();
      expect(service.calls, 1);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      service.result.complete(RecoveryChallenge({'sms': '测试提示'}));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  for (final reset in [true, false]) {
    final flow = reset ? 'reset password' : 'change phone';

    Widget verificationPage(
        RecoveryAuthService service, Map<String, String> methods) {
      final page = reset
          ? RecoveryVerificationPage.resetPassword(
              methods: methods, service: service)
          : RecoveryVerificationPage.changePhone(
              methods: methods, service: service);
      return MaterialApp(home: page);
    }

    testWidgets('$flow verification displays and switches both methods',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      await tester.pumpWidget(verificationPage(service, const {
        'sms': '138****1234',
        'wecom': 'test-wecom',
      }));

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(reset ? '重置密码' : '修改手机号'),
        ),
        findsOneWidget,
      );
      expect(find.text('二步验证'), findsOneWidget);
      expect(find.byType(TwoStepVerification), findsOneWidget);
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      final selector = tester.widget<SegmentedButton<String>>(
          find.byType(SegmentedButton<String>));
      expect(
        selector.segments
            .singleWhere((segment) => segment.value == 'wecom')
            .icon,
        isA<WeComIcon>(),
      );
      expect(
        selector.segments.singleWhere((segment) => segment.value == 'sms').icon,
        isA<Icon>(),
      );
      expect(find.text('验证码将发送至企业微信'), findsOneWidget);
      expect(find.textContaining('test-wecom'), findsNothing);
      await tester.tap(find.text('手机号'));
      await tester.pumpAndSettle();
      expect(find.text('验证码将发送至手机号 138****1234'), findsOneWidget);
      expect(find.text('验证码将发送至企业微信'), findsNothing);
      await tester.tap(find.text('企业微信'));
      await tester.pumpAndSettle();
      expect(find.text('验证码将发送至企业微信'), findsOneWidget);
      expect(find.textContaining('test-wecom'), findsNothing);
    });

    testWidgets('$flow masks an unmasked phone destination', (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      await tester.pumpWidget(verificationPage(service, const {
        'sms': '13800001234',
        'wecom': 'student-identifier',
      }));
      expect(find.textContaining('student-identifier'), findsNothing);
      await tester.tap(find.text('手机号'));
      await tester.pumpAndSettle();
      expect(find.text('验证码将发送至手机号 138****1234'), findsOneWidget);
      expect(find.textContaining('13800001234'), findsNothing);
    });

    testWidgets('$flow verification hides selector for one method',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      for (final method in ['sms', 'wecom']) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(verificationPage(service, {method: 'test'}));
        await tester.pumpAndSettle();
        expect(find.byType(SegmentedButton<String>), findsNothing);
        expect(
          find.text(method == 'sms' ? '验证码将发送至手机号 test' : '验证码将发送至企业微信'),
          findsOneWidget,
        );
        if (method == 'wecom') {
          expect(find.textContaining('test'), findsNothing);
        }
      }
    });

    testWidgets(
        '$flow code input limits length and validates before submitting',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      await tester.pumpWidget(verificationPage(service, const {'sms': 'test'}));
      final input = find.byType(TextFormField);
      expect(input, findsOneWidget);
      expect(
        tester
            .widget<TextField>(
                find.descendant(of: input, matching: find.byType(TextField)))
            .keyboardType,
        TextInputType.number,
      );
      await tester.tap(find.text('完成验证'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.descendant(
              of: find.byType(SnackBar), matching: find.text('请输入验证码')),
          findsOneWidget);
      expect(service.verifiedCodes, isEmpty);
      await tester.enterText(input, '12345678');
      expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          '123456');
      await tester.enterText(input, '123');
      await tester.tap(find.text('完成验证'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.descendant(
              of: find.byType(SnackBar), matching: find.text('请输入6位验证码')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('code-error')), findsNothing);
      expect(service.verifiedCodes, isEmpty);
      await tester.enterText(input, '123456');
      await tester.tap(find.text('完成验证'));
      await tester.pumpAndSettle();
      expect(service.verifiedCodes.single, {'method': 'sms', 'code': '123456'});
      expect(find.byType(RecoveryFinalPage), findsOneWidget);
    });

    testWidgets('$flow keeps the send cooldown when switching methods',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      service.sendResult = Completer<void>();
      await tester.pumpWidget(verificationPage(service, const {
        'sms': '138****1234',
        'wecom': 'test-wecom',
      }));
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      expect(service.sentMethods, ['wecom']);
      expect(
          find.descendant(
            of: find.byType(TextButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget);
      expect(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      service.sendResult!.complete();
      await tester.pump();
      expect(find.text('验证码已发送'), findsOneWidget);
      expect(find.textContaining('重发'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('手机号'));
      await tester.pump();
      expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          isEmpty);
      expect(find.textContaining('重发'), findsOneWidget);
      final send = find.ancestor(
          of: find.textContaining('重发'), matching: find.byType(TextButton));
      expect(tester.widget<TextButton>(send).onPressed, isNull);
      expect(service.sentMethods, ['wecom']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$flow reports verification errors and navigates after success',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      service.verificationResult = Completer<void>();
      await tester.pumpWidget(verificationPage(service, const {'sms': 'test'}));
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('完成验证'));
      await tester.pump();
      expect(service.verifiedCodes, [
        {'method': 'sms', 'code': '123456'}
      ]);
      expect(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget);
      expect(
          find.descendant(
            of: find.byType(TextButton),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing);
      service.verificationResult!
          .completeError(const RecoveryAuthException('invalid', '验证码错误'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.descendant(
              of: find.byType(SnackBar), matching: find.text('验证码错误')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('code-error')), findsNothing);
      expect(find.byType(RecoveryFinalPage), findsNothing);
      service.verificationResult = null;
      await tester.tap(find.text('完成验证'));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryFinalPage), findsOneWidget);
      expect(find.text(reset ? '设置新密码' : '绑定新手机号'), findsOneWidget);
    });

    testWidgets(
        '$flow ignores send response after verification page is disposed',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      service.sendResult = Completer<void>();
      await tester.pumpWidget(verificationPage(service, const {'sms': 'test'}));
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      service.sendResult!.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$flow reports send failure without starting cooldown',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      service.sendResult = Completer<void>();
      await tester.pumpWidget(verificationPage(service, const {'sms': 'test'}));
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      service.sendResult!
          .completeError(const RecoveryAuthException('failed', '测试发送失败'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('测试发送失败'), findsOneWidget);
      expect(find.textContaining('重发'), findsNothing);
      expect(find.text('发送验证码'), findsOneWidget);
    });

    testWidgets('$flow restores cooldown after returning to the first page',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      final started = DateTime(2030, 1, 1);
      service.clock = started;
      await tester.pumpWidget(MaterialApp(
        home: reset
            ? RecoveryFormPage.resetPassword(service: service)
            : RecoveryFormPage.changePhone(service: service),
      ));
      final fields = find.byType(TextFormField);
      for (var i = 0; i < fields.evaluate().length; i++) {
        await tester.enterText(fields.at(i), 'test$i');
      }
      Future<void> enterVerification() async {
        service.result = Completer<RecoveryChallenge>();
        await tester.ensureVisible(find.text('下一步'));
        await tester.tap(find.text('下一步'));
        await tester.pump();
        service.result.complete(RecoveryChallenge({'sms': '138****1234'}));
        await tester.pumpAndSettle();
      }

      await enterVerification();
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      expect(service.sentMethods, ['sms']);
      expect(find.text('重发 60s'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryFormPage), findsOneWidget);
      service.clock = started.add(const Duration(seconds: 20));
      await enterVerification();
      expect(find.text('重发 40s'), findsOneWidget);
      final resend = find.ancestor(
          of: find.text('重发 40s'), matching: find.byType(TextButton));
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      service.clock = started.add(const Duration(seconds: 61));
      await enterVerification();
      expect(find.text('发送验证码'), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.ancestor(
                of: find.text('发送验证码'),
                matching: find.byType(TextButton),
              ))
              .onPressed,
          isNotNull);
      expect(service.sentMethods, ['sms']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$flow blocks back navigation while sending or verifying',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      service.sendResult = Completer<void>();
      service.verificationResult = Completer<void>();
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return Scaffold(
            body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => reset
                ? RecoveryVerificationPage.resetPassword(
                    methods: const {'sms': 'test'}, service: service)
                : RecoveryVerificationPage.changePhone(
                    methods: const {'sms': 'test'}, service: service),
          )),
          child: const Text('打开验证'),
        ));
      })));
      await tester.tap(find.text('打开验证'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送验证码'));
      await tester.pump();
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(RecoveryVerificationPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(RecoveryVerificationPage), findsOneWidget);
      service.sendResult!
          .completeError(const RecoveryAuthException('failed', '发送失败'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('完成验证'));
      await tester.pump();
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(RecoveryVerificationPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(RecoveryVerificationPage), findsOneWidget);
      service.verificationResult!
          .completeError(const RecoveryAuthException('failed', '验证失败'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('打开验证'), findsOneWidget);
    });

    testWidgets('$flow verification scrolls above keyboard on a short screen',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      await tester.pumpWidget(verificationPage(service, const {
        'sms': '138****1234',
        'wecom': 'test-wecom',
      }));
      await tester.tap(find.byType(TextFormField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('完成验证'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(FilledButton)).bottom,
          lessThanOrEqualTo(568 - 250));
      expect(tester.takeException(), isNull);
    });
  }

  for (final reset in [true, false]) {
    testWidgets('manual back leaves each recovery step open: $reset',
        (tester) async {
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => reset
                    ? RecoveryFormPage.resetPassword(service: service)
                    : RecoveryFormPage.changePhone(service: service),
              ),
            ),
            child: const Text('打开找回'),
          ),
        );
      })));
      await tester.tap(find.text('打开找回'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (var i = 0; i < fields.evaluate().length; i++) {
        await tester.enterText(fields.at(i), 'test$i');
      }
      await tester.ensureVisible(find.text('下一步'));
      await tester.tap(find.text('下一步'));
      await tester.pump();
      service.result.complete(RecoveryChallenge({'sms': 'test'}));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('完成验证'));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryFinalPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryVerificationPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryFormPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('打开找回'), findsOneWidget);
    });
  }

  testWidgets('reset skips verification when no methods are returned',
      (tester) async {
    final service = _FakeRecoveryAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
      home: RecoveryFormPage.resetPassword(service: service),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), 'test$i');
    }
    await tester.ensureVisible(find.text('下一步'));
    await tester.tap(find.text('下一步'));
    await tester.pump();
    service.result.complete(RecoveryChallenge({}));
    await tester.pumpAndSettle();
    expect(find.byType(RecoveryVerificationPage), findsNothing);
    expect(find.byType(RecoveryFinalPage), findsOneWidget);
    expect(find.text('设置新密码'), findsOneWidget);
    expect(find.text('新密码'), findsOneWidget);
    expect(find.text('确认新密码'), findsOneWidget);
    expect(find.text('发送验证码'), findsNothing);
  });

  testWidgets('change phone explains when no methods are available',
      (tester) async {
    final service = _FakeRecoveryAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
      home: RecoveryVerificationPage.changePhone(
        methods: const {},
        service: service,
      ),
    ));
    expect(find.text('当前账户没有可用的验证方式，请返回上一页重试。'), findsOneWidget);
    expect(find.text('发送验证码'), findsNothing);
  });

  testWidgets(
      'reset password validates input, shows errors, and finishes the flow',
      (tester) async {
    bool? outcome;
    final service = _FakeRecoveryAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
        onPressed: () => Navigator.of(context)
            .push<bool>(MaterialPageRoute<bool>(
              builder: (_) => RecoveryFormPage.resetPassword(service: service),
            ))
            .then((value) => outcome = value),
        child: const Text('打开找回'),
      ));
    })));
    await tester.tap(find.text('打开找回'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), 'test$i');
    }
    await tester.ensureVisible(find.text('下一步'));
    await tester.tap(find.text('下一步'));
    await tester.pump();
    service.result.complete(RecoveryChallenge({'sms': 'test'}));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('完成验证'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'weak');
    await tester.enterText(fields.at(1), 'weak');
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('密码强度不足，请按提示设置密码'), findsOneWidget);
    expect(service.submittedPasswords, isEmpty);
    await tester.enterText(fields.at(0), 'Test1234!');
    await tester.enterText(fields.at(1), 'Test1235!');
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    await tester.enterText(fields.at(1), 'Test1234!');
    service.finalResult = Completer<void>();
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pump();
    expect(service.submittedPasswords.single,
        {'password': 'Test1234!', 'confirmPassword': 'Test1234!'});
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    service.finalResult!
        .completeError(const RecoveryAuthException('failed', '测试提交失败'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('测试提交失败'), findsOneWidget);
    service.finalResult = Completer<void>();
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pump();
    service.finalResult!.complete();
    await _expectSuccessSlide(tester, '密码重置成功');
    _expectSuccessLayout(tester, '密码重置成功', '你现在可以使用新密码登录。');
    expect(find.byType(BackButton), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('密码重置成功'), findsOneWidget);
    expect(outcome, isNull);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(outcome, isTrue);
    expect(find.text('打开找回'), findsOneWidget);
    expect(find.byType(RecoveryFormPage), findsNothing);
  });

  testWidgets(
      'new phone checks destination, sends, submits and closes the flow',
      (tester) async {
    bool? outcome;
    final service = _FakeRecoveryAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
        onPressed: () => Navigator.of(context)
            .push<bool>(MaterialPageRoute<bool>(
              builder: (_) => RecoveryFormPage.changePhone(service: service),
            ))
            .then((value) => outcome = value),
        child: const Text('打开找回'),
      ));
    })));
    await tester.tap(find.text('打开找回'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'test-user');
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    await tester.tap(find.text('下一步'));
    await tester.pump();
    service.result.complete(RecoveryChallenge({'sms': 'test'}));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.text('完成验证'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请输入有效的手机号'), findsOneWidget);
    expect(service.sentPhones, isEmpty);
    await tester.enterText(fields.at(0), '13800000000');
    service.sendPhoneResult = Completer<void>();
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    expect(service.sentPhones, ['13800000000']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    service.sendPhoneResult!.complete();
    await tester.pump();
    expect(find.text('重发 60s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(0), '13900000000');
    await tester.enterText(fields.at(1), '123456');
    await tester.tap(find.text('确认修改'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('请先向当前手机号发送验证码'), findsOneWidget);
    expect(service.submittedPhones, isEmpty);
    await tester.enterText(fields.at(0), '13800000000');
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    service.sendPhoneResult = null;
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    await tester.enterText(fields.at(1), '123456');
    service.finalResult = Completer<void>();
    await tester.tap(find.text('确认修改'));
    await tester.pump();
    expect(service.submittedPhones.single,
        {'phone': '13800000000', 'code': '123456'});
    service.finalResult!
        .completeError(const RecoveryAuthException('failed', '验证码不正确'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('验证码不正确'), findsOneWidget);
    service.finalResult = Completer<void>();
    await tester.tap(find.text('确认修改'));
    await tester.pump();
    service.finalResult!.complete();
    await _expectSuccessSlide(tester, '手机号修改成功');
    _expectSuccessLayout(tester, '手机号修改成功', '你的认证手机号已更新。');
    expect(find.byType(BackButton), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('手机号修改成功'), findsOneWidget);
    expect(outcome, isNull);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(outcome, isTrue);
    expect(find.text('打开找回'), findsOneWidget);
    expect(find.byType(RecoveryFormPage), findsNothing);
  });

  testWidgets('new phone has fixed China prefix and the same resend countdown',
      (tester) async {
    final service = _FakeRecoveryAuthService();
    addTearDown(service.dispose);
    service.sendPhoneResult = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: RecoveryFinalPage.changePhone(service: service),
    ));
    final fields = find.byType(TextFormField);
    final phoneField = fields.first;
    expect(find.descendant(of: phoneField, matching: find.text('🇨🇳')),
        findsOneWidget);
    expect(find.descendant(of: phoneField, matching: find.text('+86')),
        findsOneWidget);
    await tester.enterText(phoneField, '13800000000');
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    expect(service.sentPhones, ['13800000000']);
    expect(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget);
    expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing);
    await tester.tap(find.byType(TextButton), warnIfMissed: false);
    await tester.pump();
    expect(service.sentPhones, ['13800000000']);
    service.sendPhoneResult!.complete();
    await tester.pump();
    expect(find.text('重发 60s'), findsOneWidget);
    final resend = find.ancestor(
        of: find.text('重发 60s'), matching: find.byType(TextButton));
    expect(tester.widget<TextButton>(resend).onPressed, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('重发 59s'), findsOneWidget);
    await tester.enterText(fields.last, '123456');
    await tester.tap(find.text('确认修改'));
    await tester.pump();
    expect(service.submittedPhones.single,
        {'phone': '13800000000', 'code': '123456'});
    await tester.pumpWidget(const SizedBox());
  });

  for (final reset in [true, false]) {
    testWidgets('login help returns to campus login only on completion: $reset',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
      await tester.tap(find.text('登录问题？'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginHelpPage), findsOneWidget);
      final action = reset ? '重置密码' : '修改手机号';
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(find.byType(RecoveryFormPage), findsOneWidget);
      // A manual back dismisses only the current form, leaving help visible.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(LoginHelpPage), findsOneWidget);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      // The fake-service flow tests above verify that success yields true.
      Navigator.of(tester.element(find.byType(RecoveryFormPage))).pop(true);
      await tester.pumpAndSettle();
      expect(find.byType(NativeLoginPage), findsOneWidget);
      expect(find.byType(LoginHelpPage), findsNothing);
      expect(find.byType(RecoveryFormPage), findsNothing);
    });
  }

  testWidgets('password strength updates as the password changes',
      (tester) async {
    final service = _FakeRecoveryAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(
        MaterialApp(home: RecoveryFinalPage.resetPassword(service: service)));

    final password = find.byType(TextFormField).first;
    // The school checks length, both ASCII cases, digits and its special set.
    const cases = <(String, String, int)>[
      ('', '弱', 0),
      ('a', '弱', 0),
      ('A', '弱', 0),
      ('a1', '弱', 1),
      ('A1', '弱', 1),
      ('1', '弱', 1),
      ('Ab1', '中', 2),
      ('Ab1!', '中', 3),
      ('Ab12345!', '强', 4),
      ('Ab123456', '中', 3),
      ('1234567', '弱', 1),
      ('12345678', '中', 2),
      ('<>', '弱', 0),
      ('!', '弱', 1),
      ('', '弱', 0),
    ];
    final colors = tester.element(find.byType(RecoveryFinalPage)).shuyoColors;
    for (final (value, label, score) in cases) {
      await tester.enterText(password, value);
      await tester.pump();
      expect(find.text('密码强度：$label', findRichText: true), findsOneWidget,
          reason: 'password input: $value');
      for (var i = 0; i < 4; i++) {
        final segment = tester.widget<Container>(
          find.byKey(ValueKey('password-strength-segment-$i')),
        );
        expect((segment.decoration! as BoxDecoration).color,
            i < score ? colors.accent : colors.border,
            reason: 'password input: $value, segment: $i');
      }
    }
  });

  testWidgets('medium strength needs three points before submission',
      (tester) async {
    final service = _FakeRecoveryAuthService();
    addTearDown(service.dispose);
    service.finalResult = Completer<void>();
    await tester.pumpWidget(
        MaterialApp(home: RecoveryFinalPage.resetPassword(service: service)));

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Ab1');
    await tester.enterText(fields.at(1), 'Ab1');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '重置密码'));
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('密码强度不足，请按提示设置密码'), findsOneWidget);
    expect(service.submittedPasswords, isEmpty);

    // The school's scoring permits a short password when the other three
    // categories are met; length is a point, not a separate minimum.
    await tester.enterText(fields.at(0), 'Ab1!');
    await tester.enterText(fields.at(1), 'Ab1!');
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pump();
    expect(service.submittedPasswords.single,
        {'password': 'Ab1!', 'confirmPassword': 'Ab1!'});
    service.finalResult!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'password strength and submission fit on a short large-text screen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final service = _FakeRecoveryAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.5)),
        child: child!,
      ),
      home: RecoveryFinalPage.resetPassword(service: service),
    ));
    await tester.enterText(find.byType(TextFormField).first, 'Ab12345!');
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(FilledButton)).bottom,
        lessThanOrEqualTo(568 - 250));
    expect(tester.takeException(), isNull);
  });

  testWidgets('new phone form stays usable with large text and keyboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final service = _FakeRecoveryAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.5)),
        child: child!,
      ),
      home: RecoveryFinalPage.changePhone(service: service),
    ));

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, '13800000000');
    await tester.tap(fields.last);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('发送验证码'));
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    expect(service.sentPhones, ['13800000000']);
    expect(find.text('重发 60s'), findsOneWidget);
    await tester.ensureVisible(find.text('确认修改'));
    await tester.pump();
    expect(tester.getRect(find.byType(FilledButton)).bottom,
        lessThanOrEqualTo(568 - 250));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final resetPassword in [true, false]) {
    testWidgets(
        '${resetPassword ? 'reset password' : 'change phone'} success fits a short screen with large text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final service = _FakeRecoveryAuthService();
      addTearDown(service.dispose);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: resetPassword
            ? RecoveryFinalPage.resetPassword(service: service)
            : RecoveryFinalPage.changePhone(service: service),
      ));
      final fields = find.byType(TextFormField);
      if (resetPassword) {
        await tester.enterText(fields.at(0), 'Test1234!');
        await tester.enterText(fields.at(1), 'Test1234!');
      } else {
        await tester.enterText(fields.at(0), '13800000000');
        await tester.ensureVisible(find.text('发送验证码'));
        await tester.tap(find.text('发送验证码'));
        await tester.pump();
        await tester.enterText(fields.at(1), '123456');
      }
      final submit =
          find.widgetWithText(FilledButton, resetPassword ? '重置密码' : '确认修改');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      _expectSuccessLayout(
        tester,
        resetPassword ? '密码重置成功' : '手机号修改成功',
        resetPassword ? '你现在可以使用新密码登录。' : '你的认证手机号已更新。',
      );
      await tester.ensureVisible(find.text('完成'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('完成')).bottom, lessThanOrEqualTo(400));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('final form ignores submit response after disposal',
      (tester) async {
    final service = _FakeRecoveryAuthService();
    addTearDown(service.dispose);
    service.finalResult = Completer<void>();
    await tester.pumpWidget(
        MaterialApp(home: RecoveryFinalPage.resetPassword(service: service)));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test1234!');
    await tester.enterText(fields.at(1), 'Test1234!');
    await tester.tap(find.widgetWithText(FilledButton, '重置密码'));
    await tester.pump();
    expect(service.submittedPasswords, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    service.finalResult!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
