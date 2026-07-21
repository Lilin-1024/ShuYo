import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/app/lehu_app.dart';

void main() {
  testWidgets('app shows startup icon state', (tester) async {
    await tester.pumpWidget(const LehuApp());

    expect(find.byType(CircularProgressIndicator), findsNothing);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/icon_clear_blue.png',
    );
  });
}
