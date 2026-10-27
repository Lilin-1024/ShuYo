import 'package:flutter/material.dart';

import '../../../shared/theme/shuyo_theme.dart';

/// Matches the login form's surface and border while retaining floating labels.
InputDecoration recoveryInputDecoration(
  BuildContext context, {
  required String labelText,
  Widget? suffixIcon,
  String? counterText,
}) {
  final colors = context.shuyoColors;
  const radius = BorderRadius.all(Radius.circular(12));

  OutlineInputBorder outline(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: labelText,
    suffixIcon: suffixIcon,
    counterText: counterText,
    filled: true,
    fillColor: colors.surface,
    border: outline(colors.border),
    enabledBorder: outline(colors.border),
    disabledBorder: outline(colors.border),
    focusedBorder: outline(colors.accent, width: 1.4),
    errorBorder: outline(colors.danger),
    focusedErrorBorder: outline(colors.danger, width: 1.4),
  );
}
