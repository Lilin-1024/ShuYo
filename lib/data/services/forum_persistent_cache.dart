import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/forum_url_resolver.dart';
import '../models/common.dart';

class ForumPersistentCache {
  ForumPersistentCache._({
    required SharedPreferences preferences,
    required String username,
  })  : _preferences = preferences,
        _prefix =
            'forum.cache.v1.${ForumUrlResolver.mode.name}.${_safe(username)}.';

  static const topicDetailMaxAge = Duration(days: 5);
  static const topicDetailMaxCount = 50;
  static const topicFeedMaxAge = Duration(days: 3);

  static Future<ForumPersistentCache> open({
    required String username,
    Future<SharedPreferences> Function()? preferencesLoader,
  }) async {
    final loader = preferencesLoader ?? SharedPreferences.getInstance;
    return ForumPersistentCache._(
      preferences: await loader(),
      username: username,
    );
  }

  final SharedPreferences _preferences;
  final String _prefix;

  String get _feedIndexKey => '${_prefix}feeds.index';
  String get _detailIndexKey => '${_prefix}details.index';
  String get _privateMessagesKey => '${_prefix}privateMessages';

  Future<void> saveTopicFeed(String feedKey, JsonMap json) async {
    await _setEntry(_feedCacheKey(feedKey), json);
    final keys = _stringList(_preferences.getString(_feedIndexKey));
    if (!keys.contains(feedKey)) {
      keys.add(feedKey);
      await _preferences.setString(_feedIndexKey, jsonEncode(keys));
    }
  }

  Future<Map<String, JsonMap>> loadTopicFeeds() async {
    final result = <String, JsonMap>{};
    final keys = _stringList(_preferences.getString(_feedIndexKey));
    var changed = false;
    final keptKeys = <String>[];
    for (final feedKey in keys) {
      final entry = _getEntry(_feedCacheKey(feedKey));
      if (entry == null || _isExpired(entry.savedAt, topicFeedMaxAge)) {
        await _preferences.remove(_feedCacheKey(feedKey));
        changed = true;
        continue;
      }
      keptKeys.add(feedKey);
      result[feedKey] = entry.value;
    }
    if (changed) {
      await _preferences.setString(_feedIndexKey, jsonEncode(keptKeys));
    }
    return result;
  }

  Future<void> saveTopicDetail(
    int topicId,
    JsonMap json, {
    required bool privateMessage,
  }) async {
    await _setEntry(
      _detailCacheKey(topicId),
      json,
      metadata: {'privateMessage': privateMessage},
    );
    final index = _detailIndex();
    index.removeWhere((entry) => entry.id == topicId);
    index.add(
      _DetailIndexEntry(
        id: topicId,
        savedAt: DateTime.now(),
        privateMessage: privateMessage,
      ),
    );
    await _saveDetailIndex(await _cleanDetailIndex(index));
  }

  Future<Map<int, JsonMap>> loadTopicDetails() async {
    final result = <int, JsonMap>{};
    final index = await _cleanDetailIndex(_detailIndex());
    await _saveDetailIndex(index);
    for (final item in index) {
      final entry = _getEntry(_detailCacheKey(item.id));
      if (entry != null) {
        result[item.id] = entry.value;
      }
    }
    return result;
  }

  Future<void> removeTopicDetail(int topicId) async {
    await _preferences.remove(_detailCacheKey(topicId));
    final index = _detailIndex()..removeWhere((entry) => entry.id == topicId);
    await _saveDetailIndex(index);
  }

  Future<void> savePrivateMessages(JsonMap json) {
    return _setEntry(_privateMessagesKey, json);
  }

  JsonMap? loadPrivateMessages() {
    return _getEntry(_privateMessagesKey)?.value;
  }

