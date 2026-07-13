import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lehu_client/app/lehu_app.dart';

void main() {
  testWidgets('app shows startup loading state', (tester) async {
    await tester.pumpWidget(const LehuApp());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
