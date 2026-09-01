import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/app/shuyo_app.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';

void main() {
  testWidgets('app shows startup icon state', (tester) async {
    await tester.pumpWidget(const ShuYoApp());

    expect(find.byType(CircularProgressIndicator), findsNothing);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/icon_clear_blue.png',
    );
  });

  testWidgets('app uses the initial dark theme for startup loading',
      (tester) async {
    await tester.pumpWidget(
      const ShuYoApp(initialThemeId: ShuYoThemes.systemDarkId),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(
        (image.image as AssetImage).assetName, 'assets/images/icon_clear.png');
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFF0D0D0D),
    );
  });
}
