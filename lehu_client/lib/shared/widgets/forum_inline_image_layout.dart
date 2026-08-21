import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class ForumInlineImageLayout {
  const ForumInlineImageLayout._();

  static const double minimumVisibleSide = 96;
  static const double maximumHeight = 360;
  static const double fallbackWidth = 240;

  static Size displaySize({
    required double availableWidth,
    required Size? sourceSize,
    required double fallbackHeight,
  }) {
    final maxWidth = _positiveFinite(availableWidth);
    if (maxWidth == null) {
      return Size.zero;
    }

    final sourceWidth = _positiveFinite(sourceSize?.width);
    final sourceHeight = _positiveFinite(sourceSize?.height);
    if (sourceWidth == null || sourceHeight == null) {
      return Size(
        math.min(maxWidth, fallbackWidth),
        fallbackHeight.clamp(minimumVisibleSide, maximumHeight).toDouble(),
      );
    }

    final maximumScale = math.min(
      maxWidth / sourceWidth,
      maximumHeight / sourceHeight,
    );
    final naturalScale = math.min(1.0, maximumScale);
    final minimumScale =
        minimumVisibleSide / math.min(sourceWidth, sourceHeight);
    final scale = math.max(
      naturalScale,
      math.min(minimumScale, maximumScale),
    );
    return Size(sourceWidth * scale, sourceHeight * scale);
  }

  static double? _positiveFinite(double? value) {
    if (value == null || !value.isFinite || value <= 0) {
      return null;
    }
    return value;
  }
}
