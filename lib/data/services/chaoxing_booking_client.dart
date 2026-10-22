import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../core/client_user_agent.dart';
import '../../core/wecom_constants.dart';
import 'academic_account_store.dart';
import 'academic_native_auth_service.dart';
import 'session_cookie_jar.dart';

enum ChaoxingFailureKind { loginRequired, unreachable, business, uncertain }

class ChaoxingBookingException implements Exception {
  const ChaoxingBookingException(this.kind, this.message,
      {this.ssoExpired = false});

  final ChaoxingFailureKind kind;
  final String message;
  final bool ssoExpired;

  @override
  String toString() => message;
}

class _AccountMismatchException extends ChaoxingBookingException {
  const _AccountMismatchException()
      : super(ChaoxingFailureKind.loginRequired, '图书馆座位预约账号与当前校园账号不一致，请重新登录');
}

/// The SHU library's Chaoxing seat system. All booking dates are Shanghai today.
///
/// `fidEnc` belongs to the library institution (35480), not the general
/// Learning Tong institution (209). Authentication exchanges the existing SHU
/// SSO session through 5read and login6; each host receives only its own cookies.
class ChaoxingBookingClient {
  ChaoxingBookingClient({
    HttpClient? httpClient,
    SessionCookieJar? cookieJar,
    Uri? serviceUri,
    Uri? ssoUri,
    Uri? oauthRedirectUri,
    Future<List<SessionCookie>> Function(Uri)? cookieLoader,
    Future<void> Function(SessionCookie)? cookieSetter,
    Future<String?> Function()? accountIdLoader,
    DateTime Function()? clock,
  })  : _http = httpClient ?? HttpClient(),
        _jar = cookieJar ?? SessionCookieJar.shared,
        serviceUri = serviceUri ?? Uri.parse('https://office.chaoxing.com'),
        ssoUri = ssoUri ?? Uri.parse(WeComConstants.ssoBase),
        oauthRedirectUri = oauthRedirectUri ??
            Uri.parse('https://zhstsg-jx.5read.com/oauthlogin/'
                'loginByCodeSchoolid?schoolid=2434&type=xxt'),
        _cookieLoader = cookieLoader,
        _cookieSetter = cookieSetter,
        _accountIdLoader =
            accountIdLoader ?? AcademicAccountStore().loadStudentId,
        _clock = clock ?? DateTime.now {
    _http.connectionTimeout = _connectTimeout;
  }

  static const _connectTimeout = Duration(seconds: 15);
  static const _responseTimeout = Duration(seconds: 30);
  static const fidEnc = '00bae7f2bdea485a';
  static const _clientId = 'mK5y895566T96v8Z52z5M3J85K8Miv38';
  static const _submitInterval = Duration(seconds: 10);
  static const _indexPath = '/front/third/apps/seat/index';
  static const _selectPath = '/front/third/apps/seat/select';

  final HttpClient _http;
  final SessionCookieJar _jar;
  final Uri serviceUri;
  final Uri ssoUri;
  final Uri oauthRedirectUri;
  final Future<List<SessionCookie>> Function(Uri)? _cookieLoader;
  final Future<void> Function(SessionCookie)? _cookieSetter;
  final Future<String?> Function() _accountIdLoader;
  final DateTime Function() _clock;
  AcademicSessionCookieStore _cookies = AcademicSessionCookieStore();
  final Set<String> _loadedScopes = {};
  Map<String, dynamic>? _user;
  Future<Map<String, dynamic>>? _bootstrapping;
  DateTime? _lastSubmit;
  bool _submitting = false;

  Map<String, dynamic>? get user => _user == null ? null : Map.of(_user!);

  void dispose() => _http.close(force: true);

