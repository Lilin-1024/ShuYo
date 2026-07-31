import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/common.dart';

class ForumReadPosition {
  const ForumReadPosition({
    required this.offset,
    this.updatedAt,
  });

  final double offset;
  final DateTime? updatedAt;

  JsonMap toJson({DateTime? updatedAt}) {
    return {
      'offset': offset,
      'updated_at':
          (updatedAt ?? this.updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory ForumReadPosition.fromJson(JsonMap json) {
    return ForumReadPosition(
      offset: _doubleValue(json['offset']),
      updatedAt: dateValue(json['updated_at']),
    );
  }

  static double _doubleValue(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }
}

class ForumReadPositionStore {
  const ForumReadPositionStore._();

  static const _prefix = 'forum.readPosition.v1';
  static const maxAge = Duration(days: 30);
  static const maxCount = 300;

  static String topicKey({
    required String username,
    required int topicId,
  }) {
    return '$_prefix.topic.${_part(username)}.$topicId';
  }

  static Future<ForumReadPosition?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await _cleanup(prefs);
    final value = prefs.getString(key);
    if (value == null || value.isEmpty) {
      return null;
    }
    final position = _parsePosition(value);
    if (position == null || _isExpired(position)) {
      await prefs.remove(key);
      return null;
    }
    return position;
  }

  static Future<void> save(String key, double offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(ForumReadPosition(offset: offset).toJson()),
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

  static Future<void> _cleanup(SharedPreferences prefs) async {
    final records = <_ReadPositionRecord>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) {
        continue;
      }
      final value = prefs.getString(key);
      if (value == null || value.isEmpty) {
        await prefs.remove(key);
        continue;
      }
      final position = _parsePosition(value);
      if (position == null || _isExpired(position)) {
        await prefs.remove(key);
        continue;
      }
      records.add(
        _ReadPositionRecord(
          key: key,
          updatedAt:
              position.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
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

  static ForumReadPosition? _parsePosition(String value) {
    try {
      final json = jsonDecode(value);
      return json is JsonMap ? ForumReadPosition.fromJson(json) : null;
    } on Object {
      return null;
    }
  }

  static bool _isExpired(ForumReadPosition position) {
    final updatedAt = position.updatedAt;
    if (updatedAt == null) {
      return true;
    }
    return DateTime.now().difference(updatedAt) > maxAge;
  }

  static String _part(String value) {
    return Uri.encodeComponent(value.trim().toLowerCase());
  }
}

class _ReadPositionRecord {
  const _ReadPositionRecord({
    required this.key,
    required this.updatedAt,
  });

  final String key;
  final DateTime updatedAt;
}
