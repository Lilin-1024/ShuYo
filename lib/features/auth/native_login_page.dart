import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/academic_native_auth_service.dart';
import '../../data/services/verification_delivery_service.dart';
import 'forum_oauth_completion_page.dart';
import 'webvpn_oauth_completion_page.dart';

enum NativeLoginDestination { academic, forum }

class NativeLoginPage extends StatefulWidget {
  const NativeLoginPage({
    super.key,
    this.destination = NativeLoginDestination.academic,
  });

  const NativeLoginPage.forum({super.key})
      : destination = NativeLoginDestination.forum;

  final NativeLoginDestination destination;

  @override
  State<NativeLoginPage> createState() => _NativeLoginPageState();
}

class _NativeLoginPageState extends State<NativeLoginPage> {
  late final AcademicNativeAuthService _authService =
      widget.destination == NativeLoginDestination.forum
          ? AcademicNativeAuthService.forForum()
          : AcademicNativeAuthService();
  final _verificationDeliveryService = VerificationDeliveryService();
  final _studentId = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _credentialsKey = GlobalKey<FormState>();
  final _verificationKey = GlobalKey<FormState>();

  int _step = 0;
  bool _busy = false;
  bool _passwordVisible = false;
  AcademicLoginChallenge? _challenge;
  AcademicVerificationMethod _method = AcademicVerificationMethod.wecom;
  Timer? _countdownTimer;
  int _countdown = 0;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _authService.dispose();
    _studentId.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_busy) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (_step) {
            0 => widget.destination == NativeLoginDestination.forum
                ? '乐乎论坛账户'
                : '上大校园账户',
            _ => '验证身份',
          }),
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: switch (_step) {
              0 => _credentials(),
              _ => _verification(),
            },
          ),
        ),
      ),
    );
  }

  Widget _credentials() => Form(
        key: _credentialsKey,
        child: ListView(
          key: const ValueKey('credentials'),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
                widget.destination == NativeLoginDestination.forum
                    ? '使用上海大学统一认证登录乐乎论坛'
                    : '使用上海大学账户来访问各种校园服务',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 28),
            TextFormField(
              controller: _studentId,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                  labelText: '学号', prefixIcon: Icon(Icons.badge_outlined)),
              validator: (value) =>
                  value?.trim().isEmpty == true ? '请输入学号' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_passwordVisible,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submitCredentials(),
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _passwordVisible ? '隐藏密码' : '显示密码',
                  onPressed: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                  icon: Icon(_passwordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                ),
              ),
              validator: (value) => value?.isEmpty == true ? '请输入密码' : null,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _submitCredentials,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              child: _buttonContent('继续'),
            ),
          ],
        ),
      );

  Widget _verification() {
    final methods = _challenge?.methods ?? const {};
    return Form(
      key: _verificationKey,
      child: ListView(
        key: const ValueKey('verification'),
        padding: const EdgeInsets.all(24),
        children: [
          Text('二步验证',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_methodHint(methods)),
          const SizedBox(height: 24),
          SegmentedButton<AcademicVerificationMethod>(
            segments: [
              if (methods.containsKey(AcademicVerificationMethod.wecom))
                const ButtonSegment(
                    value: AcademicVerificationMethod.wecom,
                    label: Text('企业微信'),
                    icon: Icon(Icons.business_center_outlined)),
              if (methods.containsKey(AcademicVerificationMethod.sms))
                const ButtonSegment(
                    value: AcademicVerificationMethod.sms,
                    label: Text('手机号'),
                    icon: Icon(Icons.sms_outlined)),
            ],
            selected: {_method},
            onSelectionChanged: _busy
                ? null
                : (value) => _selectVerificationMethod(value.first),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy || _countdown > 0 ? null : _sendCode,
            icon: const Icon(Icons.send_outlined),
            label: Text(_countdown > 0 ? '${_countdown}s 后可重新发送' : '发送验证码'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _verifyCode(),
            decoration: const InputDecoration(
                labelText: '验证码', prefixIcon: Icon(Icons.password_outlined)),
            validator: (value) => value?.trim().length == 6 ? null : '请输入6位验证码',
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _verifyCode,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _buttonContent('完成验证'),
          ),
        ],
      ),
    );
  }

  Widget _buttonContent(String label) {
    if (!_busy) return Text(label);
    return const SizedBox.square(
        dimension: 20, child: CircularProgressIndicator(strokeWidth: 2));
  }

  Future<void> _submitCredentials() async {
    if (_busy || _credentialsKey.currentState?.validate() != true) return;
    setState(() => _busy = true);
    try {
      final result = await _authService.login(
          username: _studentId.text.trim(), password: _password.text);
      _password.clear();
      if (!mounted) return;
      if (result.callbackUri != null) {
        await _completeLogin(result.callbackUri!);
        return;
      }
      final challenge = result.challenge;
      if (challenge == null) throw StateError('学校未返回登录结果');
      final methods = challenge.methods.keys;
      final preferred =
          await _verificationDeliveryService.preferredMethod(methods);
      final remaining =
          await _verificationDeliveryService.remainingCooldown(preferred);
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _method = preferred;
        _step = 1;
      });
      _startCountdown(remaining);
    } on AcademicNativeAuthException catch (error) {
      _showError(error.message);
    } on Object {
      _showError('无法连接学校认证服务，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    if (_busy || _countdown > 0) return;
    setState(() => _busy = true);
    try {
      await _authService.sendCode(_method);
      await _verificationDeliveryService.markSent(_method);
      if (!mounted) return;
      _startCountdown(VerificationDeliveryService.cooldown);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('验证码已发送')));
    } on AcademicNativeAuthException catch (error) {
      _showError(error.message);
      if (error.code.toLowerCase() == 'senderror') {
        await _selectAlternateMethod();
      }
    } on Object {
      _showError('验证码发送失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_busy || _verificationKey.currentState?.validate() != true) return;
    setState(() => _busy = true);
    try {
      final callbackUri = await _authService.verifyCode(
          method: _method, code: _code.text.trim());
      if (!mounted) return;
      await _completeLogin(callbackUri);
    } on AcademicNativeAuthException catch (error) {
      _showError(error.message);
    } on Object {
      _showError('验证失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeLogin(Uri callbackUri) async {
    await _authService.installCookiesInWebView();
    if (!mounted) return;
    if (widget.destination == NativeLoginDestination.forum) {
      final result =
          await Navigator.of(context).push<ForumOAuthCompletionResult>(
        MaterialPageRoute(
          builder: (_) => ForumOAuthCompletionPage(callbackUri: callbackUri),
        ),
      );
      if (!mounted) return;
      if (result == ForumOAuthCompletionResult.loggedIn) {
        Navigator.of(context).pop(true);
      }
      return;
    }
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WebVpnOAuthCompletionPage(callbackUri: callbackUri),
      ),
    );
    if (completed == true && mounted) Navigator.of(context).pop(true);
  }

  String _methodHint(Map<AcademicVerificationMethod, String> methods) {
    final target = methods[_method];
    if (target == null || target.isEmpty) return '发送至学校统一认证中绑定的账号';
    return _method == AcademicVerificationMethod.wecom
        ? '发送至企业微信账号 $target'
        : '发送至手机号 $target';
  }

  Future<void> _selectVerificationMethod(
    AcademicVerificationMethod method,
  ) async {
    _countdownTimer?.cancel();
    final remaining =
        await _verificationDeliveryService.remainingCooldown(method);
    if (!mounted) return;
    setState(() => _method = method);
    _startCountdown(remaining);
  }

  Future<void> _selectAlternateMethod() async {
    final methods = _challenge?.methods.keys.toSet() ?? const {};
    if (methods.length < 2) return;
    final alternate = methods.firstWhere((method) => method != _method);
    await _selectVerificationMethod(alternate);
  }

  void _startCountdown(Duration remaining) {
    _countdownTimer?.cancel();
    final seconds = remaining.inSeconds;
    if (seconds <= 0) {
      if (mounted) setState(() => _countdown = 0);
      return;
    }
    setState(() => _countdown = seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _countdown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _countdown = 0);
        return;
      }
      setState(() => _countdown--);
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
