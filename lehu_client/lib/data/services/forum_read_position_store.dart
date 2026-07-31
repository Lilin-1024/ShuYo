import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/common.dart';

class ForumReadPosition {
  const ForumReadPosition({
    required this.offset,
    this.anchorPostNumber,
    this.anchorDelta = 0,
    this.bottomDistance,
    this.updatedAt,
  });

  final double offset;
  final int? anchorPostNumber;
  final double anchorDelta;
  final double? bottomDistance;
  final DateTime? updatedAt;

  JsonMap toJson({DateTime? updatedAt}) {
    return {
      'offset': offset,
      if (anchorPostNumber != null) 'anchor_post_number': anchorPostNumber,
      'anchor_delta': anchorDelta,
      if (bottomDistance != null) 'bottom_distance': bottomDistance,
      'updated_at':
          (updatedAt ?? this.updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory ForumReadPosition.fromJson(JsonMap json) {
    return ForumReadPosition(
      offset: _doubleValue(json['offset']),
      anchorPostNumber: _intValue(json['anchor_post_number']),
      anchorDelta: _doubleValue(json['anchor_delta']),
      bottomDistance: _nullableDoubleValue(json['bottom_distance']),
      updatedAt: dateValue(json['updated_at']),
    );
  }

  static int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double? _nullableDoubleValue(Object? value) {
    if (value == null) {
      return null;
    }
    return _doubleValue(value);
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

  static const _prefix = 'forum.readPosition.v4';
  static const _legacyPrefixes = [
    'forum.readPosition.v1',
    'forum.readPosition.v2',
    'forum.readPosition.v3',
  ];
  static const _recentSaveMaxAge = Duration(seconds: 8);
  static const maxAge = Duration(days: 30);
  static const maxCount = 300;
  static final _recentSaves = <String, ForumReadPosition>{};

  static String topicKey({
    required String username,
    required int topicId,
  }) {
    return '$_prefix.topic.${_part(username)}.$topicId';
  }

  static Future<ForumReadPosition?> load(String key) async {
    final recent = _recentSaves[key];
    if (recent != null) {
      if (_isExpired(recent) || !_isRecentSave(recent)) {
        _recentSaves.remove(key);
      } else {
        return recent;
      }
    }
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
    _recentSaves[key] = position;
    return position;
  }

  static Future<void> save(
    String key,
    double offset, {
    int? anchorPostNumber,
    double anchorDelta = 0,
    double? bottomDistance,
  }) async {
    final position = ForumReadPosition(
      offset: offset,
      anchorPostNumber: anchorPostNumber,
      anchorDelta: anchorDelta,
      bottomDistance: bottomDistance,
      updatedAt: DateTime.now(),
    );
    _recentSaves[key] = position;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(position.toJson()),
    );
    await _cleanup(prefs);
  }

  static Future<void> remove(String key) async {
    _recentSaves.remove(key);
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
      if (_legacyPrefixes.any((prefix) => key.startsWith(prefix))) {
        _recentSaves.remove(key);
        await prefs.remove(key);
        continue;
      }
      if (!key.startsWith(_prefix)) {
        continue;
      }
      final value = prefs.getString(key);
      if (value == null || value.isEmpty) {
        _recentSaves.remove(key);
        await prefs.remove(key);
        continue;
      }
      final position = _parsePosition(value);
      if (position == null || _isExpired(position)) {
        _recentSaves.remove(key);
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
      _recentSaves.remove(record.key);
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

  static bool _isRecentSave(ForumReadPosition position) {
    final updatedAt = position.updatedAt;
    if (updatedAt == null) {
      return false;
    }
    return DateTime.now().difference(updatedAt) <= _recentSaveMaxAge;
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
