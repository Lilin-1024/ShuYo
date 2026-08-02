import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/client_backend_constants.dart';
import '../models/client_backend.dart';
import '../models/common.dart';
import 'http_timeout.dart';

class ClientBackendApiException implements Exception {
  const ClientBackendApiException(this.message, {this.statusCode});

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

class ClientBackendRateLimitedException extends ClientBackendApiException {
  const ClientBackendRateLimitedException(super.message, {this.retryAfter})
      : super(statusCode: 429);

  final Duration? retryAfter;
}

class ClientBackendApiClient {
  ClientBackendApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? IOClient(HttpClient());

  final http.Client _httpClient;

  Future<ClientBootstrapInfo> fetchBootstrap() async {
    final response = await HttpTimeout.request(
      _httpClient.get(
        _uri('/api/v1/bootstrap'),
        headers: const {
          'accept': 'application/json',
          'user-agent':
              'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
        },
      ),
      message: '客户端服务请求超时，请稍后再试',
    );
    return ClientBootstrapInfo.fromJson(_decode(response));
  }

  Future<ClientFeedbackSubmissionResult> submitFeedback(
    ClientFeedbackDraft draft,
  ) async {
    final response = await HttpTimeout.request(
      _httpClient.post(
        _uri('/api/v1/feedback'),
        headers: const {
          'accept': 'application/json',
          'content-type': 'application/json; charset=utf-8',
          'user-agent':
              'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
        },
        body: jsonEncode(draft.toJson()),
      ),
      message: '反馈提交超时，请稍后再试',
    );
    return ClientFeedbackSubmissionResult.fromJson(_decode(response));
  }

  Future<ClientFeedbackTicket> fetchFeedback(
    String id,
    String token,
  ) async {
    final response = await HttpTimeout.request(
      _httpClient.get(
        _uri('/api/v1/feedback/$id'),
        headers: {
          'accept': 'application/json',
          'x-feedback-token': token,
          'user-agent':
              'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
        },
      ),
      message: '反馈查看超时，请稍后再试',
    );
    final json = _decode(response);
    final data = json['data'];
    if (data is! JsonMap) {
      throw const ClientBackendApiException('加载失败，请稍后再试');
    }
    return ClientFeedbackTicket.fromServerJson(data, lookupToken: token);
  }

  JsonMap _decode(http.Response response) {
    if (response.statusCode == 429) {
      throw ClientBackendRateLimitedException(
        _messageFromBody(response.bodyBytes) ?? '请求过于频繁，请稍后再试。',
        retryAfter: _retryAfter(response.headers['retry-after']),
      );
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (body.trim().isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return <String, dynamic>{};
      }
      throw ClientBackendApiException(
        '后端请求失败',
        statusCode: response.statusCode,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ClientBackendApiException(
        '加载失败，请稍后再试',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! JsonMap) {
      throw ClientBackendApiException(
        '加载失败，请稍后再试',
        statusCode: response.statusCode,
      );
    }
    if (decoded['success'] == false) {
      throw ClientBackendApiException(
        stringValue(decoded['error'], '后端请求失败'),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ClientBackendApiException(
        _messageFromBody(response.bodyBytes) ?? '后端请求失败',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  static String? _messageFromBody(List<int> bodyBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is JsonMap) {
        final message = decoded['message'] ?? decoded['error'];
        final text = stringValue(message).trim();
        return text.isEmpty ? null : text;
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

  Uri _uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${ClientBackendConstants.baseUrl}$normalized');
  }
}
