import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/client_user_agent.dart';
import '../models/campus_card.dart';
import 'academic_account_store.dart';
import 'http_timeout.dart';
import 'secure_app_store.dart';
import 'unified_account_service.dart';

class CampusCardException implements Exception {
  const CampusCardException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class CampusCardAuthRequiredException extends CampusCardException {
  const CampusCardAuthRequiredException()
      : super('loginRequired', '校园卡查询需要重新验证校园账户');
}

class _CampusCardTokenExpiredException extends CampusCardAuthRequiredException {
  const _CampusCardTokenExpiredException(this.token);

  final String token;
}

/// 只访问门户的身份与校园卡查询接口，不承载支付或充值会话。
class CampusCardService {
  CampusCardService({
    HttpClient? httpClient,
    UnifiedAccountService? accountService,
  })  : _http = httpClient ?? HttpClient(),
        _accountService = accountService ?? UnifiedAccountService() {
    _http.connectionTimeout = HttpTimeout.connect;
  }

  static const _host = 'eportal.shu.edu.cn';
  static const _cardPath = '/api/Identity/SchoolCard/GetCardPersonInfo';
  static const _billsPath = '/api/Identity/SchoolCard/GetCardBillInfo';
  static const _loginPath = '/api/Identity/User/Login';
  static const _profilePath = '/api/Identity/User/GetUserInfo';
  final HttpClient _http;
  final UnifiedAccountService _accountService;
  final SecureAppStore _store = SecureAppStore();
  final AcademicAccountStore _accounts = AcademicAccountStore();
  Future<_CardSession>? _pendingSession;

  void dispose() => _http.close(force: true);

  Future<void> clearSession() =>
      _store.delete(SecureAppStore.campusCardSessionKey);

  Future<CampusCardInfo> fetchCardInfo() => _withSession((session) async =>
      session.initialCard ?? await _readCard(session.token, session.studentId));

