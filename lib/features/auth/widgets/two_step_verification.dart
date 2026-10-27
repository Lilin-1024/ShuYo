import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/shuyo_theme.dart';
import '../../../shared/widgets/wecom_icon.dart';

/// Shared presentation for the login and account recovery verification steps.
/// The caller owns the code, verification state, and all network operations.
class TwoStepVerification extends StatelessWidget {
  const TwoStepVerification({
    super.key,
    required this.methods,
    required this.selectedMethod,
    required this.codeController,
    required this.codeFocusNode,
    required this.onMethodChanged,
    required this.onSendCode,
    required this.onVerifyCode,
    this.busy = false,
    this.sending = false,
    this.verifying = false,
    this.countdown = 0,
    this.digitsOnly = false,
  });

  final Map<String, String> methods;
  final String selectedMethod;
  final TextEditingController codeController;
  final FocusNode codeFocusNode;
  final ValueChanged<String> onMethodChanged;
  final VoidCallback onSendCode;
  final VoidCallback onVerifyCode;
  final bool busy;
  final bool sending;
  final bool verifying;
  final int countdown;
  final bool digitsOnly;

  String _methodLabel(String method) => switch (method) {
        'wecom' => '企业微信',
        'sms' => '手机号',
        _ => method,
      };

  String _methodHint() {
    if (selectedMethod == 'wecom') return '发送至企业微信';
    var target = methods[selectedMethod];
    if (target == null || target.isEmpty) return '发送至学校统一认证中绑定的账号';
    if (selectedMethod == 'sms') {
      target = target.replaceAllMapped(
        RegExp(r'(?<!\d)1\d{10}(?!\d)'),
        (match) {
          final number = match.group(0)!;
          return '${number.substring(0, 3)}****${number.substring(7)}';
        },
      );
    }
    return '发送至${_methodLabel(selectedMethod)} $target';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final orderedMethods = methods.keys.toList()
      ..sort((a, b) {
        int order(String method) => switch (method) {
              'wecom' => 0,
              'sms' => 1,
              _ => 2,
            };
        return order(a).compareTo(order(b));
      });
    return Form(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 55, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '二步验证',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          '验证码将${_methodHint()}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ),
                      if (orderedMethods.length > 1) ...[
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Keep the labels legible at large text sizes on
                            // narrow screens, allowing horizontal scrolling.
                            final minWidth = orderedMethods.length *
                                (52 +
                                    MediaQuery.textScalerOf(context).scale(64));
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: math.max(constraints.maxWidth, minWidth),
                                child: SegmentedButton<String>(
                                  expandedInsets: EdgeInsets.zero,
                                  showSelectedIcon: false,
                                  segments: [
                                    for (final method in orderedMethods)
                                      ButtonSegment(
                                        value: method,
                                        icon: switch (method) {
                                          'wecom' => const WeComIcon(size: 18),
                                          'sms' => const Icon(
                                              Icons.phone_android,
                                              size: 18),
                                          _ => null,
                                        },
                                        label: Text(_methodLabel(method)),
                                      ),
                                  ],
                                  selected: {selectedMethod},
                                  onSelectionChanged: busy
                                      ? null
                                      : (value) => onMethodChanged(value.first),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 20),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 8),
                          child: TextFormField(
                            controller: codeController,
                            focusNode: codeFocusNode,
                            enabled: !busy,
                            keyboardType: TextInputType.number,
                            inputFormatters: digitsOnly
                                ? [FilteringTextInputFormatter.digitsOnly]
                                : null,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            maxLength: 6,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => onVerifyCode(),
                            decoration: InputDecoration(
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              hintText: '验证码',
                              counterText: '',
                              suffixIcon: TextButton(
                                onPressed:
                                    busy || countdown > 0 ? null : onSendCode,
                                style: TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  splashFactory: NoSplash.splashFactory,
                                ),
                                child: sending
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : Text(countdown > 0
                                        ? '重发 ${countdown}s'
                                        : '发送验证码'),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: busy ? null : onVerifyCode,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: verifying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('完成验证'),
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
