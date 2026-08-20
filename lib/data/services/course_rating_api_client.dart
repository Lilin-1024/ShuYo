import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/client_user_agent.dart';
import '../models/common.dart';
import '../models/course_rating.dart';
import 'http_timeout.dart';

class CourseRatingApiException implements Exception {
  const CourseRatingApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() {
    final code = statusCode;
    if (code == null) {
      return message;
    }
    return '$message ($code)';
  }
}

class CourseRatingRateLimitedException extends CourseRatingApiException {
  const CourseRatingRateLimitedException(super.message, {this.retryAfter})
      : super(statusCode: 429);

  final Duration? retryAfter;
}

class CourseRatingApiClient {
  CourseRatingApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? IOClient(HttpClient());

  static const baseUrl = 'https://course-rate.icu';

  final http.Client _httpClient;

  Future<CourseRatingSearchResult> search(String keyword) async {
    final json = await _getJson(
      Uri.https('course-rate.icu', '/api/search', {'keyword': keyword}),
    );
    return parseSearchResult(json);
  }

  Future<CourseRatingCourseTeachers> fetchCourseTeachers(
    CourseRatingCourse course,
  ) async {
    final lookup = Uri.encodeComponent(course.lookupForTeachers);
    final json = await _getJson(
      Uri.parse('$baseUrl/api/course/$lookup/teachers'),
    );
    return parseCourseTeachers(json);
  }

  Future<CourseRatingTeacherCourses> fetchTeacherCourses(
    CourseRatingTeacher teacher,
  ) async {
    final json = await _getJson(
      Uri.parse('$baseUrl/api/teacher/${teacher.id}/courses'),
    );
    return parseTeacherCourses(json);
  }

  Future<CourseRatingDetail> fetchRatingDetail({
    required CourseRatingCourse course,
    required CourseRatingTeacher teacher,
    int page = 1,
  }) async {
    final courseLookup = Uri.encodeComponent(course.lookupForRatings);
    final teacherName = Uri.encodeComponent(teacher.name);
    final json = await _getJson(
      Uri.parse('$baseUrl/api/rate/$courseLookup/$teacherName?page=$page'),
    );
    return parseRatingDetail(json);
  }

  static CourseRatingSearchResult parseSearchResult(JsonMap json) {
    return CourseRatingSearchResult.fromJson(json);
  }

  static CourseRatingCourseTeachers parseCourseTeachers(JsonMap json) {
    return CourseRatingCourseTeachers.fromJson(json);
  }

  static CourseRatingTeacherCourses parseTeacherCourses(JsonMap json) {
    return CourseRatingTeacherCourses.fromJson(json);
  }

  static CourseRatingDetail parseRatingDetail(JsonMap json) {
    return CourseRatingDetail.fromJson(json);
  }

  Future<JsonMap> _getJson(Uri uri) async {
    final response = await HttpTimeout.request(
      _httpClient.get(
        uri,
        headers: {
          'accept': 'application/json',
          'user-agent': ClientUserAgent.mobileBrowser,
        },
      ),
      message: '课程评价请求超时，请稍后再试',
    );
    if (response.statusCode == 429) {
      throw CourseRatingRateLimitedException(
        _messageFromBody(response.bodyBytes) ?? '课程评价站点暂时限流，请稍后再试。',
        retryAfter: _retryAfter(response.headers['retry-after']),
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CourseRatingApiException(
        _messageFromBody(response.bodyBytes) ?? '课程评价请求失败',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! JsonMap) {
      throw const CourseRatingApiException('加载失败，请稍后再试');
    }
    if (boolValue(decoded['__rate_limited'])) {
      throw CourseRatingRateLimitedException(
        stringValue(decoded['message'], '课程评价站点暂时限流，请稍后再试。'),
        retryAfter: _retryAfter(stringValue(decoded['retry_after'])),
      );
    }
    if (decoded['error'] != null) {
      throw CourseRatingApiException(stringValue(decoded['error'], '课程评价请求失败'));
    }
    return decoded;
  }

  static String? _messageFromBody(List<int> bodyBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is JsonMap) {
        return stringValue(decoded['message'] ?? decoded['error']).trim();
      }
    } on Object {
      return null;
    }
    return null;
  }

  static Duration? _retryAfter(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final seconds = int.tryParse(value);
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return Duration(seconds: seconds);
  }
}
