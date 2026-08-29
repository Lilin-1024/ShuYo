import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/academic_url_resolver.dart';
import '../../core/client_user_agent.dart';
import '../../core/forum_url_resolver.dart';

enum AcademicVerificationMethod { wecom, sms }

enum _NativeAuthTarget { academic, forum }

class AcademicLoginChallenge {
  const AcademicLoginChallenge({required this.methods});
  final Map<AcademicVerificationMethod, String> methods;
}

class AcademicLoginResult {
  const AcademicLoginResult({this.challenge, this.callbackUri});

  final AcademicLoginChallenge? challenge;
  final Uri? callbackUri;
}

class AcademicNativeAuthException implements Exception {
  const AcademicNativeAuthException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}

class AcademicPasswordEncryptor {
  const AcademicPasswordEncryptor._();

  static const _rsaModulusHex =
      'e5fda0a0465f5fff838df4c7b0a159d5e7c38b394d802c18b614a739c88b1f4a'
      '98af2b17bb03a162b498c7bdadd6a4cee0bd53a29cc7a1a7a89fd9434891b68d'
      'fa99567f9230a84571b0d6697a2c5ce06b1b63d757124dd6b518f0192c832f24'
      'b3104487fe4a49568c4eee28d162a53eda8491c1304d78f3a4d47f8b450a2481';

  static String encrypt(String password) {
    final publicKey = RSAPublicKey(
      BigInt.parse(_rsaModulusHex, radix: 16),
      BigInt.from(65537),
    );
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    final encrypted = cipher.process(Uint8List.fromList(utf8.encode(password)));
    return base64Encode(encrypted);
  }
}

