import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/announcement.dart';
import '../models/common.dart';
import '../services/announcement_api_client.dart';

class AnnouncementHomeSummary {
  const AnnouncementHomeSummary(this.text);

  final String text;
}

class AnnouncementRepository {
  AnnouncementRepository({
    AnnouncementApiClient? apiClient,
    Future<SharedPreferences> Function()? preferencesLoader,
    this.autoRefreshInterval = defaultAutoRefreshInterval,
  })  : _apiClient = apiClient ?? AnnouncementApiClient(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const defaultAutoRefreshInterval = Duration(hours: 12);
  static const _listCacheKey = 'announcements.list.cache';
  static const _lastRefreshKey = 'announcements.lastRefreshAt';
  static const _cacheVersionKey = 'announcements.cacheVersion';
  static const _cacheVersion = 2;

  final AnnouncementApiClient _apiClient;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Duration autoRefreshInterval;

  List<AnnouncementListItem>? _memoryList;

  Future<List<AnnouncementListItem>> loadCachedAnnouncements() async {
    if (_memoryList != null) {
      return _memoryList!;
    }
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(_listCacheKey);
    if (raw == null || raw.isEmpty) {
      return const <AnnouncementListItem>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <AnnouncementListItem>[];
    }
    final items = decoded
        .whereType<JsonMap>()
        .map(AnnouncementListItem.fromJson)
        .toList(growable: false);
    _memoryList = items;
    return items;
  }

  Future<List<AnnouncementListItem>> fetchAnnouncements({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && !await _shouldAutoRefresh()) {
      return loadCachedAnnouncements();
    }
    try {
      final items = await _apiClient.fetchAnnouncements();
      await _saveList(items);
      return items;
    } on Object {
      final cached = await loadCachedAnnouncements();
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  Future<AnnouncementDetail> fetchDetail(AnnouncementListItem item) {
    return _apiClient.fetchDetail(item);
  }

  Future<AnnouncementHomeSummary> homeSummary() async {
    final cached = await loadCachedAnnouncements();
    if (cached.isNotEmpty) {
      return AnnouncementHomeSummary(cached.first.title);
    }
    return const AnnouncementHomeSummary('点击查看学校官网通知');
  }

  Future<bool> _shouldAutoRefresh() async {
    final prefs = await _preferencesLoader();
    if (prefs.getInt(_cacheVersionKey) != _cacheVersion) {
      return true;
    }
    final raw = prefs.getString(_lastRefreshKey);
    final lastRefresh = raw == null ? null : DateTime.tryParse(raw);
    if (lastRefresh == null) {
      return true;
    }
    return DateTime.now().difference(lastRefresh) >= autoRefreshInterval;
  }

  Future<void> _saveList(List<AnnouncementListItem> items) async {
    _memoryList = items;
    final prefs = await _preferencesLoader();
    await prefs.setString(
      _listCacheKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(_lastRefreshKey, DateTime.now().toIso8601String());
    await prefs.setInt(_cacheVersionKey, _cacheVersion);
  }
}
