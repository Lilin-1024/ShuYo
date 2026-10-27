import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/recovery_auth_service.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import 'recovery_final_page.dart';
import 'widgets/two_step_verification.dart';

/// The next screen after the university accepts the account information.
class RecoveryVerificationPage extends StatefulWidget {
  const RecoveryVerificationPage.resetPassword({
    super.key,
    required this.methods,
    required this.service,
  }) : _resetPassword = true;

  const RecoveryVerificationPage.changePhone({
    super.key,
    required this.methods,
    required this.service,
  }) : _resetPassword = false;

  /// Available method identifiers and their server-provided destination hints.
  final Map<String, String> methods;

  /// The first page owns this session until this flow is closed.
  final RecoveryAuthService service;
  final bool _resetPassword;

  @override
  State<RecoveryVerificationPage> createState() =>
      _RecoveryVerificationPageState();
}

class _RecoveryVerificationPageState extends State<RecoveryVerificationPage> {
  late String? _selectedMethod;
  final _code = TextEditingController();
  final _codeFocusNode = FocusNode();
  Timer? _countdownTimer;
  DateTime? _resendAt;
  int _countdown = 0;
  bool _sending = false;
  bool _verifying = false;

  bool get _busy => _sending || _verifying;

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.methods.containsKey('wecom')
        ? 'wecom'
        : widget.methods.keys.firstOrNull;
    final resendAt =
        widget.service.verificationCodeResendAt(widget._resetPassword);
    if (resendAt != null && resendAt.isAfter(widget.service.currentTime)) {
      _resendAt = resendAt;
      _countdown = _remainingSeconds(resendAt);
      _scheduleCountdown();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _code.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  int _remainingSeconds(DateTime resendAt) =>
      (resendAt.difference(widget.service.currentTime).inMilliseconds / 1000)
          .ceil();

  void _startCountdown(DateTime resendAt) {
    _resendAt = resendAt;
    setState(() => _countdown = _remainingSeconds(resendAt));
    _scheduleCountdown();
  }

  void _scheduleCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final seconds = _remainingSeconds(_resendAt!);
      final next = seconds < _countdown ? seconds : _countdown - 1;
      if (!mounted || next <= 0) {
        timer.cancel();
        if (mounted) setState(() => _countdown = 0);
        return;
      }
      setState(() => _countdown = next);
    });
  }

  Future<void> _sendCode() async {
    final method = _selectedMethod;
    if (_busy || _countdown > 0 || method == null) return;
    setState(() => _sending = true);
    try {
      await widget.service.sendVerificationCode(method: method);
      final resendAt =
          widget.service.recordVerificationCodeSent(widget._resetPassword);
      if (!mounted) return;
      _startCountdown(resendAt);
      _showMessage('验证码已发送');
    } on RecoveryAuthException catch (error) {
      _showMessage(error.message);
    } on Object {
      _showMessage('验证码发送失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    final method = _selectedMethod;
    if (_busy || method == null) return;
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _codeFocusNode.requestFocus();
      _showMessage(code.isEmpty ? '请输入验证码' : '请输入6位验证码');
      return;
    }
    setState(() => _verifying = true);
    var verified = false;
    try {
      await widget.service.verifyVerificationCode(method: method, code: code);
      verified = true;
    } on RecoveryAuthException catch (error) {
      _showMessage(error.message);
    } on Object {
      _showMessage('验证失败，请稍后重试');
    } finally {
      if (mounted && _verifying) setState(() => _verifying = false);
    }
    if (!mounted || !verified) return;
    final completed = await Navigator.of(context).push<bool>(
      shuyoRoute(
        builder: (_) => widget._resetPassword
            ? RecoveryFinalPage.resetPassword(service: widget.service)
            : RecoveryFinalPage.changePhone(service: widget.service),
      ),
    );
    if (mounted && completed == true) Navigator.of(context).pop(true);
  }

  Widget _verification() => TwoStepVerification(
        methods: widget.methods,
        selectedMethod: _selectedMethod!,
        codeController: _code,
        codeFocusNode: _codeFocusNode,
        busy: _busy,
        sending: _sending,
        verifying: _verifying,
        countdown: _countdown,
        digitsOnly: true,
        onMethodChanged: (method) => setState(() {
          _selectedMethod = method;
          _code.clear();
        }),
        onSendCode: _sendCode,
        onVerifyCode: _verifyCode,
      );

  @override
  Widget build(BuildContext context) {
    final noMethods = widget.methods.isEmpty;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(widget._resetPassword ? '重置密码' : '修改手机号')),
        body: SafeArea(
          child: noMethods ? _noMethods(context) : _verification(),
        ),
      ),
    );
  }

  Widget _noMethods(BuildContext context) {
    final colors = context.shuyoColors;
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '安全验证',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 12),
                Text(
                  '当前账户没有可用的验证方式，请返回上一页重试。',
                  style: TextStyle(color: colors.textSecondary, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
