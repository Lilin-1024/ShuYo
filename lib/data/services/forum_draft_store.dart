import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/common.dart';
import '../models/composer.dart';

class ForumComposerDraft {
  const ForumComposerDraft({
    this.title = '',
    this.raw = '',
    this.categoryId,
    this.replyToPostNumber,
    this.images = const [],
    this.updatedAt,
  });

  final String title;
  final String raw;
  final int? categoryId;
  final int? replyToPostNumber;
  final List<UploadedImage> images;
  final DateTime? updatedAt;

  bool get hasContent {
    return title.trim().isNotEmpty ||
        raw.trim().isNotEmpty ||
        images.isNotEmpty;
  }

  JsonMap toJson({DateTime? updatedAt}) {
    return {
      'title': title,
      'raw': raw,
      'category_id': categoryId,
      'reply_to_post_number': replyToPostNumber,
      'updated_at':
          (updatedAt ?? this.updatedAt ?? DateTime.now()).toIso8601String(),
      'images': images.map(_imageToJson).toList(),
    };
  }

  factory ForumComposerDraft.fromJson(JsonMap json) {
    final imagesJson = json['images'];
    return ForumComposerDraft(
      title: stringValue(json['title']),
      raw: stringValue(json['raw']),
      categoryId: _nullableInt(json['category_id']),
      replyToPostNumber: _nullableInt(json['reply_to_post_number']),
      updatedAt: dateValue(json['updated_at']),
      images: imagesJson is List
          ? imagesJson
              .whereType<JsonMap>()
              .map(_imageFromJson)
              .whereType<UploadedImage>()
              .toList(growable: false)
          : const [],
    );
  }

  static JsonMap _imageToJson(UploadedImage image) {
    return {
      'url': image.url,
      'short_url': image.shortUrl,
      'filename': image.filename,
      'width': image.width,
      'height': image.height,
      'thumbnail_width': image.thumbnailWidth,
      'thumbnail_height': image.thumbnailHeight,
    };
  }

  static UploadedImage? _imageFromJson(JsonMap json) {
    final url = stringValue(json['url']);
    final shortUrl = stringValue(json['short_url']);
    if (url.isEmpty && shortUrl.isEmpty) {
      return null;
    }
    return UploadedImage(
      url: url,
      shortUrl: shortUrl.isEmpty ? url : shortUrl,
      filename: stringValue(json['filename'], 'image.jpg'),
      width: intValue(json['width']),
      height: intValue(json['height']),
      thumbnailWidth: intValue(json['thumbnail_width']),
      thumbnailHeight: intValue(json['thumbnail_height']),
    );
  }

  static int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    final parsed = intValue(value);
    return parsed == 0 ? null : parsed;
  }
}

class ForumDraftStore {
  const ForumDraftStore._();

  static const _prefix = 'forum.composerDraft.v1';
  static const maxAge = Duration(days: 15);
  static const maxCount = 50;

  static String newTopicKey(String username) {
    return '$_prefix.topic.new.${_part(username)}';
  }

  static String newPrivateMessageKey(String username, String recipient) {
    return '$_prefix.private.new.${_part(username)}.${_part(recipient)}';
  }

  static String topicReplyKey({
    required String username,
    required int topicId,
    required int? replyToPostNumber,
  }) {
    return '$_prefix.topic.reply.${_part(username)}.$topicId.'
        '${replyToPostNumber ?? 'root'}';
  }

  static String privateMessageReplyKey({
    required String username,
    required int topicId,
  }) {
    return '$_prefix.private.reply.${_part(username)}.$topicId';
  }

  static Future<ForumComposerDraft?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await _cleanup(prefs);
    final value = prefs.getString(key);
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(value);
      if (json is! JsonMap) {
        await prefs.remove(key);
        return null;
      }
      final draft = ForumComposerDraft.fromJson(json);
      if (!draft.hasContent || _isExpired(draft)) {
        await prefs.remove(key);
        return null;
      }
      return draft;
    } on Object {
      await prefs.remove(key);
      return null;
    }
  }

  static Future<void> save(String key, ForumComposerDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    if (!draft.hasContent) {
      await prefs.remove(key);
      await _cleanup(prefs);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode(draft.toJson(updatedAt: DateTime.now())),
    );
    await _cleanup(prefs);
  }

  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  static Future<void> cleanup() async {
    final prefs = await SharedPreferences.getInstance();
    await _cleanup(prefs);
  }

  static String _part(String value) {
    return Uri.encodeComponent(value.trim().toLowerCase());
  }

  static Future<void> _cleanup(SharedPreferences prefs) async {
    final records = <_DraftRecord>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) {
        continue;
      }
      final value = prefs.getString(key);
      if (value == null || value.isEmpty) {
        await prefs.remove(key);
        continue;
      }
      final draft = _parseDraft(value);
      if (draft == null || !draft.hasContent || _isExpired(draft)) {
        await prefs.remove(key);
        continue;
      }
      records.add(
        _DraftRecord(
          key: key,
          updatedAt: draft.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
    if (records.length <= maxCount) {
      return;
    }
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final record in records.skip(maxCount)) {
      await prefs.remove(record.key);
    }
  }

  static ForumComposerDraft? _parseDraft(String value) {
    try {
      final json = jsonDecode(value);
      return json is JsonMap ? ForumComposerDraft.fromJson(json) : null;
    } on Object {
      return null;
    }
  }

  static bool _isExpired(ForumComposerDraft draft) {
    final updatedAt = draft.updatedAt;
    if (updatedAt == null) {
      return true;
    }
    return DateTime.now().difference(updatedAt) > maxAge;
  }
}

class _DraftRecord {
  const _DraftRecord({
    required this.key,
    required this.updatedAt,
  });

  final String key;
  final DateTime updatedAt;
}
