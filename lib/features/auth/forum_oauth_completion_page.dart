import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/client_user_agent.dart';
import '../../core/forum_url_resolver.dart';
import '../../data/services/discourse_api_client.dart';
import '../../data/services/forum_auth_service.dart';

enum ForumOAuthCompletionResult { loggedIn, registrationRequired }

@visibleForTesting
bool isForumRegistrationUri(Uri uri) {
  if (!ForumUrlResolver.isKnownForumHost(uri.host.toLowerCase())) return false;
  final path = uri.path.toLowerCase();
  return path == '/u/account-created' ||
      path.startsWith('/signup') ||
      path.startsWith('/register') ||
      path.contains('/complete-registration');
}

class ForumOAuthCompletionPage extends StatefulWidget {
  const ForumOAuthCompletionPage({
    super.key,
    required this.callbackUri,
  });

  final Uri callbackUri;

  @override
  State<ForumOAuthCompletionPage> createState() =>
      _ForumOAuthCompletionPageState();
}

class _ForumOAuthCompletionPageState extends State<ForumOAuthCompletionPage> {
  late final WebViewController _controller;
  final _authService = ForumAuthService();
  Timer? _sessionPollTimer;
  Timer? _timeoutTimer;
  bool _completed = false;
  bool _checkingSession = false;
  bool _forumReached = false;
  String? _error;
  final String _status = '正在建立乐乎论坛会话';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setUserAgent(ClientUserAgent.mobileBrowser)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: _handleNavigation,
          onPageFinished: (url) {
            _handleNavigation(url);
            unawaited(_checkSession());
          },
          onNavigationRequest: _handleNavigationRequest,
          onWebResourceError: (error) {
            if (error.isForMainFrame != false) {
              _fail('论坛登录会话建立失败：${error.description}');
            }
          },
        ),
      );
    unawaited(_start());
  }

  @override
  void dispose() {
    _sessionPollTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _error != null,
      child: Scaffold(
        appBar: AppBar(title: const Text('乐乎论坛账户')),
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
                            onPressed: () => Navigator.of(context).pop(),
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
    _sessionPollTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) => unawaited(_checkSession()),
    );
    _timeoutTimer = Timer(
      const Duration(seconds: 75),
      () => _fail('建立乐乎论坛登录会话超时，请返回后重新登录'),
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

  void _handleNavigation(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || _completed) return;
    if (kDebugMode) {
      debugPrint('[FORUM_AUTH_CALLBACK] ${uri.host}${uri.path}');
    }
    if (isForumRegistrationUri(uri)) {
      _finish(ForumOAuthCompletionResult.registrationRequired);
      return;
    }
    if (ForumUrlResolver.isKnownForumHost(uri.host.toLowerCase())) {
      _forumReached = true;
      if (uri.path.startsWith('/auth/failure')) {
        _fail('乐乎论坛拒绝了本次登录，请返回后重试');
      }
    }
  }

  NavigationDecision _handleNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri != null && _isInternalWebViewScheme(uri.scheme)) {
      return NavigationDecision.navigate;
    }
    if (uri != null && uri.scheme == 'https' && _isAllowedHost(uri.host)) {
      return NavigationDecision.navigate;
    }
    if (request.isMainFrame) {
      _fail('认证页面尝试跳转到非上海大学地址');
    }
    return NavigationDecision.prevent;
  }

  Future<void> _checkSession() async {
    if (_completed || _checkingSession || !_forumReached) return;
    _checkingSession = true;
    try {
      final apiClient = DiscourseApiClient(authService: _authService);
      final session = await apiClient.getJson('/session/current.json');
      if (session['current_user'] is Map) {
        await _authService.persistLastCookieHeader();
        _finish(ForumOAuthCompletionResult.loggedIn);
      }
    } on ForumAuthException {
      // The callback can finish setting cookies a moment after navigation.
    } on ForumApiException catch (error) {
      if (kDebugMode) debugPrint('[FORUM_AUTH_CALLBACK] session: $error');
    } on Object catch (error) {
      if (kDebugMode) debugPrint('[FORUM_AUTH_CALLBACK] session: $error');
    } finally {
      _checkingSession = false;
    }
  }

  void _finish(ForumOAuthCompletionResult result) {
    if (_completed || !mounted) return;
    _completed = true;
    _sessionPollTimer?.cancel();
    _timeoutTimer?.cancel();
    Navigator.of(context).pop(result);
  }

  void _fail(String message) {
    if (_completed || !mounted || _error != null) return;
    _sessionPollTimer?.cancel();
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
