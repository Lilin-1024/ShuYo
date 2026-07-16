import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/common.dart';
import '../models/course_rating.dart';
import '../services/course_rating_api_client.dart';

class CourseRatingRepository {
  CourseRatingRepository({
    CourseRatingApiClient? apiClient,
    Future<SharedPreferences> Function()? preferencesLoader,
    this.searchCacheDuration = const Duration(hours: 12),
    this.relationCacheDuration = const Duration(hours: 12),
    this.detailCacheDuration = const Duration(minutes: 30),
  })  : _apiClient = apiClient ?? CourseRatingApiClient(),
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _cachePrefix = 'course_rating.cache.';

  final CourseRatingApiClient _apiClient;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final Duration searchCacheDuration;
  final Duration relationCacheDuration;
  final Duration detailCacheDuration;

  final _memoryCache = <String, _CachedJson>{};

  Future<CourseRatingSearchResult> search(
    String keyword, {
    bool forceRefresh = false,
  }) async {
    final normalized = normalizeKeyword(keyword);
    if (normalized.isEmpty) {
      return const CourseRatingSearchResult(
        query: '',
        courses: [],
        teachers: [],
      );
    }
    final key = 'search:${_cacheSafe(normalized)}';
    return _loadCached(
      key: key,
      duration: searchCacheDuration,
      forceRefresh: forceRefresh,
      parser: CourseRatingSearchResult.fromJson,
      loader: () => _apiClient.search(normalized),
    );
  }

  Future<CourseRatingCourseTeachers> fetchCourseTeachers(
    CourseRatingCourse course, {
    bool forceRefresh = false,
  }) {
    final key = 'courseTeachers:${_cacheSafe(course.lookupForTeachers)}';
    return _loadCached(
      key: key,
      duration: relationCacheDuration,
      forceRefresh: forceRefresh,
      parser: CourseRatingCourseTeachers.fromJson,
      loader: () => _apiClient.fetchCourseTeachers(course),
    );
  }

  Future<CourseRatingTeacherCourses> fetchTeacherCourses(
    CourseRatingTeacher teacher, {
    bool forceRefresh = false,
  }) {
    final key = 'teacherCourses:${teacher.id}:${_cacheSafe(teacher.name)}';
    return _loadCached(
      key: key,
      duration: relationCacheDuration,
      forceRefresh: forceRefresh,
      parser: CourseRatingTeacherCourses.fromJson,
      loader: () => _apiClient.fetchTeacherCourses(teacher),
    );
  }

  Future<CourseRatingDetail> fetchRatingDetail({
    required CourseRatingCourse course,
    required CourseRatingTeacher teacher,
    int page = 1,
    bool forceRefresh = false,
  }) {
    final key = 'detail:${_cacheSafe(course.lookupForRatings)}:'
        '${teacher.id}:${_cacheSafe(teacher.name)}:$page';
    return _loadCached(
      key: key,
      duration: detailCacheDuration,
      forceRefresh: forceRefresh,
      parser: CourseRatingDetail.fromJson,
      loader: () => _apiClient.fetchRatingDetail(
        course: course,
        teacher: teacher,
        page: page,
      ),
    );
  }

  String normalizeKeyword(String keyword) {
    return keyword.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<T> _loadCached<T>({
    required String key,
    required Duration duration,
    required bool forceRefresh,
    required T Function(JsonMap json) parser,
    required Future<T> Function() loader,
  }) async {
    if (!forceRefresh) {
      final cached = await _readCache(key);
      if (cached != null &&
          DateTime.now().difference(cached.createdAt) < duration) {
        return parser(cached.value);
      }
    }
    try {
      final value = await loader();
      await _writeCache(key, _toJson(value));
      return value;
    } on Object {
      final cached = await _readCache(key);
      if (cached != null) {
        return parser(cached.value);
      }
      rethrow;
    }
  }

  JsonMap _toJson<T>(T value) {
    if (value is CourseRatingSearchResult) {
      return value.toJson();
    }
    if (value is CourseRatingCourseTeachers) {
      return value.toJson();
    }
    if (value is CourseRatingTeacherCourses) {
      return value.toJson();
    }
    if (value is CourseRatingDetail) {
      return value.toJson();
    }
    throw StateError('Unsupported course rating cache value: $T');
  }

  Future<_CachedJson?> _readCache(String key) async {
    final memory = _memoryCache[key];
    if (memory != null) {
      return memory;
    }
    final prefs = await _preferencesLoader();
    final raw = prefs.getString('$_cachePrefix$key');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! JsonMap) {
      return null;
    }
    final createdAt = dateValue(decoded['createdAt']);
    final value = decoded['value'];
    if (createdAt == null || value is! JsonMap) {
      return null;
    }
    final cached = _CachedJson(createdAt: createdAt, value: value);
    _memoryCache[key] = cached;
    return cached;
  }

  Future<void> _writeCache(String key, JsonMap value) async {
    final cached = _CachedJson(createdAt: DateTime.now(), value: value);
    _memoryCache[key] = cached;
    final prefs = await _preferencesLoader();
    await prefs.setString(
      '$_cachePrefix$key',
      jsonEncode({
        'createdAt': cached.createdAt.toIso8601String(),
        'value': value,
      }),
    );
  }

  String _cacheSafe(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }
}

class _CachedJson {
  const _CachedJson({
    required this.createdAt,
    required this.value,
  });

  final DateTime createdAt;
  final JsonMap value;
}
