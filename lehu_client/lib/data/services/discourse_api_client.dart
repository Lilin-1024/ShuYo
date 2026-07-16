import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/certificate_policy.dart';
import '../../core/forum_constants.dart';
import '../models/common.dart';
import 'forum_auth_service.dart';

class ForumApiException implements Exception {
  const ForumApiException(this.message, {this.statusCode});

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

class ForumAuthException extends ForumApiException {
  const ForumAuthException([
    super.message = '请先登录乐乎',
    int? statusCode,
  ]) : super(statusCode: statusCode);
}

class DiscourseApiClient {
  DiscourseApiClient({
    required ForumAuthService authService,
    http.Client? httpClient,
  })  : _authService = authService,
        _httpClient = httpClient ?? _defaultHttpClient();

  final ForumAuthService _authService;
  final http.Client _httpClient;
  String? _csrfToken;

  static http.Client _defaultHttpClient() {
    final client = HttpClient()
      ..badCertificateCallback = (certificate, host, port) {
        return CertificatePolicy.allowsHost(host);
      };
    return IOClient(client);
  }

  Future<JsonMap> getJson(String path) async {
    final response = await _httpClient.get(
      _uri(path),
      headers: await _headers(),
    );
    return _decode(response);
  }

  Future<JsonMap> postForm(String path, String body) async {
    final response = await _httpClient.post(
      _uri(path),
      headers: await _headers(
        csrfToken: await _csrf(),
        formRequest: true,
      ),
      body: body,
    );
    return _decode(response);
  }

  Future<JsonMap> putForm(String path, String body) async {
    final response = await _httpClient.put(
      _uri(path),
      headers: await _headers(
        csrfToken: await _csrf(),
        formRequest: true,
      ),
      body: body,
    );
    return _decode(response);
  }

  Future<JsonMap> deleteForm(String path, String body) async {
    final response = await _httpClient.delete(
      _uri(path),
      headers: await _headers(
        csrfToken: await _csrf(),
        formRequest: true,
      ),
      body: body,
    );
    return _decode(response);
  }

  Future<JsonMap> postMultipart({
    required String path,
    required Map<String, String> fields,
    required String fileField,
    required Uint8List fileBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(await _headers(csrfToken: await _csrf()));
    request.fields.addAll(fields);
    request.files.add(
      http.MultipartFile.fromBytes(
        fileField,
        fileBytes,
        filename: filename,
      ),
    );
    final streamed = await _httpClient.send(request);
    return _decode(await http.Response.fromStream(streamed));
  }

  Future<Map<String, String>> _headers({
    String? csrfToken,
    bool formRequest = false,
  }) async {
    final headers = <String, String>{
      'accept': formRequest ? '*/*' : 'application/json',
      'x-requested-with': 'XMLHttpRequest',
    };
    final cookie = await _authService.cookieHeader();
    if (cookie != null && cookie.isNotEmpty) {
      headers['cookie'] = cookie;
    }
    if (csrfToken != null && csrfToken.isNotEmpty) {
      headers['x-csrf-token'] = csrfToken;
    }
    if (formRequest) {
      headers['content-type'] =
          'application/x-www-form-urlencoded; charset=UTF-8';
    }
    return headers;
  }

  Future<String> _csrf() async {
    final cached = _csrfToken;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final json = await getJson('/session/csrf.json');
    final token = stringValue(json['csrf']);
    if (token.isEmpty) {
      throw const ForumAuthException('无法获取 CSRF Token，请重新登录');
    }
    _csrfToken = token;
    return token;
  }

  Uri _uri(String path) {
    if (path.startsWith('http')) {
      return Uri.parse(path);
    }
    return Uri.parse('${ForumConstants.baseUrl}$path');
  }

  JsonMap _decode(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    if (body.trim().isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return <String, dynamic>{};
      }
      throw ForumApiException(
        '论坛请求失败',
        statusCode: response.statusCode,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ForumApiException(
        '论坛返回的不是 JSON，可能需要重新登录',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! JsonMap) {
      throw ForumApiException(
        '论坛返回了无法解析的数据',
        statusCode: response.statusCode,
      );
    }
    if (decoded['error_type'] == 'not_logged_in') {
      throw const ForumAuthException();
    }
    if (response.statusCode == 401) {
      throw ForumAuthException(
        '登录状态已失效',
        response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ForumApiException(
        _errorMessage(decoded),
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  String _errorMessage(JsonMap json) {
    final errors = json['errors'];
    if (errors is List && errors.isNotEmpty) {
      return errors.map((error) => error.toString()).join('\n');
    }
    final error = json['error'];
    if (error != null) {
      return error.toString();
    }
    return '论坛请求失败';
  }
}
