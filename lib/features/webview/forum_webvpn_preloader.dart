import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/certificate_policy.dart';
import '../../core/client_user_agent.dart';
import '../../core/forum_url_resolver.dart';

enum ForumWebVpnPreparationResult { ready, loginRequired, unavailable }

class ForumWebVpnPreloader extends StatefulWidget {
  const ForumWebVpnPreloader({
    super.key,
    required this.onComplete,
  });

  final ValueChanged<ForumWebVpnPreparationResult> onComplete;

  @override
  State<ForumWebVpnPreloader> createState() => _ForumWebVpnPreloaderState();
}

class _ForumWebVpnPreloaderState extends State<ForumWebVpnPreloader> {
  late final WebViewController _controller;
  bool _completed = false;
  Uri? _currentUri;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(ClientUserAgent.mobileBrowser)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _currentUri = Uri.tryParse(url);
            _debug('page-started', url);
          },
          onPageFinished: _handlePageFinished,
          onNavigationRequest: (request) {
            _currentUri = Uri.tryParse(request.url);
            _debug('navigation-request', request.url);
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) {
              return;
            }
            _debug(
              'web-resource-error ${error.errorCode}: ${error.description}',
            );
            _complete(ForumWebVpnPreparationResult.unavailable);
          },
          onHttpError: (error) {
            _debug('http-error ${error.response?.statusCode ?? 'unknown'}');
          },
          onSslAuthError: _handleSslAuthError,
        ),
      );
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.01,
        child: SizedBox(
          width: 1,
          height: 1,
          child: WebViewWidget(controller: _controller),
        ),
      ),
    );
  }

  Future<void> _load() async {
    await _configureAndroidWebView();
    if (!mounted) {
      return;
    }
    final url = '${ForumUrlResolver.webVpnBaseUrl}/latest';
    _debug('load-latest', url);
    try {
      await _controller.loadRequest(Uri.parse(url));
    } on Object {
      _complete(ForumWebVpnPreparationResult.unavailable);
    }
  }

  Future<void> _configureAndroidWebView() async {
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) {
      return;
    }
    if (kDebugMode) {
      await AndroidWebViewController.enableDebugging(true);
    }
    await platform.setMediaPlaybackRequiresUserGesture(false);
    await platform.setUseWideViewPort(true);
    await platform.setMixedContentMode(MixedContentMode.compatibilityMode);
    final cookieManager = WebViewCookieManager().platform;
    if (cookieManager is AndroidWebViewCookieManager) {
      await cookieManager.setAcceptThirdPartyCookies(platform, true);
    }
  }

  Future<void> _handlePageFinished(String url) async {
    _debug('page-finished', url);
    if (_completed) {
      return;
    }
    if (_isForumLoginUrl(url)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _complete(ForumWebVpnPreparationResult.loginRequired);
      return;
    }
    if (_completed || !_isPreparedForumUrl(url)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _complete(ForumWebVpnPreparationResult.ready);
  }

  bool _isPreparedForumUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != ForumUrlResolver.webVpnHost) {
      return false;
    }
    final path = uri.path.toLowerCase();
    if (path == '/login' || path.startsWith('/login/')) {
      return false;
    }
    if (path.startsWith('/auth/')) {
      return false;
    }
    return true;
  }

  bool _isForumLoginUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != ForumUrlResolver.webVpnHost) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path == '/login' ||
        path.startsWith('/login/') ||
        path.startsWith('/auth/');
  }

  void _handleSslAuthError(SslAuthError error) {
    final uri = _sslErrorUri(error) ?? _currentUri;
    if (kDebugMode) {
      debugPrint(
        '[LEHU_WEBVIEW FORUM_BG_PREP] ssl-error '
        'host=${uri?.host ?? 'unknown'} description=${error.platform.description}',
      );
    }
    if (CertificatePolicy.allowsUri(uri)) {
      error.proceed();
      return;
    }
    error.cancel();
  }

  Uri? _sslErrorUri(SslAuthError error) {
    final platform = error.platform;
    if (platform is AndroidSslAuthError) {
      return Uri.tryParse(platform.url);
    }
    if (platform is WebKitSslAuthError) {
      return Uri.parse('https://${platform.host}');
    }
    return null;
  }

  void _complete(ForumWebVpnPreparationResult result) {
    if (_completed || !mounted) return;
    _completed = true;
    widget.onComplete(result);
  }

  void _debug(String message, [String? url]) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[LEHU_WEBVIEW FORUM_BG_PREP] $message${url == null ? '' : ' | $url'}',
    );
  }
}