class AcademicNativeAuthService {
  AcademicNativeAuthService({HttpClient? httpClient})
      : _target = _NativeAuthTarget.academic,
        _cookieManager = WebViewCookieManager(),
        _client = httpClient ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
  }

  AcademicNativeAuthService.forForum({
    HttpClient? httpClient,
    WebViewCookieManager? cookieManager,
  })  : _target = _NativeAuthTarget.forum,
        _cookieManager = cookieManager ?? WebViewCookieManager(),
        _client = httpClient ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
  }

  static const _newssoPathMarker = '/oauth2/login/';
  static Uri get _academicEntry => AcademicUrlResolver.entryUri;
  static const _webVpnPortal = 'https://webvpn.shu.edu.cn';
  static const _webVpnHost = 'webvpn.shu.edu.cn';
  final _NativeAuthTarget _target;
  final WebViewCookieManager _cookieManager;
  final HttpClient _client;
  final List<_StoredCookie> _cookies = [];
  bool _webViewCookiesImported = false;

  Uri? _loginUri;
  String? _params;
  String? _username;
  String? _encryptedPassword;

  void dispose() => _client.close(force: true);

  /// Transfers the native authentication cookies to the shared WebView store
  /// before the OAuth callback is loaded there.
  Future<void> installCookiesInWebView() async {
    final manager = WebViewCookieManager();
    for (final stored in _cookies) {
      final cookie = stored.cookie;
      if (cookie.value.isEmpty) continue;
      await manager.setCookie(
        WebViewCookie(
          name: cookie.name,
          value: cookie.value,
          domain: stored.domain,
          path: stored.path,
        ),
      );
    }
  }

  Future<AcademicLoginResult> login({
    required String username,
    required String password,
  }) async {
    _clearChallenge();
    final loginUri = await _discoverLoginUri();
    final params = _extractParams(loginUri);
    final encryptedPassword = AcademicPasswordEncryptor.encrypt(password);
    final response = await _jsonRequest(
      'POST',
      loginUri.resolve('/oauth/userLogin'),
      body: {
        'username': username,
        'password': encryptedPassword,
        'params': params,
      },
      referer: loginUri,
    );
    _requireSuccess(response);

    if (response['twoStepRequired'] == true) {
      _loginUri = loginUri;
      _params = params;
      _username = username;
      _encryptedPassword = encryptedPassword;
      final rawMethods = response['twoStepMethods'];
      final methods = <AcademicVerificationMethod, String>{};
      if (rawMethods is Map) {
        for (final entry in rawMethods.entries) {
          final method = _methodFromWire(entry.key.toString());
          if (method != null) methods[method] = entry.value?.toString() ?? '';
        }
      }
      if (methods.isEmpty) {
        throw const AcademicNativeAuthException(
          'noTwoStepMethod',
          '学校未返回可用的验证方式',
        );
      }
      return AcademicLoginResult(
        challenge: AcademicLoginChallenge(methods: methods),
      );
    }

    final redirect = response['redirectUri']?.toString();
    if (redirect == null || redirect.isEmpty) {
      throw const AcademicNativeAuthException(
        'missingRedirect',
        '登录成功，但学校未返回授权地址',
      );
    }
    final callbackUri = loginUri.resolve(redirect);
    _validateUri(callbackUri);
    _clearChallenge();
    return AcademicLoginResult(callbackUri: callbackUri);
  }

  Future<void> sendCode(AcademicVerificationMethod method) async {
    final loginUri = _requireChallenge();
    final response = await _jsonRequest(
      'POST',
      loginUri.resolve('/oauth/twoStep/send'),
      body: {'method': method.name},
      referer: loginUri,
    );
    _requireSuccess(response);
  }

  Future<Uri> verifyCode({
    required AcademicVerificationMethod method,
    required String code,
  }) async {
    final loginUri = _requireChallenge();
    final response = await _jsonRequest(
      'POST',
      loginUri.resolve('/oauth/twoStep/verify'),
      body: {
        'username': _username,
        'password': _encryptedPassword,
        'params': _params,
        'code': code,
        'method': method.name,
      },
      referer: loginUri,
    );
    _requireSuccess(response);
    final redirect = response['redirectUri']?.toString();
    if (redirect == null || redirect.isEmpty) {
      throw const AcademicNativeAuthException(
        'missingRedirect',
        '验证成功，但学校未返回授权地址',
      );
    }
    final callbackUri = loginUri.resolve(redirect);
    _validateUri(callbackUri);
    _clearChallenge();
    return callbackUri;
  }

  Future<Uri> _discoverLoginUri() async {
    if (_target == _NativeAuthTarget.forum) {
      await _importWebViewCookies();
    }
    var uri = _target == _NativeAuthTarget.academic
        ? _academicEntry
        : ForumUrlResolver.uri('/auth/oauth2_basic');
    for (var redirects = 0; redirects < 16; redirects++) {
      final response = await _request('GET', uri);
      final next = _redirectTarget(response, uri);
      await response.drain<void>();
      if (next == null) {
        if (uri.path.contains(_newssoPathMarker)) return uri;
        if (_target == _NativeAuthTarget.academic && uri.host == _webVpnHost) {
          uri = await _startWebVpnOAuth();
          continue;
        }
        if (_target == _NativeAuthTarget.forum &&
            ForumUrlResolver.usesWebVpn &&
            uri.host == _webVpnHost) {
          throw const AcademicNativeAuthException(
            'webVpnLoginRequired',
            '使用 WebVPN 登录论坛前，请先完成上大校园账户登录',
          );
        }
        throw const AcademicNativeAuthException(
          'loginPageNotFound',
          '无法取得该服务的统一认证入口',
        );
      }
      if (next.path.contains(_newssoPathMarker)) {
        final loginPage = await _request('GET', next);
        final loginRedirect = _redirectTarget(loginPage, next);
        await loginPage.drain<void>();
        return loginRedirect ?? next;
      }
      uri = next;
    }
    throw const AcademicNativeAuthException('tooManyRedirects', '认证入口跳转次数过多');
  }

  @visibleForTesting
  static bool isForumOAuthCallback(Uri uri) {
    return ForumUrlResolver.isKnownForumHost(uri.host.toLowerCase()) &&
        uri.path == '/auth/oauth2_basic/callback' &&
        uri.queryParameters.containsKey('code') &&
        uri.queryParameters.containsKey('state');
  }

  Future<void> _importWebViewCookies() async {
    if (_webViewCookiesImported) return;
    _webViewCookiesImported = true;
    final domains = <Uri>{
      ForumUrlResolver.baseUri,
      Uri.parse(ForumUrlResolver.webVpnPortalUrl),
      Uri.parse('https://oauth.shu.edu.cn'),
      Uri.parse('https://https-oauth-shu-edu-cn-443.webvpn.shu.edu.cn'),
    };
    for (final domain in domains) {
      List<WebViewCookie> cookies;
      try {
        cookies = await _cookieManager.getCookies(domain: domain);
      } on Object {
        continue;
      }
      for (final cookie in cookies) {
        if (cookie.name.isEmpty || cookie.value.isEmpty) continue;
        final nativeCookie = Cookie(cookie.name, cookie.value)
          ..domain = cookie.domain
          ..path = cookie.path;
        _saveCookies(domain, [nativeCookie]);
      }
    }
  }

  Future<Map<String, dynamic>> _jsonRequest(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
    Uri? referer,
  }) async {
    final response = await _request(
      method,
      uri,
      body: body == null ? null : jsonEncode(body),
      referer: referer,
    );
    final text = await utf8.decodeStream(response);
    Map<String, dynamic> json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } on Object {
      throw AcademicNativeAuthException(
        'invalidResponse',
        '学校认证服务返回了无法识别的内容（HTTP ${response.statusCode}）',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _debugJsonError(uri, response.statusCode, json);
      final code = json['message']?.toString() ?? 'http${response.statusCode}';
      throw AcademicNativeAuthException(code, messageForCode(code));
    }
    return json;
  }

  Future<Uri> _startWebVpnOAuth() async {
    final portal = Uri.parse(_webVpnPortal);
    final methodsResponse = await _jsonRequest(
      'GET',
      portal.resolve('/api/access/authentication/list?type=Login'),
      referer: portal.resolve('/auth/login'),
    );
    if (methodsResponse['code'] != 0) {
      throw const AcademicNativeAuthException(
        'webVpnAuthMethodsFailed',
        '无法取得 WebVPN 认证方式',
      );
    }
    final data = methodsResponse['data'];
    final list = data is Map ? data['list'] : null;
    Map<dynamic, dynamic>? oauthMethod;
    if (list is List) {
      for (final item in list) {
        if (item is Map && item['authType'] == 5) {
          oauthMethod = item;
          break;
        }
      }
    }
    final externalId = oauthMethod?['externalId']?.toString();
    if (externalId == null || externalId.isEmpty) {
      throw const AcademicNativeAuthException(
        'webVpnOAuthUnavailable',
        'WebVPN 当前未提供上海大学统一认证',
      );
    }
    final state =
        base64Encode(utf8.encode(jsonEncode({'externalId': externalId})));
    final callbackUrl = portal.resolve('/callback/oauth2').toString();
    final startResponse = await _jsonRequest(
      'POST',
      portal.resolve('/api/access/auth/start'),
      body: {
        'externalId': externalId,
        'data': jsonEncode({
          'callbackUrl': callbackUrl,
          'state': state,
        }),
      },
      referer: portal.resolve('/auth/login'),
    );
    if (startResponse['code'] != 0) {
      throw const AcademicNativeAuthException(
        'webVpnOAuthStartFailed',
        'WebVPN 统一认证启动失败',
      );
    }
    final startData = startResponse['data'];
    final action = startData is Map ? startData['action'] : null;
    final loginUrl = action is Map ? action['login_url']?.toString() : null;
    final loginUri = loginUrl == null ? null : Uri.tryParse(loginUrl);
    if (loginUri == null) {
      throw const AcademicNativeAuthException(
        'webVpnLoginUrlMissing',
        'WebVPN 未返回统一认证地址',
      );
    }
    _validateUri(loginUri);
    return loginUri;
  }

  Future<HttpClientResponse> _request(
    String method,
    Uri uri, {
    String? body,
    Uri? referer,
  }) async {
    _validateUri(uri);
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*');
    request.headers
        .set(HttpHeaders.userAgentHeader, ClientUserAgent.mobileBrowser);
    final cookieHeader = _cookieHeader(uri);
    if (cookieHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }
    if (referer != null) {
      request.headers.set(HttpHeaders.refererHeader, referer.toString());
      request.headers.set('Origin', '${referer.scheme}://${referer.authority}');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body);
    }
    final response = await request.close();
    _saveCookies(uri, response.cookies);
    _debugRequest(method, uri, response);
    return response;
  }

  Uri? _redirectTarget(HttpClientResponse response, Uri current) {
    if (response.statusCode < 300 || response.statusCode >= 400) return null;
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (location == null || location.isEmpty) return null;
    final next = current.resolve(location);
    _validateUri(next);
    return next;
  }

  void _saveCookies(Uri source, List<Cookie> cookies) {
    for (final cookie in cookies) {
      final domain =
          (cookie.domain?.isNotEmpty == true ? cookie.domain! : source.host)
              .replaceFirst(RegExp(r'^\.'), '');
      final path = cookie.path?.isNotEmpty == true ? cookie.path! : '/';
      _cookies.removeWhere(
        (stored) =>
            stored.cookie.name == cookie.name &&
            stored.domain == domain &&
            stored.path == path,
      );
      if (cookie.value.isNotEmpty &&
          (cookie.expires == null || cookie.expires!.isAfter(DateTime.now()))) {
        _cookies.add(_StoredCookie(cookie, domain, path));
      }
    }
  }

  String _cookieHeader(Uri uri) {
    final now = DateTime.now();
    _cookies.removeWhere(
      (stored) => stored.cookie.expires?.isBefore(now) == true,
    );
    return _cookies
        .where((stored) => stored.matches(uri))
        .map((stored) => '${stored.cookie.name}=${stored.cookie.value}')
        .join('; ');
  }

  String _extractParams(Uri loginUri) {
    final index = loginUri.path.indexOf(_newssoPathMarker);
    if (index < 0) {
      throw const AcademicNativeAuthException('missingParams', '认证地址缺少登录参数');
    }
    final params = loginUri.path.substring(index + _newssoPathMarker.length);
    if (params.isEmpty) {
      throw const AcademicNativeAuthException('missingParams', '认证地址缺少登录参数');
    }
    return params;
  }

  void _requireSuccess(Map<String, dynamic> response) {
    final code = response['message']?.toString();
    if (code != 'success') {
      throw AcademicNativeAuthException(
        code ?? 'unknown',
        messageForCode(code ?? 'unknown'),
      );
    }
  }

  Uri _requireChallenge() {
    final uri = _loginUri;
    if (uri == null ||
        _params == null ||
        _username == null ||
        _encryptedPassword == null) {
      throw const AcademicNativeAuthException(
          'challengeExpired', '登录状态已失效，请重新输入账号密码');
    }
    return uri;
  }

  void _clearChallenge() {
    _loginUri = null;
    _params = null;
    _username = null;
    _encryptedPassword = null;
  }

  AcademicVerificationMethod? _methodFromWire(String value) => switch (value) {
        'wecom' => AcademicVerificationMethod.wecom,
        'sms' => AcademicVerificationMethod.sms,
        _ => null,
      };

  void _validateUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'https' ||
        (host != 'shu.edu.cn' && !host.endsWith('.shu.edu.cn'))) {
      throw const AcademicNativeAuthException(
          'unsafeRedirect', '认证服务返回了非上海大学的跳转地址');
    }
  }

  @visibleForTesting
  static String messageForCode(String code) => switch (code) {
        'badPassword' => '学号或密码错误',
        'userNotFound' => '未找到该校园账户',
        'invalidCode' => '验证码错误或已失效',
        'userLocked' => '账户已被锁定，请稍后重试',
        'ipLimitExceeded' => '登录请求过于频繁，请稍后重试',
        'sendError' || 'senderror' => '验证码发送过于频繁，请切换验证方式或稍后再试',
        'userNotAllowed' => '该账户暂时无法登录此服务',
        'internalServerError' => '学校认证服务暂时不可用',
        _ => '登录失败，请稍后重试（$code）',
      };

  void _debugRequest(String method, Uri uri, HttpClientResponse response) {
    if (!kDebugMode) return;
    final cookieNames = response.cookies.map((cookie) => cookie.name).join(',');
    debugPrint(
      '[SHU_AUTH] $method ${uri.host}${uri.path} '
      'status=${response.statusCode} cookies=[$cookieNames]',
    );
  }

  void _debugJsonError(
    Uri uri,
    int statusCode,
    Map<String, dynamic> json,
  ) {
    if (!kDebugMode) return;
    final apiCode = json['code']?.toString() ?? 'none';
    final message = json['message']?.toString() ?? 'none';
    debugPrint(
      '[SHU_AUTH] response-error ${uri.host}${uri.path} '
      'status=$statusCode apiCode=$apiCode message=$message',
    );
  }
}

class _StoredCookie {
  const _StoredCookie(this.cookie, this.domain, this.path);
  final Cookie cookie;
  final String domain;
  final String path;

  bool matches(Uri uri) {
    final hostMatches = uri.host == domain || uri.host.endsWith('.$domain');
    return hostMatches && uri.path.startsWith(path);
  }
}