  static String today([DateTime? now]) {
    final date = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Reuse a verified office session or exchange the existing SHU SSO cookie.
  /// A different student account clears only this business session.
  Future<Map<String, dynamic>> bootstrap() =>
      _bootstrapping ??= _bootstrap().whenComplete(() => _bootstrapping = null);

  Future<Map<String, dynamic>> _bootstrap() async {
    await _loadCookies(_indexUri());
    if (_user != null || _cookies.headerFor(_indexUri()).isNotEmpty) {
      try {
        return await _verifyOfficeUser();
      } on ChaoxingBookingException catch (error) {
        if (error is _AccountMismatchException ||
            error.kind != ChaoxingFailureKind.loginRequired) {
          rethrow;
        }
        _user = null;
      }
    }
    await _exchangeSso();
    return _verifyOfficeUser();
  }

  /// Returns the API's data object, including curReserves and nearReserves.
  Future<Map<String, dynamic>> home() async {
    final data = _object((await _api('GET', '/data/apps/seat/index', query: {
      'fidEnc': fidEnc,
      'r': _clock().microsecondsSinceEpoch.toString(),
    }))['data']);
    if (data == null) throw _protocolError();
    return data;
  }

  /// Returns today's seatRoomList, with the server's level names and capacity.
  Future<List<Map<String, dynamic>>> rooms() async {
    final data =
        _object((await _api('GET', '/data/apps/seat/room/list', query: {
      'time': '',
      'cpage': '1',
      'pageSize': '100',
      'firstLevelName': '',
      'secondLevelName': '',
      'thirdLevelName': '',
      'day': today(_clock()),
      'deptIdEnc': fidEnc,
    }))['data']);
    if (data == null || data['seatRoomList'] is! List) throw _protocolError();
    return _objects(data['seatRoomList']);
  }

  /// Seats are derived from the room's number range minus occupied numbers.
  /// The server can still reject an individual seat during submission.
  Future<Map<String, dynamic>> availability({
    required String roomId,
    required String start,
    required String end,
  }) async {
    final interval = _validateInterval(start, end);
    final id = _requireId(roomId, '房间');
    final day = today(_clock());
    final roomData =
        _object((await _api('POST', '/data/apps/seat/room/info', form: {
      'id': id,
      'toDay': day,
      'fidEnc': fidEnc,
      'queryReserve': 'true',
    }))['data']);
    final room = _object(roomData?['seatRoom']);
    final capacity = _positiveInt(room?['capacity']);
    final first = _positiveInt(room?['startSeatNum']) ?? 1;
    if (room == null || capacity == null) throw _protocolError();
    if (today(_clock()) != day) throw _dayChanged();
    final usedData =
        _object((await _api('POST', '/data/apps/seat/getusedseatnums', form: {
      'roomId': id,
      'startTime': interval.start,
      'endTime': interval.end,
      'day': day,
      'fidEnc': fidEnc,
    }))['data']);
    if (usedData == null ||
        (usedData['seatReserves'] != null &&
            usedData['seatReserves'] is! List)) {
      throw _protocolError();
    }
    final used = <String>{
      for (final reserve in _objects(usedData['seatReserves']))
        if (_string(reserve['seatNum']) case final String number)
          _normalizeSeat(number),
    }.toList()
      ..sort();
    final occupied = used.toSet();
    final available = [
      for (var number = first; number < first + capacity; number++)
        if (!occupied.contains(number.toString().padLeft(3, '0')))
          number.toString().padLeft(3, '0'),
    ];
    return {
      'day': day,
      'room': room,
      'used': used,
      'available': available,
      'total': capacity,
      'availableCount': available.length,
    };
  }

  /// Creates one seat reservation. Never retries an uncertain submission.
  Future<String> submit({
    required String roomId,
    required String start,
    required String end,
    required String seatNum,
  }) async {
    if (_submitting) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '预约正在提交，请等待结果');
    }
    final last = _lastSubmit;
    if (last != null && _clock().difference(last) < _submitInterval) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '同一用户 10 秒内只能提交一次，请稍后重试');
    }
    final interval = _validateInterval(start, end);
    final id = _requireId(roomId, '房间');
    final seat = _normalizeSeat(_requireId(seatNum, '座位'));
    final day = today(_clock());
    _submitting = true;
    _lastSubmit = _clock();
    try {
      await _ensureSession();
      final selectUri =
          serviceUri.resolve(_selectPath).replace(queryParameters: {
        'deptIdEnc': fidEnc,
        'id': id,
        'day': day,
        'backLevel': '2',
        'fidEnc': fidEnc,
      });
      final select = await _request('GET', selectUri,
          referer: _indexUri(), followOfficeRedirects: true);
      if (select.uri.path.startsWith('/front/apps/reserve/error')) {
        throw ChaoxingBookingException(ChaoxingFailureKind.business,
            select.uri.queryParameters['msg'] ?? '当前区域不可预约');
      }
      _requireHttpSuccess(select);
      final match = RegExp(
              r'''id=["']submit_enc["']\s+value=["']([^"']+)["']''',
              caseSensitive: false)
          .firstMatch(select.body);
      final salt = match?.group(1)?.trim();
      if (salt == null || salt.isEmpty) throw _protocolError();
      if (today(_clock()) != day) throw _dayChanged();
      final fields = <String, String>{
        'captcha': '',
        'day': day,
        'deptIdEnc': fidEnc,
        'endTime': interval.end,
        'roomId': id,
        'seatNum': seat,
        'startTime': interval.start,
        'wyToken': '',
      };
      final form = {...fields, 'enc': buildEnc(fields, salt)};
      final response = await _api('POST', '/data/apps/seat/submit',
          form: form,
          referer: selectUri,
          uncertainWriteMessage: '预约提交结果未确认，请先查看我的预约，勿直接重试',
          expectedDay: day);
      final reserve = _object(_object(response['data'])?['seatReserve']);
      final reserveId = _string(reserve?['id']);
      if (reserveId == null) {
        throw const ChaoxingBookingException(
            ChaoxingFailureKind.uncertain, '预约结果尚未确认，请先查看我的预约，勿直接重试');
      }
      return reserveId;
    } finally {
      _submitting = false;
    }
  }

  Future<void> cancel(String reserveId) async {
    final id = _requireId(reserveId, '预约');
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '预约 ID 无效');
    }
    await _api('GET', '/data/apps/seat/cancel',
        query: {'id': id}, uncertainWriteMessage: '取消结果未确认，请先刷新我的预约，勿直接重试');
  }

  /// Sign a reservation in from the seat operation page. The server decides
  /// whether the current time and account are eligible.
  Future<void> sign(String reserveId) async {
    final id = _requireId(reserveId, '预约');
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '预约 ID 无效');
    }
    await _api('GET', '/data/apps/seat/sign',
        query: {'id': id},
        referer: serviceUri.resolve('/front/apps/seat/code'),
        uncertainWriteMessage: '签到结果未确认，请先刷新我的预约，勿直接重试');
  }

  /// Reconstructs the seat page from the current reservation, without scanning
  /// a physical QR code. The observed reads do not obtain a device position or
  /// satisfy a browser-side location check; the server decides eligibility.
  Future<void> signWithSeatPage({
    required String reserveId,
    required String roomId,
    required String seatNum,
    String? deptId,
  }) async {
    final id = _requireId(reserveId, '预约');
    final room = _requireId(roomId, '房间');
    final seat = _requireId(seatNum, '座位');
    if (!RegExp(r'^\d+$').hasMatch(id) ||
        !RegExp(r'^\d+$').hasMatch(room) ||
        !RegExp(r'^\d+$').hasMatch(seat)) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '预约的房间、座位或编号无效');
    }
    final seatNumber = int.tryParse(seat);
    if (seatNumber == null || seatNumber <= 0) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '预约座位号无效');
    }
    final paddedSeat = seatNumber.toString().padLeft(3, '0');
    final querySeat = seatNumber.toString();

    // The QR page checks occupancy with a three-digit seat number first.
    final check = _object((await _api('GET', '/data/apps/seat/check/exist',
        query: {'seatNum': paddedSeat, 'roomId': room}))['data']);
    final occupied = int.tryParse(check?['existCount']?.toString() ?? '');
    if (occupied == null || occupied < 0) throw _protocolError();
    if (occupied > 0) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '该座位已有未退座记录，无法签到');
    }

    final codeUri = serviceUri
        .resolve('/front/apps/seat/code')
        .replace(queryParameters: {'id': room, 'seatNum': querySeat});
    final page = await _request('GET', codeUri,
        referer: _indexUri(), followOfficeRedirects: true);
    _requireHttpSuccess(page);
    if (page.uri.path != '/front/apps/seat/code' &&
        page.uri.path != '/front/third/apps/seat/code') {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '未能进入当前座位操作页，请稍后重试');
    }

    // reserve/info uses roomId and an unpadded seat, while sign uses reserveId.
    final detail = _object((await _api('GET', '/data/apps/seat/reserve/info',
        query: {'id': room, 'seatNum': querySeat}, referer: page.uri))['data']);
    final reserve = _object(detail?['seatReserve']);
    if (_string(reserve?['id']) != id ||
        _string(reserve?['roomId']) != room ||
        _normalizeSeat(_string(reserve?['seatNum']) ?? '') != paddedSeat ||
        _string(reserve?['status']) != '0') {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '座位操作页与当前预约不一致，请刷新后重试');
    }
    final current = _objects((await home())['curReserves']);
    if (!current.any((item) =>
        _string(item['id']) == id &&
        _string(item['roomId']) == room &&
        _normalizeSeat(_string(item['seatNum']) ?? '') == paddedSeat)) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '当前账号的预约已变化，请刷新后重试');
    }

    // This POST only reads locationType. It sends no coordinates or fake proof.
    await _api('POST', '/api/data/apps/reserve/wx/location', referer: page.uri);
    final seatConfig = _object(detail?['seatConfig']);
    final positionMode =
        int.tryParse(seatConfig?['isPosition']?.toString() ?? '');
    if (positionMode == 1 || positionMode == 2 || positionMode == 7) {
      final department =
          _string(seatConfig?['deptId']) ?? _string(deptId) ?? '35480';
      // Reading addressArr does not compare it with a real device location.
      await _api('GET', '/data/apps/seat/address',
          query: {'deptId': department, 'roomId': room}, referer: page.uri);
    }
    await _api('GET', '/data/apps/seat/sign',
        query: {'id': id},
        referer: page.uri,
        uncertainWriteMessage: '签到结果未确认，请先刷新我的预约，勿直接重试');
  }

  /// The seat page calls signback with the reservation ID to release a seat.
  /// The response has no documented final state, so callers must refresh home.
  Future<void> signback(String reserveId) async {
    final id = _requireId(reserveId, '预约');
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '预约 ID 无效');
    }
    await _api('POST', '/data/apps/seat/signback',
        form: {'id': id}, uncertainWriteMessage: '退座结果未确认，请先刷新我的预约，勿直接重试');
  }

  /// Removes only Chaoxing business cookies; SHU SSO belongs to account login.
  Future<void> clearSession() async {
    _user = null;
    _cookies = AcademicSessionCookieStore();
    _loadedScopes.clear();
    final values = <SessionCookie>[];
    if (_cookieLoader case final loader?) {
      // Keep the injected URI loader available for transport tests.
      for (final uri in [
        serviceUri,
        serviceUri.resolve(_indexPath),
        serviceUri.resolve('/data/apps/seat/index'),
        Uri.parse('https://passport2-api.chaoxing.com'),
        Uri.parse('https://passport2-api.chaoxing.com/api/v2/login6'),
        oauthRedirectUri,
      ]) {
        values.addAll(await loader(uri));
      }
    } else {
      values.addAll(await _jar.getCookiesForDomainTree(domain: 'chaoxing.com'));
      values.addAll(
          await _jar.getCookiesForDomainTree(domain: oauthRedirectUri.host));
    }
    final seen = <(String, String, String)>{};
    for (final cookie in values) {
      final domain =
          cookie.domain.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
      if (domain != 'chaoxing.com' &&
          !domain.endsWith('.chaoxing.com') &&
          domain != oauthRedirectUri.host) {
        continue;
      }
      if (!seen.add((domain, cookie.path, cookie.name))) continue;
      final expired = SessionCookie(
        name: cookie.name,
        value: '',
        domain: cookie.domain,
        path: cookie.path,
      );
      await (_cookieSetter?.call(expired) ?? _jar.setCookie(expired));
    }
  }

  Future<Map<String, dynamic>> _verifyOfficeUser() async {
    final response =
        await _request('GET', _indexUri(), followOfficeRedirects: true);
    _requireHttpSuccess(response);
    final match =
        RegExp(r'userLoginInfo\s*=\s*(\{.*?\})\s*\|\|\s*\{\}', dotAll: true)
            .firstMatch(response.body);
    Map<String, dynamic>? info;
    try {
      info = _object(jsonDecode(match?.group(1) ?? ''));
    } on Object {
      // Login pages and changed page contracts must not be treated as valid.
    }
    final person = _object(info?['userInfo']);
    if (_string(person?['uid']) == null) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.loginRequired, '图书馆座位预约需要重新登录');
    }
    final verified = {
      'uid': _string(person?['uid'])!,
      'uname': _string(person?['uname']) ?? '',
      'sno': _string(person?['sno']) ?? '',
    };
    await _checkAccount(verified);
    _user = verified;
    return Map.of(verified);
  }

  Future<void> _checkAccount(Map<String, dynamic> user) async {
    final expected = (await _accountIdLoader())?.trim();
    if (expected == null || expected.isEmpty) return;
    final actual = _string(user['sno']);
    if (actual != null && actual.toLowerCase() == expected.toLowerCase()) {
      return;
    }
    await clearSession();
    throw const _AccountMismatchException();
  }

  Future<void> _ensureSession() async {
    if (_user == null) {
      await bootstrap();
    } else {
      await _checkAccount(_user!);
    }
  }

  Future<void> _exchangeSso() async {
    final authorizeUri = ssoUri.resolve('/oauth/authorize');
    await _loadCookies(authorizeUri);
    final ssoCookie = _cookies.headerFor(authorizeUri);
    if (!ssoCookie.split(';').any((part) =>
        part.trimLeft().startsWith('${WeComConstants.sessionCookieName}='))) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.loginRequired, '请先登录校园账号，再使用图书馆座位预约',
          ssoExpired: true);
    }
    final authorize = authorizeUri.replace(queryParameters: {
      'client_id': _clientId,
      'response_type': 'code',
      'scope': '',
      'redirect_uri': oauthRedirectUri.toString(),
      'state': '',
    });
    var response = await _request('GET', authorize);
    var next = response.location;
    if (!_isRedirect(response.status) || next == null) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.uncertain, '暂时无法取得图书馆座位预约授权，请稍后重试');
    }
    if (next.path.startsWith('/oauth2/login/')) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.loginRequired, '校园登录已失效，请重新登录',
          ssoExpired: true);
    }
    if (next.host != oauthRedirectUri.host ||
        _string(next.queryParameters['code']) == null) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.uncertain, '图书馆座位预约授权回调无法识别，请稍后重试');
    }
    for (var hop = 0; hop < 10; hop++) {
      final target = next == null
          ? null
          : secureExchangeRedirect(next, callbackHost: oauthRedirectUri.host);
      if (target == null || !_allowedExchangeUri(target)) {
        throw const ChaoxingBookingException(
            ChaoxingFailureKind.uncertain, '图书馆座位预约登录跳转异常，请稍后重试');
      }
      response = await _request('GET', target);
      if (!_isRedirect(response.status)) {
        if (_isChaoxingHost(response.uri.host) && response.status == 200) {
          return;
        }
        throw const ChaoxingBookingException(
            ChaoxingFailureKind.uncertain, '图书馆座位预约会话未建立，请稍后重试');
      }
      next = response.location;
    }
    throw const ChaoxingBookingException(
        ChaoxingFailureKind.uncertain, '图书馆座位预约登录跳转次数过多，请稍后重试');
  }

  /// The 5read callback sometimes returns an HTTP URL for Chaoxing's
  /// passport endpoint. Keep the one-time code on TLS for known OAuth hosts.
  static Uri secureExchangeRedirect(Uri uri, {required String callbackHost}) {
    final host = uri.host.toLowerCase();
    final knownHost = host == callbackHost.toLowerCase() ||
        host == 'chaoxing.com' ||
        host.endsWith('.chaoxing.com');
    if (uri.scheme != 'http' ||
        uri.userInfo.isNotEmpty ||
        !knownHost ||
        (uri.hasPort && uri.port != 80)) {
      return uri;
    }
    return uri.replace(scheme: 'https', port: 443);
  }

  bool _allowedExchangeUri(Uri uri) {
    if (uri.userInfo.isNotEmpty) return false;
    final testOrigin = serviceUri.host == ssoUri.host &&
        serviceUri.host == oauthRedirectUri.host;
    if (testOrigin && uri.host == serviceUri.host) {
      return uri.scheme == serviceUri.scheme;
    }
    return uri.scheme == 'https' &&
        (uri.host == oauthRedirectUri.host || _isChaoxingHost(uri.host));
  }

  bool _isChaoxingHost(String host) =>
      host == 'chaoxing.com' ||
      host.endsWith('.chaoxing.com') ||
      (serviceUri.host != 'office.chaoxing.com' && host == serviceUri.host);

  Future<Map<String, dynamic>> _api(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String>? form,
    Uri? referer,
    String? uncertainWriteMessage,
    String? expectedDay,
  }) async {
    await _ensureSession();
    if (expectedDay != null && today(_clock()) != expectedDay) {
      throw _dayChanged();
    }
    final uri = serviceUri.resolve(path).replace(queryParameters: query);
    final response = await _request(method, uri,
        form: form,
        referer: referer ?? _indexUri(),
        uncertainWriteMessage: uncertainWriteMessage);
    _requireHttpSuccess(response);
    Map<String, dynamic>? envelope;
    try {
      envelope = _object(jsonDecode(response.body));
    } on Object {
      throw _protocolError();
    }
    if (envelope == null || envelope['success'] is! bool) {
      throw _protocolError();
    }
    if (envelope['success'] != true) {
      throw ChaoxingBookingException(
          ChaoxingFailureKind.business,
          _string(envelope['msg']) ??
              _string(envelope['message']) ??
              '图书馆座位预约服务拒绝了本次操作');
    }
    return envelope;
  }

  Future<_CxResponse> _request(
    String method,
    Uri uri, {
    Map<String, String>? form,
    Uri? referer,
    bool followOfficeRedirects = false,
    String? uncertainWriteMessage,
  }) async {
    var response = await _send(method, uri,
        form: form,
        referer: referer,
        uncertainWriteMessage: uncertainWriteMessage);
    if (!followOfficeRedirects) return response;
    for (var hop = 0; hop < 8 && _isRedirect(response.status); hop++) {
      final next = response.location;
      if (next == null ||
          next.host != serviceUri.host ||
          next.scheme != serviceUri.scheme ||
          next.userInfo.isNotEmpty) {
        throw const ChaoxingBookingException(
            ChaoxingFailureKind.loginRequired, '图书馆座位预约需要重新登录');
      }
      response = await _send('GET', next, referer: referer);
    }
    if (_isRedirect(response.status)) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.uncertain, '图书馆座位预约页面跳转次数过多，请稍后重试');
    }
    return response;
  }

  Future<_CxResponse> _send(
    String method,
    Uri uri, {
    Map<String, String>? form,
    Uri? referer,
    String? uncertainWriteMessage,
  }) async {
    try {
      await _loadCookies(uri);
      final request = await _http.openUrl(method, uri).timeout(_connectTimeout);
      request.followRedirects = false;
      request.headers
          .set(HttpHeaders.userAgentHeader, ClientUserAgent.mobileBrowser);
      request.headers.set(
          HttpHeaders.acceptHeader,
          uri.host == serviceUri.host
              ? 'application/json, text/javascript, */*; q=0.01'
              : 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      if (uri.host == serviceUri.host) {
        request.headers.set('X-Requested-With', 'XMLHttpRequest');
        request.headers.set(
            HttpHeaders.refererHeader, (referer ?? _indexUri()).toString());
      }
      final cookieHeader = _cookies.headerFor(uri);
      if (cookieHeader.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      }
      if (form != null) {
        request.headers.set('Origin', serviceUri.origin);
        request.headers.contentType = ContentType(
            'application', 'x-www-form-urlencoded',
            charset: 'UTF-8');
        request.write(Uri(queryParameters: form).query);
      }
      final received = await request.close().timeout(_responseTimeout);
      await _saveCookies(
          uri, received.headers[HttpHeaders.setCookieHeader] ?? const []);
      final location = received.headers.value(HttpHeaders.locationHeader);
      final next = location == null ? null : uri.resolve(location);
      if (_isRedirect(received.statusCode) && next != null) {
        try {
          await received.drain<void>().timeout(_responseTimeout);
        } on Object {
          // Redirect content is unused; a truncated body must not discard a
          // valid Location and the session cookies already received.
        }
        return _CxResponse(received.statusCode, '', next, uri);
      }
      final body = await utf8.decodeStream(received).timeout(_responseTimeout);
      return _CxResponse(received.statusCode, body, next, uri);
    } on TimeoutException {
      throw ChaoxingBookingException(
          uncertainWriteMessage != null
              ? ChaoxingFailureKind.uncertain
              : ChaoxingFailureKind.unreachable,
          uncertainWriteMessage ?? '${_requestStage(uri)}连接超时，请稍后重试');
    } on SocketException {
      throw ChaoxingBookingException(
          uncertainWriteMessage != null
              ? ChaoxingFailureKind.uncertain
              : ChaoxingFailureKind.unreachable,
          uncertainWriteMessage ?? '${_requestStage(uri)}暂时无法访问，请检查网络后重试');
    } on HttpException {
      throw ChaoxingBookingException(
          uncertainWriteMessage != null
              ? ChaoxingFailureKind.uncertain
              : ChaoxingFailureKind.unreachable,
          uncertainWriteMessage ?? '${_requestStage(uri)}连接中断，请稍后重试');
    } on HandshakeException {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.unreachable, '图书馆座位预约安全连接失败，请稍后重试');
    }
  }

  String _requestStage(Uri uri) {
    if (uri.host == ssoUri.host) return '学校统一认证';
    if (uri.host == oauthRedirectUri.host) return '图书馆授权';
    if (uri.host == serviceUri.host) {
      if (uri.path.startsWith('/front/')) return '图书馆登录校验';
      if (uri.path == '/data/apps/seat/room/list') return '图书馆分区列表';
      return '图书馆预约服务';
    }
    return '图书馆登录';
  }

  Future<void> _loadCookies(Uri uri) async {
    final scope = '${uri.origin}${uri.path}';
    if (_loadedScopes.contains(scope)) return;
    final entries =
        await (_cookieLoader?.call(uri) ?? _jar.getCookies(domain: uri));
    _loadedScopes.add(scope);
    for (final entry in entries) {
      if (entry.domain.isEmpty || entry.value.isEmpty) continue;
      final cookie = Cookie(entry.name, entry.value)
        ..domain = entry.domain
        ..path = entry.path;
      _cookies.save(uri, [cookie]);
    }
  }

  Future<void> _saveCookies(Uri source, List<String> headers) async {
    for (final value in headers) {
      Cookie cookie;
      try {
        cookie = Cookie.fromSetCookieValue(value);
      } on Exception {
        // Some 5read responses include malformed legacy Set-Cookie values.
        // One unusable cookie must not discard the valid OAuth redirect.
        continue;
      }
      if (cookie.name.isEmpty) continue;
      final domain = (cookie.domain ?? source.host)
          .replaceFirst(RegExp(r'^\.'), '')
          .toLowerCase();
      if (source.host != domain && !source.host.endsWith('.$domain')) continue;
      cookie.domain = domain;
      cookie.path ??= '/';
      _cookies.save(source, [cookie]);
      if (!_isChaoxingHost(domain) && domain != oauthRedirectUri.host) continue;
      final record = SessionCookie(
        name: cookie.name,
        value: cookie.expires?.isBefore(_clock()) == true ? '' : cookie.value,
        domain: domain,
        path: cookie.path!,
      );
      await (_cookieSetter?.call(record) ?? _jar.setCookie(record));
    }
  }

  Uri _indexUri() => serviceUri.resolve(_indexPath).replace(queryParameters: {
        'fidEnc': fidEnc,
      });

  void _requireHttpSuccess(_CxResponse response) {
    if (response.status == 401 || _isRedirect(response.status)) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.loginRequired, '图书馆座位预约需要重新登录');
    }
    if (response.status != 200) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.unreachable, '图书馆座位预约服务暂时不可用，请稍后重试');
    }
  }

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  static Map<String, dynamic>? _object(Object? value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : null;

  static List<Map<String, dynamic>> _objects(Object? value) => value is List
      ? [
          for (final item in value)
            if (_object(item) case final Map<String, dynamic> object) object
        ]
      : [];

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _positiveInt(Object? value) {
    final number = int.tryParse(value?.toString() ?? '');
    return number == null || number <= 0 ? null : number;
  }

  static String _requireId(String value, String label) {
    final id = value.trim();
    if (id.isEmpty || id.contains(RegExp(r'[\r\n]'))) {
      throw ChaoxingBookingException(
          ChaoxingFailureKind.business, '$label ID 无效');
    }
    return id;
  }

  static String _normalizeSeat(String value) {
    final number = int.tryParse(value);
    return number == null ? value : number.toString().padLeft(3, '0');
  }

  static ({String start, String end}) _validateInterval(
      String start, String end) {
    String normalized(String value) {
      final match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(value.trim());
      final hour = int.tryParse(match?.group(1) ?? '');
      if (hour == null || hour > 23) {
        throw const ChaoxingBookingException(
            ChaoxingFailureKind.business, '请选择有效的预约时段');
      }
      return '${hour.toString().padLeft(2, '0')}:${match!.group(2)}';
    }

    final from = normalized(start);
    final to = normalized(end);
    int minutes(String text) =>
        int.parse(text.substring(0, 2)) * 60 + int.parse(text.substring(3));
    final first = minutes(from);
    final last = minutes(to);
    if (first < 8 * 60 ||
        last > 22 * 60 ||
        first % 30 != 0 ||
        last % 30 != 0 ||
        last - first < 60) {
      throw const ChaoxingBookingException(
          ChaoxingFailureKind.business, '预约时段需在 08:00–22:00，按半小时选择，且至少预约 1 小时');
    }
    return (start: from, end: to);
  }

  static ChaoxingBookingException _protocolError() =>
      const ChaoxingBookingException(
          ChaoxingFailureKind.uncertain, '图书馆座位预约返回了无法识别的内容，请稍后重试');

  static ChaoxingBookingException _dayChanged() =>
      const ChaoxingBookingException(
          ChaoxingFailureKind.business, '日期已经变化，请重新选择今天的预约时段');

  /// PoC signature: sorted `[key=value]` pairs plus `[fresh select salt]`.
  static String buildEnc(Map<String, String> fields, String salt) {
    const keys = [
      'captcha',
      'day',
      'deptIdEnc',
      'endTime',
      'roomId',
      'seatNum',
      'startTime',
      'wyToken',
    ];
    if (salt.trim().isEmpty ||
        fields.length != keys.length ||
        keys.any((key) => !fields.containsKey(key))) {
      throw _protocolError();
    }
    final plain =
        '${keys.map((key) => '[$key=${fields[key]}]').join()}[${salt.trim()}]';
    final digest = MD5Digest().process(Uint8List.fromList(utf8.encode(plain)));
    return digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _CxResponse {
  const _CxResponse(this.status, this.body, this.location, this.uri);

  final int status;
  final String body;
  final Uri? location;
  final Uri uri;
}
