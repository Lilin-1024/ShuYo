import 'package:flutter/services.dart';

class EmojiRecentStore {
  const EmojiRecentStore._();

  static const _channel = MethodChannel('cn.edu.shu.lehu_client/emoji_recents');
  static const _maxRecent = 28;
  static List<String> _memoryFallback = const [];

  static Future<List<String>> load() async {
    try {
      final result = await _channel.invokeListMethod<String>(
        'getEmojiRecents',
      );
      return result ?? _memoryFallback;
    } on MissingPluginException {
      return _memoryFallback;
    }
  }

  static Future<List<String>> record(String shortcode) async {
    final current = await load();
    final next = [
      shortcode,
      ...current.where((item) => item != shortcode),
    ].take(_maxRecent).toList(growable: false);
    _memoryFallback = next;
    try {
      await _channel.invokeMethod<void>('setEmojiRecents', {
        'shortcodes': next,
      });
    } on MissingPluginException {
      // Tests and unsupported platforms still get session-local recents.
    }
    return next;
  }
}
