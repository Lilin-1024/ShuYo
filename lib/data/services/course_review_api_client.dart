import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/client_backend_constants.dart';
import '../../core/client_user_agent.dart';
import '../models/common.dart';
import '../models/course_review.dart';
import 'client_backend_api_client.dart';
import 'http_timeout.dart';

/// Course review endpoints. Public reads need no identity; reviews and
/// course review feedback need a verified student token.
class CourseReviewApiClient {
  CourseReviewApiClient({http.Client? httpClient})
      : _httpClient = httpClient ??
            IOClient(HttpClient()..connectionTimeout = HttpTimeout.connect);

  final http.Client _httpClient;

  void dispose() => _httpClient.close();

  Future<RateCatalogConfig> fetchConfig() async =>
      RateCatalogConfig.fromJson(await _data('GET', '/api/v1/rate/questions'));

  Future<RateHome> fetchHome() async =>
      RateHome.fromJson(await _data('GET', '/api/v1/rate/home'));

  Future<RateSearchResult> search(String query) async =>
      RateSearchResult.fromJson(
          await _data('GET', '/api/v1/rate/search', query: {'q': query}));

  Future<RateCourseDetail> fetchCourse(String id) async =>
      RateCourseDetail.fromJson(
          await _data('GET', '/api/v1/rate/courses/${_segment(id)}'));

  Future<RateTeacherDetail> fetchTeacher(String id) async =>
      RateTeacherDetail.fromJson(
          await _data('GET', '/api/v1/rate/teachers/${_segment(id)}'));

  Future<RateUnitDetail> fetchUnit(String id) async => RateUnitDetail.fromJson(
      await _data('GET', '/api/v1/rate/units/${_segment(id)}'));

  Future<RateRankingResult> fetchRanking(
    String category, {
    String sub = '',
    int page = 1,
  }) async =>
      RateRankingResult.fromJson(await _data(
        'GET',
        '/api/v1/rate/rankings/${_segment(category)}',
        query: {if (sub.isNotEmpty) 'sub': sub, 'page': '$page'},
      ));

  Future<List<RateCourseSummary>> fetchCollegeCourses(String college) async {
    final data = await _data(
        'GET', '/api/v1/rate/colleges/${_segment(college)}/courses');
    return (data['courses'] as List? ?? const [])
        .whereType<JsonMap>()
        .map(RateCourseSummary.fromJson)
        .toList();
  }

  Future<List<RateLookupResult>> lookup(
      List<RateScheduleCourse> courses) async {
    final response = await _send('POST', '/api/v1/rate/units/lookup', body: {
      'items': [for (final course in courses) course.toJson()],
    });
    final data = _decode(response)['data'];
    if (data is! List) throw const ClientBackendApiException('课程匹配结果无效');
    return data.whereType<JsonMap>().map(RateLookupResult.fromJson).toList();
  }

  Future<RateMyReviews> fetchMyReviews(String token) async =>
      RateMyReviews.fromJson(
          await _data('GET', '/api/v1/student/rate/reviews', token: token));

  Future<RateMyReview?> fetchMyReview(String token, String unitId) async {
    final response = await _send(
        'GET', '/api/v1/student/rate/reviews/${_segment(unitId)}',
        token: token);
    final data = _decode(response)['data'];
    return data is JsonMap ? RateMyReview.fromJson(data) : null;
  }

  Future<RateMyReview> saveReview(
      String token, String unitId, RateReviewDraft draft) async {
    final data = await _data(
        'PUT', '/api/v1/student/rate/reviews/${_segment(unitId)}',
        token: token, body: draft.toJson());
    return RateMyReview.fromJson(data);
  }

  Future<void> deleteReview(String token, String unitId) async {
    _decode(await _send(
        'DELETE', '/api/v1/student/rate/reviews/${_segment(unitId)}',
        token: token));
  }

  Future<List<RateFeedbackTicket>> listFeedback(String token) async {
    final response =
        await _send('GET', '/api/v1/student/rate/feedback', token: token);
    final data = _decode(response)['data'];
    if (data is! List) throw const ClientBackendApiException('反馈列表无效');
    return data.whereType<JsonMap>().map(RateFeedbackTicket.fromJson).toList();
  }

  Future<String> submitFeedback(
    String token, {
    required String kind,
    required String content,
    String unitId = '',
    String courseId = '',
    required String appVersion,
    required String platform,
  }) async {
    final data = await _data('POST', '/api/v1/student/rate/feedback',
        token: token,
        body: {
          'kind': kind,
          'content': content,
          if (unitId.isNotEmpty) 'unitId': unitId,
          if (unitId.isEmpty && courseId.isNotEmpty) 'courseId': courseId,
          'appVersion': appVersion,
          'platform': platform,
        });
    return stringValue(data['id']);
  }

  Future<RateFeedbackTicket> fetchFeedback(String token, String id) async =>
      RateFeedbackTicket.fromJson(await _data(
          'GET', '/api/v1/student/rate/feedback/${_segment(id)}',
          token: token));

  Future<RateFeedbackTicket> closeFeedback(String token, String id) async =>
      RateFeedbackTicket.fromJson(await _data(
          'POST', '/api/v1/student/rate/feedback/${_segment(id)}/close',
          token: token));

  static String _segment(String value) => Uri.encodeComponent(value);

  Future<JsonMap> _data(
    String method,
    String path, {
    String? token,
    Map<String, String>? query,
    Object? body,
  }) async {
    final data = _decode(await _send(method, path,
        token: token, query: query, body: body))['data'];
    if (data is! JsonMap) {
      throw const ClientBackendApiException('加载失败，请稍后再试');
    }
    return data;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? token,
    Map<String, String>? query,
    Object? body,
  }) {
    final uri = Uri.parse('${ClientBackendConstants.baseUrl}$path')
        .replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll({
        'accept': 'application/json',
        'user-agent': ClientUserAgent.mobileBrowser,
        if (token != null) 'authorization': 'Bearer $token',
      });
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    return HttpTimeout.request(
      _httpClient.send(request).then(http.Response.fromStream),
      message: '课评服务请求超时，请稍后再试',
    );
  }

  JsonMap _decode(http.Response response) {
    if (response.statusCode == 204) return const {};
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    final error = decoded is JsonMap ? stringValue(decoded['error']) : '';
    if (response.statusCode == 429) {
      throw ClientBackendRateLimitedException(
          error.isEmpty ? '操作过于频繁，请稍后再试。' : error);
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded is! JsonMap ||
        decoded['success'] == false) {
      throw ClientBackendApiException(
        error.isEmpty ? '加载失败，请稍后再试' : error,
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}
