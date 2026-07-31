import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'emoji_text.dart';

class ForumTitleRules {
  const ForumTitleRules._();

  static const disallowedEmojiMessage = '标题不能包含 Emoji';

  static final _knownEmojiBaseRunes = <int>{
    for (final entry in EmojiText.entries)
      if (entry.value.runes.isNotEmpty &&
          !_isAsciiKeycapBase(entry.value.runes.first))
        entry.value.runes.first,
  };

  static String sanitize(String value) {
    return _removeUnicodeEmoji(EmojiText.removeKnownShortcodes(value));
  }

  static bool containsDisallowedEmoji(String value) {
    return sanitize(value) != value;
  }

  static TextEditingValue sanitizeEditingValue(TextEditingValue value) {
    final sanitized = sanitize(value.text);
    if (sanitized == value.text) {
      return value;
    }
    final selection = value.selection;
    if (!selection.isValid) {
      return value.copyWith(
        text: sanitized,
        selection: TextSelection.collapsed(offset: sanitized.length),
        composing: TextRange.empty,
      );
    }
    final baseOffset = _safeOffset(selection.baseOffset, value.text.length);
    final extentOffset = _safeOffset(selection.extentOffset, value.text.length);
    final base = sanitize(value.text.substring(0, baseOffset)).length;
    final extent = sanitize(value.text.substring(0, extentOffset)).length;
    return value.copyWith(
      text: sanitized,
      selection: TextSelection(
        baseOffset: math.min(base, sanitized.length),
        extentOffset: math.min(extent, sanitized.length),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
      composing: TextRange.empty,
    );
  }

  static int _safeOffset(int offset, int length) {
    return offset.clamp(0, length).toInt();
  }

  static String _removeUnicodeEmoji(String value) {
    if (value.isEmpty) {
      return value;
    }
    final runes = value.runes.toList(growable: false);
    final buffer = StringBuffer();
    for (var index = 0; index < runes.length; index++) {
      final keycapLength = _keycapSequenceLength(runes, index);
      if (keycapLength > 0) {
        index += keycapLength - 1;
        continue;
      }
      final rune = runes[index];
      if (_isEmojiBaseAt(runes, index)) {
        index = _skipEmojiContinuation(runes, index);
        continue;
      }
      if (_isEmojiContinuation(rune)) {
        continue;
      }
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  static int _skipEmojiContinuation(List<int> runes, int index) {
    var cursor = index;
    while (cursor + 1 < runes.length) {
      final next = runes[cursor + 1];
      if (next == _zeroWidthJoiner && cursor + 2 < runes.length) {
        cursor += 2;
        continue;
      }
      if (_isEmojiContinuation(next)) {
        cursor++;
        continue;
      }
      break;
    }
    return cursor;
  }

  static int _keycapSequenceLength(List<int> runes, int index) {
    final rune = runes[index];
    if (!_isKeycapBase(rune) || index + 1 >= runes.length) {
      return 0;
    }
    if (runes[index + 1] == _combiningEnclosingKeycap) {
      return 2;
    }
    if (index + 2 < runes.length &&
        runes[index + 1] == _variationSelector16 &&
        runes[index + 2] == _combiningEnclosingKeycap) {
      return 3;
    }
    return 0;
  }

  static bool _isKeycapBase(int rune) {
    return rune == 0x23 || rune == 0x2A || (rune >= 0x30 && rune <= 0x39);
  }

  static bool _isEmojiBaseAt(List<int> runes, int index) {
    final rune = runes[index];
    if (rune >= 0x1F000 && rune <= 0x1FAFF) {
      return true;
    }
    if (_knownEmojiBaseRunes.contains(rune)) {
      return true;
    }
    return index + 1 < runes.length &&
        runes[index + 1] == _variationSelector16 &&
        _canUseEmojiPresentation(rune);
  }

  static bool _canUseEmojiPresentation(int rune) {
    return rune == 0x00A9 ||
        rune == 0x00AE ||
        rune == 0x3030 ||
        rune == 0x303D ||
        rune == 0x3297 ||
        rune == 0x3299 ||
        (rune >= 0x2000 && rune <= 0x2BFF);
  }

  static bool _isEmojiContinuation(int rune) {
    return rune == _zeroWidthJoiner ||
        rune == _variationSelector16 ||
        rune == _combiningEnclosingKeycap ||
        (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
        (rune >= 0xE0020 && rune <= 0xE007F);
  }

  static const _zeroWidthJoiner = 0x200D;
  static const _variationSelector16 = 0xFE0F;
  static const _combiningEnclosingKeycap = 0x20E3;

  static bool _isAsciiKeycapBase(int rune) {
    return rune == 0x23 || rune == 0x2A || (rune >= 0x30 && rune <= 0x39);
  }
}
