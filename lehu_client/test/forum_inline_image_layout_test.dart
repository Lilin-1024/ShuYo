import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/shared/widgets/forum_cooked_content.dart';
import 'package:shuyo/shared/widgets/forum_inline_image_layout.dart';
import 'package:shuyo/shared/widgets/forum_network_image.dart';

void main() {
  group('ForumInlineImageLayout', () {
    test('keeps medium images at their natural display size', () {
      final size = ForumInlineImageLayout.displaySize(
        availableWidth: 350,
        sourceSize: const Size(200, 100),
        fallbackHeight: 160,
      );

      expect(size, const Size(200, 100));
    });

    test('enlarges a small image until its short side is visible', () {
      final size = ForumInlineImageLayout.displaySize(
        availableWidth: 350,
        sourceSize: const Size(40, 20),
        fallbackHeight: 160,
      );

      expect(size, const Size(192, 96));
    });

    test('limits large images by content width without distortion', () {
      final size = ForumInlineImageLayout.displaySize(
        availableWidth: 350,
        sourceSize: const Size(690, 431),
        fallbackHeight: 160,
      );

      expect(size.width, 350);
      expect(size.height, closeTo(350 / (690 / 431), 0.001));
      expect(size.aspectRatio, closeTo(690 / 431, 0.001));
    });

    test('limits portrait images by the maximum height', () {
      final size = ForumInlineImageLayout.displaySize(
        availableWidth: 500,
        sourceSize: const Size(600, 1200),
        fallbackHeight: 160,
      );

      expect(size, const Size(180, 360));
    });

    test('uses a bounded placeholder when dimensions are unknown', () {
      final size = ForumInlineImageLayout.displaySize(
        availableWidth: 400,
        sourceSize: null,
        fallbackHeight: 130,
      );

      expect(size, const Size(240, 130));
    });
  });

  testWidgets('cooked content uses responsive inline image dimensions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            child: ForumCookedContent(
              cooked: '<img src="https://example.com/photo.jpg" '
                  'width="40" height="20">',
              textColor: Colors.black,
              onOpenImage: (_, __) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ForumNetworkImage), findsOneWidget);
    expect(tester.getSize(find.byType(ForumNetworkImage)), const Size(192, 96));
  });

  testWidgets('cooked emoji images stay inline at the current text size',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            child: ForumCookedContent(
              cooked: '<p>before <img class="emoji" '
                  'src="https://example.com/custom-campus.png" '
                  'alt=":custom_campus:" width="20" height="20"> after</p>',
              textColor: Colors.black,
              onOpenImage: (_, __) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ForumNetworkImage), findsOneWidget);
    final size = tester.getSize(find.byType(ForumNetworkImage));
    expect(size.width, closeTo(17.92, 0.01));
    expect(size.height, closeTo(17.92, 0.01));
  });
}
