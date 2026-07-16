import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/certificate_policy.dart';
import '../../shared/widgets/info_confirm_dialog.dart';

class ForumWebViewPage extends StatefulWidget {
  const ForumWebViewPage({
    super.key,
    required this.title,
    required this.url,
    this.initialNoticeTitle,
    this.initialNoticeMessage,
    this.initialNoticeDelay = Duration.zero,
  });

  final String title;
  final String url;
  final String? initialNoticeTitle;
  final String? initialNoticeMessage;
  final Duration initialNoticeDelay;

  @override
  State<ForumWebViewPage> createState() => _ForumWebViewPageState();
}

class _ForumWebViewPageState extends State<ForumWebViewPage> {
  static const _mobileChromeUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  late final WebViewController _controller;
  bool _loading = true;
  WebResourceError? _lastError;
  HttpResponseError? _lastHttpError;
  Uri? _currentUri;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(_mobileChromeUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _currentUri = Uri.tryParse(url);
            setState(() {
              _loading = true;
              _lastError = null;
              _lastHttpError = null;
            });
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _loading = false);
            }
          },
          onNavigationRequest: (request) {
            _currentUri = Uri.tryParse(request.url);
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) {
              return;
            }
            setState(() {
              _loading = false;
              _lastError = error;
            });
          },
          onHttpError: (error) {
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = false;
              _lastHttpError = error;
            });
          },
          onSslAuthError: _handleSslAuthError,
        ),
      );
    unawaited(_loadInitialRequest());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showInitialNotice());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_lastError != null || _lastHttpError != null)
            _WebViewErrorOverlay(
              error: _lastError,
              httpError: _lastHttpError,
              onRetry: () {
                setState(() {
                  _lastError = null;
                  _lastHttpError = null;
                  _loading = true;
                });
                _controller.reload();
              },
            ),
          if (_loading)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
    );
  }

  void _handleSslAuthError(SslAuthError error) {
    final uri = _sslErrorUri(error) ?? _currentUri;
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
    return null;
  }

  Future<void> _configureAndroidWebView() async {
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) {
      return;
    }
    await AndroidWebViewController.enableDebugging(true);
    await platform.setMediaPlaybackRequiresUserGesture(false);
    await platform.setUseWideViewPort(true);
    await platform.setMixedContentMode(MixedContentMode.compatibilityMode);
    final cookieManager = WebViewCookieManager().platform;
    if (cookieManager is AndroidWebViewCookieManager) {
      await cookieManager.setAcceptThirdPartyCookies(platform, true);
    }
  }

  Future<void> _loadInitialRequest() async {
    await _configureAndroidWebView();
    if (!mounted) {
      return;
    }
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  Future<void> _showInitialNotice() async {
    final title = widget.initialNoticeTitle;
    final message = widget.initialNoticeMessage;
    if (!mounted || title == null || message == null) {
      return;
    }
    await showInfoConfirmDialog(
      context,
      title: title,
      message: message,
      confirmDelay: widget.initialNoticeDelay,
    );
  }
}

class _WebViewErrorOverlay extends StatelessWidget {
  const _WebViewErrorOverlay({
    required this.error,
    required this.httpError,
    required this.onRetry,
  });

  final WebResourceError? error;
  final HttpResponseError? httpError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final httpError = this.httpError;
    final message = error != null
        ? '${error.errorCode} · ${error.description}'
        : 'HTTP ${httpError?.response?.statusCode ?? '错误'}';
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.public_off_outlined,
                size: 40,
                color: Color(0xFFBDBDBD),
              ),
              const SizedBox(height: 14),
              const Text(
                '网页加载失败',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFAAAAAA)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
