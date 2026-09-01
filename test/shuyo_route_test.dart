import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/shared/navigation/shuyo_route.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('uses the native iOS route with swipe-back support', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final route = shuyoRoute<void>(builder: (_) => const SizedBox());

    expect(route, isA<CupertinoPageRoute<void>>());
  });

  test('keeps the existing custom route on Android', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final route = shuyoRoute<void>(builder: (_) => const SizedBox());

    expect(route, isA<PageRouteBuilder<void>>());
  });
}