  Future<void> removePrivateMessageTopic(int topicId) async {
    await removeTopicDetail(topicId);
    final entry = _getEntry(_privateMessagesKey);
    if (entry == null) {
      return;
    }
    final topicList = entry.value['topic_list'];
    if (topicList is! JsonMap) {
      return;
    }
    final topics = topicList['topics'];
    if (topics is! List) {
      return;
    }
    final nextTopics = [
      for (final topic in topics)
        if (topic is! JsonMap || intValue(topic['id']) != topicId) topic,
    ];
    if (nextTopics.length == topics.length) {
      return;
    }
    final next = JsonMap.of(entry.value);
    next['topic_list'] = {
      ...topicList,
      'topics': nextTopics,
    };
    await savePrivateMessages(next);
  }

  String _feedCacheKey(String feedKey) => '${_prefix}feed.${_safe(feedKey)}';
  String _detailCacheKey(int topicId) => '${_prefix}detail.$topicId';

  Future<void> _setEntry(
    String key,
    JsonMap value, {
    JsonMap metadata = const {},
  }) {
    return _preferences.setString(
      key,
      jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'metadata': metadata,
        'value': value,
      }),
    );
  }

  _CacheEntry? _getEntry(String key) {
    final raw = _preferences.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! JsonMap) {
        return null;
      }
      final savedAt = dateValue(decoded['savedAt']);
      final value = decoded['value'];
      if (savedAt == null || value is! JsonMap) {
        return null;
      }
      return _CacheEntry(savedAt: savedAt, value: value);
    } on Object {
      return null;
    }
  }

  List<_DetailIndexEntry> _detailIndex() {
    final raw = _preferences.getString(_detailIndexKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<JsonMap>()
          .map(_DetailIndexEntry.fromJson)
          .where((entry) => entry.id > 0)
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> _saveDetailIndex(List<_DetailIndexEntry> index) {
    return _preferences.setString(
      _detailIndexKey,
      jsonEncode([for (final entry in index) entry.toJson()]),
    );
  }

  Future<List<_DetailIndexEntry>> _cleanDetailIndex(
    List<_DetailIndexEntry> index,
  ) async {
    final now = DateTime.now();
    final byId = <int, _DetailIndexEntry>{};
    for (final entry in index) {
      byId[entry.id] = entry;
    }
    final privateEntries = <_DetailIndexEntry>[];
    final regularEntries = <_DetailIndexEntry>[];
    for (final entry in byId.values) {
      final expired = !entry.privateMessage &&
          now.difference(entry.savedAt) > topicDetailMaxAge;
      if (expired) {
        await _preferences.remove(_detailCacheKey(entry.id));
        continue;
      }
      if (entry.privateMessage) {
        privateEntries.add(entry);
      } else {
        regularEntries.add(entry);
      }
    }
    regularEntries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    for (final removed in regularEntries.skip(topicDetailMaxCount)) {
      await _preferences.remove(_detailCacheKey(removed.id));
    }
    return [
      ...privateEntries,
      ...regularEntries.take(topicDetailMaxCount),
    ];
  }

  bool _isExpired(DateTime savedAt, Duration maxAge) {
    return DateTime.now().difference(savedAt) > maxAge;
  }

  static List<String> _stringList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded.map((item) => item.toString()).toList();
    } on Object {
      return [];
    }
  }

  static String _safe(String value) {
    return base64Url.encode(utf8.encode(value.toLowerCase()));
  }
}

class _CacheEntry {
  const _CacheEntry({
    required this.savedAt,
    required this.value,
  });

  final DateTime savedAt;
  final JsonMap value;
}

class _DetailIndexEntry {
  const _DetailIndexEntry({
    required this.id,
    required this.savedAt,
    required this.privateMessage,
  });

  final int id;
  final DateTime savedAt;
  final bool privateMessage;

  factory _DetailIndexEntry.fromJson(JsonMap json) {
    return _DetailIndexEntry(
      id: intValue(json['id']),
      savedAt:
          dateValue(json['savedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      privateMessage: boolValue(json['privateMessage']),
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'savedAt': savedAt.toIso8601String(),
      'privateMessage': privateMessage,
    };
  }
}
