import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/widgets/wecom_icon.dart';

/// 企业微信登录二维码，保持与确认链接一致并使用主题颜色。
class WeComLoginQr extends StatelessWidget {
  const WeComLoginQr({
    super.key,
    required this.confirmUrl,
    required this.foreground,
    required this.background,
  });

  final String confirmUrl;
  final Color foreground;
  final Color background;

  static const double _size = 220;
  static const double _padding = 20;

  @override
  Widget build(BuildContext context) {
    final eyeStyle = QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: foreground,
    );
    final dataModuleStyle = QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.circle,
      color: foreground,
    );
    return SizedBox.square(
      dimension: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          QrImageView(
            data: confirmUrl,
            size: _size,
            padding: const EdgeInsets.all(_padding),
            backgroundColor: background,
            errorCorrectionLevel: QrErrorCorrectLevel.H,
            gapless: false,
            eyeStyle: eyeStyle,
            dataModuleStyle: dataModuleStyle,
            semanticsLabel: '企业微信登录二维码',
          ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(5),
              ),
              child: SizedBox.square(
                dimension: 36,
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(color: foreground),
                    child: const WeComIcon(size: 30),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
