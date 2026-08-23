import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/academic_url_resolver.dart';
import '../../core/client_user_agent.dart';

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

  late final WebViewController _controller;
  Timer? _cookiePollTimer;
  Timer? _timeoutTimer;
  bool _completed = false;
  bool _openingAcademicSystem = false;
  bool _checkingTicketLogin = false;
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
          onWebResourceError: (error) {
            if (error.isForMainFrame != false) {
              _fail('WebVPN 登录会话建立失败：${error.description}');
            }
          },
        ),
      );
    unawaited(_start());
  }

  @override
  void dispose() {
    _cookiePollTimer?.cancel();
    _timeoutTimer?.cancel();
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

  Future<void> _checkLoginCookie() async {
    if (_completed) return;
    final cookies = await WebViewCookieManager().getCookies(domain: _portalUri);
    if (cookies.any(
      (cookie) => cookie.name == 'webvpn-token' && cookie.value.isNotEmpty,
    )) {
      await _openAcademicSystem();
    }
  }

  Future<void> _openAcademicSystem() async {
    if (_completed || _openingAcademicSystem || !mounted) return;
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
    if (_completed || _checkingTicketLogin) return;
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
    if (_completed || !mounted) return;
    _completed = true;
    _cookiePollTimer?.cancel();
    _timeoutTimer?.cancel();
    Navigator.of(context).pop(true);
  }

  void _fail(String message) {
    if (_completed || !mounted || _error != null) return;
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
