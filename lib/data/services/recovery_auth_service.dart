import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/client_user_agent.dart';
import 'academic_native_auth_service.dart';
import 'http_timeout.dart';

class RecoveryChallenge {
  RecoveryChallenge(Map<String, String> methods)
      : methods = Map.unmodifiable(methods);

  /// Only methods returned by the university are available for this account.
  final Map<String, String> methods;
}

class RecoveryAuthException implements Exception {
  const RecoveryAuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// One instance owns one recovery flow and its private, in-memory session.
/// Keep it alive when moving to the next page; it must not publish these
/// temporary cookies to the application's login session.
class RecoveryAuthService {
  RecoveryAuthService(
      {HttpClient? httpClient, Uri? baseUri, DateTime Function()? now})
      : _client = httpClient ?? HttpClient(),
        _baseUri = baseUri ?? Uri.parse('https://services.shu.edu.cn'),
        _now = now ?? DateTime.now {
    _client.connectionTimeout = HttpTimeout.connect;
  }

  final HttpClient _client;
  final Uri _baseUri;
  final DateTime Function() _now;
  final Map<bool, DateTime> _verificationResendAt = {};
  AcademicSessionCookieStore _cookies = AcademicSessionCookieStore();
  String? _csrfToken;
  String? _flow;

  bool get hasVerifiedSession => _csrfToken != null && _flow != null;

  /// This short-lived state is owned by the recovery flow, not a screen.
  /// It contains no account or session information.
  DateTime get currentTime => _now();

  DateTime? verificationCodeResendAt(bool resetPassword) =>
      _verificationResendAt[resetPassword];

  DateTime recordVerificationCodeSent(bool resetPassword) {
    final resendAt = currentTime.add(const Duration(seconds: 60));
    _verificationResendAt[resetPassword] = resendAt;
    return resendAt;
  }

  void dispose() => _client.close(force: true);

  Future<RecoveryChallenge> verifyResetInfo({
    required String username,
    required String realName,
    required String identityID,
    required String cardID,
  }) =>
      _verify('resetPassword', {
        'username': username,
        'realName': realName,
        'identityID': identityID,
        'cardID': cardID,
      });

  Future<RecoveryChallenge> verifyChangePhoneUser({
    required String username,
    required String password,
  }) {
    // The site's 1024-bit RSA key with PKCS#1 v1.5 has 117 bytes for input.
    if (utf8.encode(password).length > 117) {
      throw const RecoveryAuthException('passwordTooLong', '密码过长，请检查后重试');
    }
    return _verify('changePhone', {
      'username': username,
      'password': AcademicPasswordEncryptor.encrypt(password),
    });
  }

  /// Sends a code using one of the methods returned by the first step.
  Future<void> sendVerificationCode({required String method}) => _action(
        (flow) => flow == 'resetPassword' ? 'sendCode' : 'sendOldCode',
        {'method': method},
        fallbackMessage: '验证码发送失败，请稍后重试',
      );

  Future<void> verifyVerificationCode({
    required String method,
    required String code,
  }) =>
      _action(
        (flow) => flow == 'resetPassword' ? 'verifyCode' : 'verifyOldCode',
        {'method': method, 'code': code},
      );

  Future<void> resetPassword({
    required String password,
    required String confirmPassword,
  }) {
    _requireFlow('resetPassword');
    if (utf8.encode(password).length > 117 ||
        utf8.encode(confirmPassword).length > 117) {
      throw const RecoveryAuthException('passwordTooLong', '密码过长，请检查后重试');
    }
    return _action(
        (_) => 'submit',
        {
          'password': AcademicPasswordEncryptor.encrypt(password),
          'confirmPassword': AcademicPasswordEncryptor.encrypt(confirmPassword),
        },
        requireExplicitSuccess: true);
  }

  Future<void> sendNewPhoneCode({required String phone}) {
    _requireFlow('changePhone');
    return _action((_) => 'sendNewCode', {'phone': phone},
        fallbackMessage: '验证码发送失败，请稍后重试');
  }

  Future<void> submitNewPhone({required String phone, required String code}) {
    _requireFlow('changePhone');
    return _action((_) => 'submit', {'phone': phone, 'code': code});
  }

  void _requireFlow(String expected) {
    if (_csrfToken == null || _flow != expected) {
      throw const RecoveryAuthException('invalidSession', '验证会话已失效，请重新开始');
    }
  }

