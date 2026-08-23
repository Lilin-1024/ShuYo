import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/academic_url_resolver.dart';
import '../../core/client_user_agent.dart';

@visibleForTesting
bool hasWebVpnNavigationProgressed(String? failedUrl, String? currentUrl) {
  if (failedUrl == null || currentUrl == null) return false;
  return _normalizedWebVpnUrl(failedUrl) != _normalizedWebVpnUrl(currentUrl);
}

String _normalizedWebVpnUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  final withoutFragment =
      uri.replace(fragment: '').toString().replaceFirst(RegExp(r'#$'), '');
  return withoutFragment.replaceFirst(RegExp(r'/$'), '');
}

class WebVpnOAuthCompletionPage extends StatefulWidget {
  const WebVpnOAuthCompletionPage({
    super.key,
    required this.callbackUri,
  });

  final Uri callbackUri;

  @override
  State<WebVpnOAuthCompletionPage> createState() =>
      _WebVpnOAuthCompletionPageState();
}

class _WebVpnOAuthCompletionPageState extends State<WebVpnOAuthCompletionPage> {
  static final _portalUri = Uri.parse('https://webvpn.shu.edu.cn');
  static const _resourceErrorConfirmationDelay = Duration(seconds: 3);

  late final WebViewController _controller;
  Timer? _cookiePollTimer;
  Timer? _timeoutTimer;
  Timer? _resourceErrorTimer;
  bool _completed = false;
  bool _terminalFailure = false;
  bool _openingAcademicSystem = false;
  bool _checkingTicketLogin = false;
  String? _lastNavigationUrl;
  String? _pendingResourceErrorUrl;
  int _resourceErrorGeneration = 0;
  String? _error;
  String _status = '正在建立 WebVPN 校园服务会话';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setUserAgent(ClientUserAgent.mobileBrowser)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => _handleNavigation(url),
          onPageFinished: (url) {
            _handleNavigation(url, pageFinished: true);
            unawaited(_checkLoginCookie());
          },
          onNavigationRequest: _handleNavigationRequest,
          onWebResourceError: _handleWebResourceError,
        ),
      );
    unawaited(_start());
  }

  @override
  void dispose() {
    _cookiePollTimer?.cancel();
    _timeoutTimer?.cancel();
    _resourceErrorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _error != null,
      child: Scaffold(
        appBar: AppBar(title: const Text('上大校园账户')),
        body: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.01,
                  child: WebViewWidget(controller: _controller),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _error == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 24),
                          const Text(
                            '正在完成登录',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(_status, textAlign: TextAlign.center),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 44,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('返回'),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start() async {
    await _configureAndroidWebView();
    if (!mounted) return;
    await _controller.loadRequest(widget.callbackUri);
    _cookiePollTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => unawaited(_checkLoginCookie()),
    );
    _timeoutTimer = Timer(
      const Duration(seconds: 75),
      () => _fail('建立教务系统登录会话超时，请返回后重新登录'),
    );
  }

  Future<void> _configureAndroidWebView() async {
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) return;
    if (kDebugMode) {
      await AndroidWebViewController.enableDebugging(true);
    }
    final cookieManager = WebViewCookieManager().platform;
    if (cookieManager is AndroidWebViewCookieManager) {
      await cookieManager.setAcceptThirdPartyCookies(platform, true);
    }
  }

  void _handleNavigation(String value, {bool pageFinished = false}) {
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    _clearTransientResourceErrorAfterNavigation(value);
    _lastNavigationUrl = value;
    if (_terminalFailure) return;
    if (kDebugMode) {
      debugPrint('[SHU_AUTH_CALLBACK] ${uri.host}${uri.path}');
    }
    if (pageFinished &&
        uri.host == _portalUri.host &&
        uri.path.startsWith('/site-nav')) {
      unawaited(_openAcademicSystem());
      return;
    }
    if (_isAcademicReady(uri)) {
      _succeed();
      return;
    }
    if (pageFinished && AcademicUrlResolver.isTicketLoginUrl(value)) {
      unawaited(_verifyAfterTicketLogin());
    }
  }

  NavigationDecision _handleNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri != null && _isInternalWebViewScheme(uri.scheme)) {
      return NavigationDecision.navigate;
    }
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        _isAllowedHost(uri.host)) {
      return NavigationDecision.navigate;
    }
    if (kDebugMode) {
      debugPrint(
        '[SHU_AUTH_CALLBACK] blocked-navigation '
        'mainFrame=${request.isMainFrame} url=${request.url}',
      );
    }
    if (request.isMainFrame) {
      _fail('认证页面尝试跳转到非上海大学地址');
    }
    return NavigationDecision.prevent;
  }

  void _handleWebResourceError(WebResourceError error) {
    if (_completed || _terminalFailure || error.isForMainFrame == false) {
      return;
    }
    final failedUrl = error.url ?? _lastNavigationUrl;
    if (kDebugMode) {
      debugPrint(
        '[SHU_AUTH_CALLBACK] web-resource-error '
        'code=${error.errorCode} type=${error.errorType} url=$failedUrl '
        'description=${error.description}',
      );
    }
    _resourceErrorTimer?.cancel();
    _pendingResourceErrorUrl = failedUrl;
    final generation = ++_resourceErrorGeneration;
    _resourceErrorTimer = Timer(
      _resourceErrorConfirmationDelay,
      () => unawaited(
        _confirmWebResourceError(
          generation: generation,
          failedUrl: failedUrl,
          description: error.description,
        ),
      ),
    );
  }

  Future<void> _confirmWebResourceError({
    required int generation,
    required String? failedUrl,
    required String description,
  }) async {
    if (!_isCurrentResourceError(generation)) return;
    String? currentUrl;
    try {
      currentUrl = await _controller.currentUrl();
    } on Object {
      currentUrl = _lastNavigationUrl;
    }
    if (!_isCurrentResourceError(generation)) return;
    if (hasWebVpnNavigationProgressed(failedUrl, currentUrl)) {
      _clearPendingResourceError();
      return;
    }
    try {
      final cookies =
          await WebViewCookieManager().getCookies(domain: _portalUri);
      if (!_isCurrentResourceError(generation)) return;
      if (cookies.any(
        (cookie) => cookie.name == 'webvpn-token' && cookie.value.isNotEmpty,
      )) {
        _clearPendingResourceError();
        await _openAcademicSystem();
        return;
      }
    } on Object {
      // Cookie 查询失败时仍按当前页面状态判断是否展示错误。
    }
    if (!_isCurrentResourceError(generation)) return;
    _clearPendingResourceError();
    _fail('WebVPN 登录会话建立失败：$description');
  }

  bool _isCurrentResourceError(int generation) {
    return !_completed &&
        !_terminalFailure &&
        mounted &&
        generation == _resourceErrorGeneration;
  }

  void _clearTransientResourceErrorAfterNavigation(String nextUrl) {
    final failedUrl = _pendingResourceErrorUrl;
    if (failedUrl != null &&
        hasWebVpnNavigationProgressed(failedUrl, nextUrl)) {
      _clearPendingResourceError();
    }
  }

  void _clearPendingResourceError() {
    _resourceErrorTimer?.cancel();
    _resourceErrorTimer = null;
    _pendingResourceErrorUrl = null;
    _resourceErrorGeneration++;
  }

  Future<void> _checkLoginCookie() async {
    if (_completed || _terminalFailure) return;
    final cookies = await WebViewCookieManager().getCookies(domain: _portalUri);
    if (cookies.any(
      (cookie) => cookie.name == 'webvpn-token' && cookie.value.isNotEmpty,
    )) {
      await _openAcademicSystem();
    }
  }

  Future<void> _openAcademicSystem() async {
    if (_completed || _terminalFailure || _openingAcademicSystem || !mounted) {
      return;
    }
    _openingAcademicSystem = true;
    setState(() => _status = '正在进入上海大学教务系统');
    try {
      await _controller.loadRequest(
        Uri.parse('${AcademicUrlResolver.webVpnBaseUrl}/'),
      );
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('[SHU_AUTH_CALLBACK] academic-load-error $error');
      }
      _fail('WebVPN 已认证，但无法进入教务系统');
    }
  }

  Future<void> _verifyAfterTicketLogin() async {
    if (_completed || _terminalFailure || _checkingTicketLogin) return;
    _checkingTicketLogin = true;
    if (mounted) setState(() => _status = '正在完成教务系统票据登录');
    await Future<void>.delayed(const Duration(seconds: 6));
    if (_completed || !mounted) return;
    _checkingTicketLogin = false;
    await _controller.loadRequest(
      Uri.parse(
        '${AcademicUrlResolver.webVpnBaseUrl}${AcademicUrlResolver.homePath}',
      ),
    );
  }

  bool _isAcademicReady(Uri uri) {
    if (uri.host != AcademicUrlResolver.webVpnHost ||
        !uri.path.startsWith('/jwglxt/')) {
      return false;
    }
    return !uri.path.endsWith('/jwglxt/ticketlogin') &&
        !uri.path.endsWith('/jwglxt/xtgl/login_slogin.html');
  }

  void _succeed() {
    if (_completed || _terminalFailure || !mounted) return;
    _completed = true;
    _clearPendingResourceError();
    _cookiePollTimer?.cancel();
    _timeoutTimer?.cancel();
    Navigator.of(context).pop(true);
  }

  void _fail(String message) {
    if (_completed || _terminalFailure || !mounted || _error != null) return;
    _terminalFailure = true;
    _clearPendingResourceError();
    _cookiePollTimer?.cancel();
    _timeoutTimer?.cancel();
    setState(() => _error = message);
  }

  bool _isAllowedHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'shu.edu.cn' || normalized.endsWith('.shu.edu.cn');
  }

  bool _isInternalWebViewScheme(String scheme) {
    return scheme == 'about' ||
        scheme == 'data' ||
        scheme == 'blob' ||
        scheme == 'javascript';
  }
}
