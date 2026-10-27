import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/recovery_auth_service.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import 'widgets/recovery_input_decoration.dart';

/// The final form shares the session established by the first recovery page.
class RecoveryFinalPage extends StatefulWidget {
  const RecoveryFinalPage.resetPassword({super.key, required this.service})
      : _resetPassword = true;

  const RecoveryFinalPage.changePhone({super.key, required this.service})
      : _resetPassword = false;

  final RecoveryAuthService service;
  final bool _resetPassword;

  @override
  State<RecoveryFinalPage> createState() => _RecoveryFinalPageState();
}

class _RecoveryFinalPageState extends State<RecoveryFinalPage> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _passwordVisible = false;
  bool _confirmationVisible = false;
  bool _sending = false;
  bool _submitting = false;
  bool _completed = false;
  bool _allowPop = false;
  String? _sentPhone;
  Timer? _countdown;
  int _secondsRemaining = 0;

  bool get _busy => _sending || _submitting;

  int _passwordScore(String password) {
    return [
      password.length >= 8,
      RegExp(r'[a-z]').hasMatch(password) &&
          RegExp(r'[A-Z]').hasMatch(password),
      RegExp(r'\d').hasMatch(password),
      RegExp(r'''[~!"#$%&'()*+,\-./:;=?@\[\]^_`{|} \\]''').hasMatch(password),
    ].where((condition) => condition).length;
  }

  bool _strongEnough(String password) => _passwordScore(password) >= 3;

  bool _validPhone(String phone) => RegExp(r'^1[3-9]\d{9}$').hasMatch(phone);

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _sendCode() async {
    if (_busy || _secondsRemaining > 0) return;
    final phone = _phone.text.trim();
    if (!_validPhone(phone)) {
      _showMessage('请输入有效的手机号');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      await widget.service.sendNewPhoneCode(phone: phone);
      if (!mounted) return;
      _sentPhone = phone;
      _code.clear();
      setState(() => _secondsRemaining = 60);
      _countdown?.cancel();
      _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() => _secondsRemaining--);
        if (_secondsRemaining <= 0) timer.cancel();
      });
      _showMessage('验证码已发送');
    } on RecoveryAuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('验证码发送失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _completed) return;
    final password = _password.text;
    final confirmation = _confirmation.text;
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (widget._resetPassword) {
      if (password.isEmpty || confirmation.isEmpty) {
        _showMessage('请填写完整信息');
        return;
      }
      if (!_strongEnough(password)) {
        _showMessage('密码强度不足，请按提示设置密码');
        return;
      }
      if (password != confirmation) {
        _showMessage('两次输入的密码不一致');
        return;
      }
    } else {
      if (!_validPhone(phone)) {
        _showMessage('请输入有效的手机号');
        return;
      }
      if (_sentPhone != phone) {
        _showMessage('请先向当前手机号发送验证码');
        return;
      }
      if (code.isEmpty) {
        _showMessage('请输入验证码');
        return;
      }
    }
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      if (widget._resetPassword) {
        await widget.service.resetPassword(
          password: password,
          confirmPassword: confirmation,
        );
      } else {
        await widget.service.submitNewPhone(phone: phone, code: code);
      }
      if (!mounted) return;
      _password.clear();
      _confirmation.clear();
      _code.clear();
      _countdown?.cancel();
      setState(() => _completed = true);
    } on RecoveryAuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('提交失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted || !_completed) return;
    final completed = await Navigator.of(context).push<bool>(
      shuyoRoute(
        builder: (_) => _RecoverySuccessPage(
          resetPassword: widget._resetPassword,
        ),
      ),
    );
    if (mounted && completed == true) _finish();
  }

  void _finish() {
    if (_allowPop) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _password.dispose();
    _confirmation.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final resetPassword = widget._resetPassword;
    final title = resetPassword ? '重置密码' : '修改手机号';
    return PopScope(
      canPop: !_busy && (!_completed || _allowPop),
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: SingleChildScrollView(
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
                        resetPassword ? '设置新密码' : '绑定新手机号',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: colors.textPrimary),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        resetPassword
                            ? '请设置你的上海大学账户新密码。'
                            : '请输入新手机号，并使用收到的验证码完成绑定。',
                        style: TextStyle(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (resetPassword) ...[
                        _passwordField(
                          label: '新密码',
                          controller: _password,
                          visible: _passwordVisible,
                          onVisibility: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _password,
                          builder: (context, value, _) =>
                              _passwordStrength(_passwordScore(value.text)),
                        ),
                        const SizedBox(height: 16),
                        _passwordField(
                          label: '确认新密码',
                          controller: _confirmation,
                          visible: _confirmationVisible,
                          last: true,
                          onVisibility: () => setState(
                            () => _confirmationVisible = !_confirmationVisible,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '密码需满足以下四项中的至少三项：不少于 8 位、同时包含大小写字母、包含数字、包含特殊字符。',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.textSecondary,
                                    height: 1.5,
                                  ),
                        ),
                      ] else ...[
                        TextFormField(
                          controller: _phone,
                          enabled: !_busy,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          maxLength: 11,
                          textInputAction: TextInputAction.next,
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                          onChanged: (value) {
                            if (value != _sentPhone) {
                              _sentPhone = null;
                              _code.clear();
                            }
                          },
                          decoration: recoveryInputDecoration(
                            context,
                            labelText: '新手机号',
                            counterText: '',
                          ).copyWith(
                            prefixIcon: Semantics(
                              label: '中国大陆区号加八十六',
                              child: ExcludeSemantics(
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 16,
                                    right: 12,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('🇨🇳'),
                                      const SizedBox(width: 6),
                                      Text(
                                        '+86',
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _code,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          textInputAction: TextInputAction.done,
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                          decoration: recoveryInputDecoration(
                            context,
                            labelText: '验证码',
                            suffixIcon: TextButton(
                              onPressed: _busy || _secondsRemaining > 0
                                  ? null
                                  : _sendCode,
                              child: _sending
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(_secondsRemaining > 0
                                      ? '重发 ${_secondsRemaining}s'
                                      : '发送验证码'),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy || _completed ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(resetPassword ? '重置密码' : '确认修改'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _passwordStrength(int score) {
    final colors = context.shuyoColors;
    final label = switch (score) {
      <= 1 => '弱',
      <= 3 => '中',
      _ => '强',
    };
    return Semantics(
      label: '密码强度：$label',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                text: '密码强度：',
                style: TextStyle(color: colors.textSecondary),
                children: [
                  TextSpan(text: label, style: TextStyle(color: colors.accent))
                ],
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var index = 0; index < 4; index++) ...[
                  if (index > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      key: ValueKey('password-strength-segment-$index'),
                      height: 6,
                      decoration: BoxDecoration(
                        color: index < score ? colors.accent : colors.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool visible,
    required VoidCallback onVisibility,
    bool last = false,
  }) {
    return TextFormField(
      controller: controller,
      enabled: !_busy,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: const [AutofillHints.newPassword],
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: recoveryInputDecoration(
        context,
        labelText: label,
        suffixIcon: IconButton(
          tooltip: visible ? '隐藏密码' : '显示密码',
          onPressed: _busy ? null : onVisibility,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: context.shuyoColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _RecoverySuccessPage extends StatefulWidget {
  const _RecoverySuccessPage({required this.resetPassword});

  final bool resetPassword;

  @override
  State<_RecoverySuccessPage> createState() => _RecoverySuccessPageState();
}

class _RecoverySuccessPageState extends State<_RecoverySuccessPage> {
  bool _allowPop = false;

  void _finish() {
    if (_allowPop) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return PopScope(
      canPop: _allowPop,
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 55, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.resetPassword ? '密码重置成功' : '手机号修改成功',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          widget.resetPassword
                              ? '你现在可以使用新密码登录。'
                              : '你的认证手机号已更新。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: colors.textSecondary, height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _finish,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
