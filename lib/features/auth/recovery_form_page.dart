import 'package:flutter/material.dart';

import '../../data/services/recovery_auth_service.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import 'recovery_final_page.dart';
import 'recovery_verification_page.dart';
import 'widgets/recovery_input_decoration.dart';

/// First step of the university's account recovery flows.
class RecoveryFormPage extends StatefulWidget {
  const RecoveryFormPage.resetPassword({super.key, this.service})
      : _resetPassword = true;

  const RecoveryFormPage.changePhone({super.key, this.service})
      : _resetPassword = false;

  final RecoveryAuthService? service;
  final bool _resetPassword;

  @override
  State<RecoveryFormPage> createState() => _RecoveryFormPageState();
}

class _RecoveryFormPageState extends State<RecoveryFormPage> {
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _identityId = TextEditingController();
  final _cardId = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _passwordVisible = false;
  bool _busy = false;
  late final RecoveryAuthService _service =
      widget.service ?? RecoveryAuthService();

  @override
  void initState() {
    super.initState();
    _passwordFocusNode.addListener(_onPasswordFocusChanged);
  }

  void _onPasswordFocusChanged() => setState(() {});

  Future<void> _submit() async {
    if (_busy) return;
    final username = _username.text.trim();
    final realName = _name.text.trim();
    final identityId = _identityId.text.trim();
    final cardId = _cardId.text.trim();
    final password = _password.text;
    if (username.isEmpty ||
        (widget._resetPassword
            ? realName.isEmpty || identityId.isEmpty || cardId.isEmpty
            : password.isEmpty)) {
      _showError('请填写完整信息');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    RecoveryChallenge? challenge;
    try {
      challenge = widget._resetPassword
          ? await _service.verifyResetInfo(
              username: username,
              realName: realName,
              identityID: identityId,
              cardID: cardId,
            )
          : await _service.verifyChangePhoneUser(
              username: username,
              password: password,
            );
    } on RecoveryAuthException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } catch (_) {
      if (!mounted) return;
      _showError('验证失败，请稍后重试');
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
    if (!mounted || challenge == null) return;
    final completed = await Navigator.of(context).push<bool>(
      shuyoRoute(
        builder: (_) => widget._resetPassword
            ? challenge!.methods.isEmpty
                ? RecoveryFinalPage.resetPassword(service: _service)
                : RecoveryVerificationPage.resetPassword(
                    methods: challenge.methods, service: _service)
            : RecoveryVerificationPage.changePhone(
                methods: challenge!.methods, service: _service),
      ),
    );
    if (mounted && completed == true && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _identityId.dispose();
    _cardId.dispose();
    _password.dispose();
    _passwordFocusNode.removeListener(_onPasswordFocusChanged);
    _passwordFocusNode.dispose();
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final resetPassword = widget._resetPassword;
    final fields = <Widget>[
      _field(
        label: '学/工号',
        controller: _username,
        autofillHints: const [AutofillHints.username],
      ),
      if (resetPassword) ...[
        _field(label: '姓名', controller: _name),
        _field(label: '证件号码', controller: _identityId),
        _field(
          label: '校园卡号',
          controller: _cardId,
          keyboardType: TextInputType.number,
          cardHelp: true,
          last: true,
        ),
      ] else
        _field(
          label: '密码',
          controller: _password,
          password: true,
          last: true,
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(resetPassword ? '重置密码' : '修改手机号')),
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
                      '验证身份',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      resetPassword
                          ? '请填写以下信息，验证你的上海大学账户。'
                          : '请登录上海大学账户，验证你的身份。',
                      style:
                          TextStyle(color: colors.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    for (var i = 0; i < fields.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      fields[i],
                    ],
                    if (resetPassword) ...[
                      const SizedBox(height: 16),
                      Text(
                        '请确保填写的信息与学校登记的信息一致。',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('下一步'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    Iterable<String>? autofillHints,
    TextInputType keyboardType = TextInputType.text,
    bool password = false,
    bool cardHelp = false,
    bool last = false,
  }) {
    final colors = context.shuyoColors;
    return TextFormField(
      controller: controller,
      focusNode: password ? _passwordFocusNode : null,
      keyboardType: password ? TextInputType.visiblePassword : keyboardType,
      obscureText: password && !_passwordVisible,
      autocorrect: false,
      enableSuggestions: !password,
      autofillHints: password ? const [AutofillHints.password] : autofillHints,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: recoveryInputDecoration(
        context,
        labelText: label,
        suffixIcon: password
            ? IgnorePointer(
                ignoring: !_passwordFocusNode.hasFocus,
                child: AnimatedOpacity(
                  opacity: _passwordFocusNode.hasFocus ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IconButton(
                    style: const ButtonStyle(
                      splashFactory: NoSplash.splashFactory,
                      overlayColor: WidgetStatePropertyAll(Colors.transparent),
                    ),
                    tooltip: _passwordVisible ? '隐藏密码' : '显示密码',
                    onPressed: () => setState(
                      () => _passwordVisible = !_passwordVisible,
                    ),
                    icon: Icon(
                      _passwordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              )
            : cardHelp
                ? IconButton(
                    tooltip: '校园卡号说明',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('校园卡号'),
                        content: const Text('卡号在校园卡人像面左下角。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('知道了'),
                          ),
                        ],
                      ),
                    ),
                    icon: Icon(
                      Icons.help_outline,
                      color: colors.textTertiary,
                    ),
                  )
                : null,
      ),
    );
  }
}