  Future<void> _action(
    String Function(String) endpoint,
    Map<String, String> body, {
    bool requireExplicitSuccess = false,
    String fallbackMessage = '验证失败，请稍后重试',
  }) async {
    final flow = _flow;
    final token = _csrfToken;
    if (flow == null || token == null) {
      throw const RecoveryAuthException('invalidSession', '验证会话已失效，请重新开始');
    }
    try {
      final response = await _request(
        'POST',
        _baseUri.resolve('/oauth/$flow/${endpoint(flow)}'),
        body: {...body, 'csrfToken': token},
        referer: _baseUri.resolve('/oauth2/$flow'),
      );
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) json = decoded;
      } on FormatException {
        // HTML error pages and invalid JSON are never treated as success.
      }
      final message = json?['message'];
      if (response.status < 200 ||
          response.status >= 300 ||
          json?['success'] == false ||
          (json?['success'] != true &&
              message is String &&
              message != 'success')) {
        final code = message is String ? message : 'requestFailed';
        throw RecoveryAuthException(
            code, _errorMessage(code, flow, fallbackMessage: fallbackMessage));
      }
      // The final reset response body has not been observed. Require an
      // explicit success indication rather than assuming HTTP 200 means it
      // succeeded. The other endpoints have observed message=success too.
      if (json == null || (message != 'success' && json['success'] != true)) {
        throw RecoveryAuthException(
          'invalidResponse',
          requireExplicitSuccess ? '无法确认密码是否重置成功，请尝试登录确认' : '学校返回的信息不完整，请稍后重试',
        );
      }
    } on RecoveryAuthException {
      rethrow;
    } on TimeoutException {
      throw const RecoveryAuthException('timeout', '网络请求超时，请稍后重试');
    } on SocketException {
      throw const RecoveryAuthException('networkError', '网络连接失败，请检查网络后重试');
    } on HandshakeException {
      throw const RecoveryAuthException('networkError', '安全连接建立失败，请稍后重试');
    } on HttpException {
      throw const RecoveryAuthException('networkError', '网络请求失败，请稍后重试');
    }
  }

  Future<RecoveryChallenge> _verify(
    String flow,
    Map<String, String> body,
  ) async {
    _cookies = AcademicSessionCookieStore();
    _csrfToken = null;
    _flow = null;
    try {
      final page = _baseUri.resolve('/oauth2/$flow');
      final bootstrap = await _request('GET', page);
      if (bootstrap.status < 200 || bootstrap.status >= 300) {
        throw const RecoveryAuthException(
            'pageUnavailable', '无法连接学校认证页面，请稍后重试');
      }
      final endpoint = flow == 'resetPassword' ? 'verifyInfo' : 'verifyUser';
      final response = await _request(
        'POST',
        _baseUri.resolve('/oauth/$flow/$endpoint'),
        body: body,
        referer: page,
      );
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) json = decoded;
      } on FormatException {
        // The server may return an HTML error page instead of JSON.
      }
      if (response.status < 200 ||
          response.status >= 300 ||
          json?['success'] == false) {
        final code = json?['message'] is String
            ? json!['message'] as String
            : 'requestFailed';
        throw RecoveryAuthException(code, _errorMessage(code, flow));
      }
      final token = json?['csrfToken'];
      if (token is! String || token.isEmpty) {
        throw const RecoveryAuthException(
            'invalidResponse', '学校返回的信息不完整，请稍后重试');
      }
      final methods = <String, String>{};
      final rawMethods = json?['methods'];
      if (rawMethods is Map) {
        for (final entry in rawMethods.entries) {
          if (entry.key is String) {
            methods[entry.key as String] = entry.value?.toString() ?? '';
          }
        }
      }
      _csrfToken = token;
      _flow = flow;
      return RecoveryChallenge(methods);
    } on RecoveryAuthException {
      rethrow;
    } on TimeoutException {
      throw const RecoveryAuthException('timeout', '网络请求超时，请稍后重试');
    } on SocketException {
      throw const RecoveryAuthException('networkError', '网络连接失败，请检查网络后重试');
    } on HandshakeException {
      throw const RecoveryAuthException('networkError', '安全连接建立失败，请稍后重试');
    } on HttpException {
      throw const RecoveryAuthException('networkError', '网络请求失败，请稍后重试');
    }
  }

  Future<({int status, String body})> _request(
    String method,
    Uri uri, {
    Map<String, String>? body,
    Uri? referer,
  }) async {
    // A request can finish after a new recovery attempt replaces _cookies.
    // Keep both reading and updating the store belonging to this request.
    final cookieStore = _cookies;
    final request =
        await _client.openUrl(method, uri).timeout(HttpTimeout.connect);
    request.followRedirects = false;
    request.headers
        .set(HttpHeaders.userAgentHeader, ClientUserAgent.mobileBrowser);
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*');
    final cookieHeader = cookieStore.headerFor(uri);
    if (cookieHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }
    if (referer != null) {
      request.headers.set(HttpHeaders.refererHeader, referer.toString());
      request.headers.set('Origin', _baseUri.origin);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(HttpTimeout.normal);
    final cookies = <Cookie>[];
    for (final value
        in response.headers[HttpHeaders.setCookieHeader] ?? <String>[]) {
      try {
        cookies.add(Cookie.fromSetCookieValue(value));
      } on FormatException {
        // Ignore malformed cookies without logging their contents.
      }
    }
    cookieStore.save(uri, cookies);
    final text = await utf8.decodeStream(response).timeout(HttpTimeout.normal);
    return (status: response.statusCode, body: text);
  }

  static String _errorMessage(String code, String flow,
          {String fallbackMessage = '验证失败，请稍后重试'}) =>
      switch (code) {
        'badRequestParams' => flow == 'resetPassword' ? '验证信息无效' : '请求参数无效',
        'userNotFound' => '用户不存在',
        'infoMismatch' => '身份信息不匹配',
        'invalidPassword' => '学工号或密码不正确',
        'invalidCode' => '验证码不正确或已过期',
        'sendError' => '验证码发送失败',
        'badPassword' => '重置密码失败',
        'sendTooRecently' => '验证码发送过于频繁，请稍后再试',
        'samePhoneNumber' => '新手机号不能与旧手机号相同',
        'ipLimitExceeded' => '当前 IP 尝试次数过多，请稍后再试',
        'internalServerError' => '系统内部错误，请稍后再试',
        _ => fallbackMessage,
      };
}
