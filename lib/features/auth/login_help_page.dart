import 'package:flutter/material.dart';

import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import 'recovery_form_page.dart';

/// Entry points to the university's account recovery services.
class LoginHelpPage extends StatelessWidget {
  const LoginHelpPage({super.key});

  Future<void> _openRecovery(BuildContext context, Widget page) async {
    final completed = await Navigator.of(context).push<bool>(
      shuyoRoute(builder: (_) => page),
    );
    if (context.mounted &&
        completed == true &&
        Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Scaffold(
      appBar: AppBar(title: const Text('登录问题')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '如果你遇到密码错误、无法完成两步验证等问题，可以尝试以下选项。',
                      style:
                          TextStyle(color: colors.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading:
                          Icon(Icons.lock_reset, color: colors.textSecondary),
                      title: const Text('重置密码'),
                      subtitle: Text('忘记密码时，通过身份验证重置',
                          style: TextStyle(color: colors.textSecondary)),
                      trailing: Icon(Icons.chevron_right,
                          size: 18, color: colors.textSecondary),
                      onTap: () => _openRecovery(
                        context,
                        const RecoveryFormPage.resetPassword(),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(Icons.phone_android,
                          color: colors.textSecondary),
                      title: const Text('修改手机号'),
                      subtitle: Text('更换用于身份认证的手机号码',
                          style: TextStyle(color: colors.textSecondary)),
                      trailing: Icon(Icons.chevron_right,
                          size: 18, color: colors.textSecondary),
                      onTap: () => _openRecovery(
                        context,
                        const RecoveryFormPage.changePhone(),
                      ),
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
}