  Future<List<CampusCardBill>> fetchBills({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    if (start.isAfter(end)) {
      throw const CampusCardException('invalidDates', '开始日期不能晚于结束日期');
    }
    return _withSession((session) async {
      final data = await _request('GET', _billsPath, query: {
        'access_token': session.token,
        'StartDate': _day(start),
        'EndDate': _day(end),
      });
      await _requireAccount(session.studentId);
      final bills = data['bills'];
      if (bills is! List) throw _invalidResponse;
      try {
        return List.unmodifiable(bills.map((bill) {
          if (bill is! Map<String, dynamic>) throw _invalidResponse;
          return CampusCardBill.fromJson(bill);
        }));
      } on FormatException {
        throw _invalidResponse;
      }
    });
  }

  /// 授权码只消费一次，校验门户与校园卡身份后才保存业务凭证。
  Future<void> completeOAuth(
    Uri callback, {
    required String expectedStudentId,
  }) async {
    await _completeOAuth(callback, expectedStudentId: expectedStudentId);
  }

  Future<_CardSession> _completeOAuth(
    Uri callback, {
    required String expectedStudentId,
  }) async {
    await _requireAccount(expectedStudentId);
    final codes = callback.queryParametersAll['code'];
    if (callback.scheme != 'https' ||
        callback.host != _host ||
        callback.port != 443 ||
        callback.userInfo.isNotEmpty ||
        callback.fragment.isNotEmpty ||
        (callback.path != '/login' && callback.path != '/login/') ||
        callback.queryParameters.containsKey('error') ||
        codes == null ||
        codes.length != 1 ||
        codes.single.trim().isEmpty) {
      throw const CampusCardException('invalidCallback', '校园卡授权回调无效，请重试');
    }
    final login = await _request('POST', _loginPath, query: {
      'code': codes.single,
    });
    final token = login['access_token'];
    final userId = _identity(login['userid']);
    if (token is! String || token.isEmpty || userId == null) {
      throw _invalidResponse;
    }
    if (userId != expectedStudentId.trim()) throw _accountMismatch;
    final card = await _readCard(token, userId);
    await _requireAccount(userId);
    await _store.write(
      SecureAppStore.campusCardSessionKey,
      jsonEncode({'access_token': token, 'studentId': userId}),
    );
    // Account switching or logout may have happened while Keychain was busy.
    if (await _accounts.loadStudentId() != userId) {
      await clearSession();
      throw _accountMismatch;
    }
    return _CardSession(token, userId, initialCard: card);
  }

  Future<T> _withSession<T>(Future<T> Function(_CardSession) operation) async {
    final studentId = await _accounts.loadStudentId();
    if (studentId == null) throw const CampusCardAuthRequiredException();
    Future<T> run(_CardSession session) async {
      if (session.studentId != studentId) throw _accountMismatch;
      await _requireAccount(studentId);
      return operation(session);
    }

    try {
      return await run(await _session());
    } on _CampusCardTokenExpiredException catch (error) {
      await _requireAccount(studentId);
      // Retry once; failures of the replacement session reach the caller.
      return run(await _session(rejectedToken: error.token));
    }
  }

  Future<_CardSession> _session({String? rejectedToken}) async {
    final pending = _pendingSession;
    if (pending != null) {
      try {
        final session = await pending;
        if (session.token != rejectedToken) return session;
      } on _CampusCardTokenExpiredException {
        if (rejectedToken == null) rethrow;
      }
      if (_pendingSession != null && !identical(_pendingSession, pending)) {
        return _session(rejectedToken: rejectedToken);
      }
    }
    final operation = _loadSession(rejectedToken: rejectedToken);
    _pendingSession = operation;
    try {
      return await operation;
    } finally {
      if (identical(_pendingSession, operation)) _pendingSession = null;
    }
  }

  Future<_CardSession> _authorizeSession(String studentId) async {
    await _requireAccount(studentId);
    final callback = await _accountService.authorizeCampusCard();
    if (callback == null) throw const CampusCardAuthRequiredException();
    try {
      return await _completeOAuth(callback, expectedStudentId: studentId);
    } on _CampusCardTokenExpiredException {
      // A newly issued token was already rejected. Leave login to the caller
      // instead of starting another automatic authorization.
      throw const CampusCardAuthRequiredException();
    }
  }

  Future<_CardSession> _loadSession({String? rejectedToken}) async {
    final studentId = await _accounts.loadStudentId();
    if (studentId == null) throw const CampusCardAuthRequiredException();
    final raw = await _store.read(SecureAppStore.campusCardSessionKey);
    if (raw == null) {
      return _authorizeSession(studentId);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      await clearSession();
      throw _invalidResponse;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['studentId'] != studentId ||
        decoded['access_token'] is! String ||
        (decoded['access_token'] as String).isEmpty) {
      await clearSession();
      throw const CampusCardAuthRequiredException();
    }
    final token = decoded['access_token'] as String;
    if (token == rejectedToken) {
      await clearSession();
      return _authorizeSession(studentId);
    }
    final profile = await _request('POST', _profilePath, query: {
      'access_token': token,
    });
    if (_identity(profile['userid']) != studentId) {
      await clearSession();
      throw _accountMismatch;
    }
    await _requireAccount(studentId);
    return _CardSession(token, studentId);
  }

  Future<CampusCardInfo> _readCard(String token, String studentId) async {
    final data = await _request('GET', _cardPath, query: {
      'access_token': token,
    });
    final object = data['schoolCard'];
    if (object is! Map<String, dynamic>) throw _invalidResponse;
    final CampusCardInfo card;
    try {
      card = CampusCardInfo.fromJson(object);
    } on FormatException {
      throw _invalidResponse;
    }
    if (card.studentId != studentId) {
      await clearSession();
      throw _accountMismatch;
    }
    await _requireAccount(studentId);
    return card;
  }

  Future<void> _requireAccount(String studentId) async {
    if (studentId.trim().isEmpty ||
        await _accounts.loadStudentId() != studentId.trim()) {
      throw _accountMismatch;
    }
  }

  Future<Never> _rejectAuthentication(String? token) async {
    if (token == null) throw const CampusCardAuthRequiredException();
    final raw = await _store.read(SecureAppStore.campusCardSessionKey);
    if (raw != null) {
      // A late rejection of an old request must not delete a renewed token.
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['access_token'] == token) {
        await clearSession();
      }
    }
    throw _CampusCardTokenExpiredException(token);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    required Map<String, String> query,
  }) async {
    // No externally supplied host/path and no redirects can receive this token.
    if (!{_cardPath, _billsPath, _loginPath, _profilePath}.contains(path)) {
      throw const CampusCardException('invalidEndpoint', '校园卡请求地址无效');
    }
    final uri = Uri.https(_host, path, query);
    try {
      final request =
          await _http.openUrl(method, uri).timeout(HttpTimeout.connect);
      request.followRedirects = false;
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.userAgentHeader, ClientUserAgent.mobileBrowser);
      if (method == 'POST') request.contentLength = 0;
      final response = await request.close().timeout(HttpTimeout.normal);
      final status = response.statusCode;
      final body =
          await utf8.decodeStream(response).timeout(HttpTimeout.normal);
      if (status == 401 || status == 403) {
        return await _rejectAuthentication(query['access_token']);
      }
      if (status != HttpStatus.ok) {
        throw CampusCardException('httpError', '校园卡服务暂时不可用（HTTP $status）');
      }
      final payload = jsonDecode(body);
      if (payload is! Map<String, dynamic>) throw _invalidResponse;
      // GetUserInfo is the portal's own token-validation endpoint. Its actual
      // signed-out response is type=3,errorcode=500,message=登录失效. A generic
      // SchoolCard "fault" is not sufficient evidence of an expired token.
      if (payload['type'] == 3 &&
          payload['errorcode'] == 500 &&
          payload['message'] == '登录失效') {
        return await _rejectAuthentication(query['access_token']);
      }
      if (payload['type'] != 1 || payload['errorcode'] != 0) {
        throw const CampusCardException('businessError', '校方暂未返回校园卡数据，请稍后重试');
      }
      final data = payload['data'];
      if (data is! Map<String, dynamic>) throw _invalidResponse;
      return data;
    } on TimeoutException {
      throw const CampusCardException('timeout', '校园卡查询超时，请稍后重试');
    } on SocketException {
      throw const CampusCardException('network', '无法连接校园卡服务，请检查网络');
    } on HandshakeException {
      throw const CampusCardException('network', '无法安全连接校园卡服务');
    } on HttpException {
      throw const CampusCardException('network', '校园卡服务连接中断，请重试');
    } on FormatException {
      throw _invalidResponse;
    }
  }

  static const _invalidResponse =
      CampusCardException('invalidResponse', '校园卡数据格式异常，请稍后重试');
  static const _accountMismatch =
      CampusCardException('accountMismatch', '校园卡身份与当前校园账户不一致，请重新登录');

  static String? _identity(Object? value) {
    if (value is! String && value is! num) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _CardSession {
  const _CardSession(this.token, this.studentId, {this.initialCard});

  final String token;
  final String studentId;
  final CampusCardInfo? initialCard;
}
