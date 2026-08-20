import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/academic_url_resolver.dart';
import '../../core/client_user_agent.dart';

class AcademicWebVpnPreloader extends StatefulWidget {
  const AcademicWebVpnPreloader({
    super.key,
    required this.onComplete,
  });

  final ValueChanged<bool> onComplete;

  @override
  State<AcademicWebVpnPreloader> createState() =>
      _AcademicWebVpnPreloaderState();
}

class _AcademicWebVpnPreloaderState extends State<AcademicWebVpnPreloader> {
  late final WebViewController _controller;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(ClientUserAgent.mobileBrowser)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => _debug('page-started', url),
          onPageFinished: _handlePageFinished,
          onNavigationRequest: (request) {
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
          },
          onHttpError: (error) {
            _debug('http-error ${error.response?.statusCode ?? 'unknown'}');
          },
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
    final url = AcademicUrlResolver.entryUri.toString();
    _debug('load-entry', url);
    await _controller.loadRequest(Uri.parse(url));
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
    if (_completed || !AcademicUrlResolver.isPreparedWebVpnAcademicUrl(url)) {
      return;
    }
    _completed = true;
    final isTicketLogin = AcademicUrlResolver.isTicketLoginUrl(url);
    _debug(isTicketLogin ? 'ticketlogin-finished' : 'academic-ready', url);
    await Future<void>.delayed(
      isTicketLogin ? const Duration(seconds: 6) : const Duration(seconds: 3),
    );
    if (mounted) {
      widget.onComplete(true);
    }
  }

  void _debug(String message, [String? url]) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[LEHU_WEBVIEW ACADEMIC_BG_PREP] $message${url == null ? '' : ' | $url'}',
    );
  }
}
