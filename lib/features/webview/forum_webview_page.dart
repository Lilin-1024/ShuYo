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
    this.autoCloseUrlPrefixes = const [],
    this.autoVisitUrlPrefixes = const [],
    this.autoVisitUrls = const [],
    this.autoCloseAfterAutoVisit = false,
    this.autoVisitMessage,
    this.autoVisitFinalDelay = Duration.zero,
    this.hideContentDuringAutoVisit = false,
    this.debugLabel,
    this.showDebugInfo = false,
  });

  final String title;
  final String url;
  final String? initialNoticeTitle;
  final String? initialNoticeMessage;
  final Duration initialNoticeDelay;
  final List<String> autoCloseUrlPrefixes;
  final List<String> autoVisitUrlPrefixes;
  final List<String> autoVisitUrls;
  final bool autoCloseAfterAutoVisit;
  final String? autoVisitMessage;
  final Duration autoVisitFinalDelay;
  final bool hideContentDuringAutoVisit;
  final String? debugLabel;
  final bool showDebugInfo;

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
  bool _autoClosed = false;
  bool _autoVisitStarted = false;
  String? _autoVisitMessage;
  String? _waitingForUrl;
  String _debugStatus = '初始化';
  String _debugUrl = '';
  Completer<String>? _pageFinishedCompleter;

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
            _debug('page-started', url);
            setState(() {
              _loading = true;
              _lastError = null;
              _lastHttpError = null;
            });
          },
          onPageFinished: (url) {
            _debug('page-finished', url);
            if (mounted) {
              setState(() => _loading = false);
            }
            final completer = _pageFinishedCompleter;
            if (completer != null && !completer.isCompleted) {
              final waitingFor = _waitingForUrl;
              if (waitingFor == null ||
                  _isRelevantFinishedUrl(waitingFor, url)) {
                completer.complete(url);
              } else {
                _debug('page-finished-ignored', url);
              }
            }
            if (_maybeStartAutoVisit(url)) {
              return;
            }
            _closeIfMatched(url);
          },
          onNavigationRequest: (request) {
            _currentUri = Uri.tryParse(request.url);
            _debug('navigation-request', request.url);
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) {
              return;
            }
            _debug(
              'web-resource-error ${error.errorCode}: ${error.description}',
            );
            setState(() {
              _loading = false;
              _lastError = error;
            });
          },
          onHttpError: (error) {
            if (!mounted) {
              return;
            }
            _debug('http-error ${error.response?.statusCode ?? 'unknown'}');
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
          if (widget.hideContentDuringAutoVisit && _autoVisitMessage != null)
            const ColoredBox(color: Colors.black),
          if (_autoVisitMessage != null)
            _AutoVisitOverlay(message: _autoVisitMessage!),
          if (widget.showDebugInfo)
            _WebViewDebugPanel(
              label: widget.debugLabel ?? widget.title,
              status: _debugStatus,
              url: _debugUrl,
            ),
        ],
      ),
    );
  }

  void _handleSslAuthError(SslAuthError error) {
    final uri = _sslErrorUri(error) ?? _currentUri;
    if (CertificatePolicy.allowsUri(uri)) {
      _debug('ssl-proceed', uri?.toString());
      error.proceed();
      return;
    }
    _debug('ssl-cancel', uri?.toString());
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
    _debug('load-initial', widget.url);
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

  Future<void> _closeIfMatched(String url) async {
    if (_autoClosed || widget.autoCloseUrlPrefixes.isEmpty) {
      return;
    }
    if (!widget.autoCloseUrlPrefixes.any(url.startsWith)) {
      _debug('auto-close-not-matched', url);
      return;
    }
    _autoClosed = true;
    _debug('auto-close-matched', url);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      _debug('auto-close-pop-true');
      Navigator.of(context).pop(true);
    }
  }

  bool _maybeStartAutoVisit(String url) {
    if (_autoVisitStarted ||
        widget.autoVisitUrls.isEmpty ||
        widget.autoVisitUrlPrefixes.isEmpty) {
      return false;
    }
    if (!widget.autoVisitUrlPrefixes.any(url.startsWith)) {
      _debug('auto-visit-not-matched', url);
      return false;
    }
    _autoVisitStarted = true;
    _debug('auto-visit-start', url);
    unawaited(_runAutoVisitSequence());
    return true;
  }

  Future<void> _runAutoVisitSequence() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _autoVisitMessage = widget.autoVisitMessage ?? '正在准备页面...';
      _lastError = null;
      _lastHttpError = null;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      for (final url in widget.autoVisitUrls) {
        _debug('auto-visit-load', url);
        await _loadAndWaitForPage(url);
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
      if (!mounted) {
        return;
      }
      if (widget.autoVisitFinalDelay > Duration.zero) {
        _debug(
            'auto-visit-final-delay ${widget.autoVisitFinalDelay.inMilliseconds}ms');
        await Future<void>.delayed(widget.autoVisitFinalDelay);
      }
      if (!mounted) {
        return;
      }
      if (widget.autoCloseAfterAutoVisit) {
        _debug('auto-visit-complete-pop-true');
        Navigator.of(context).pop(true);
        return;
      }
      _debug('auto-visit-complete-stay');
      setState(() => _autoVisitMessage = null);
    } on Object catch (error) {
      _debug('auto-visit-error: $error');
      if (!mounted) {
        return;
      }
      if (widget.autoCloseAfterAutoVisit) {
        _debug('auto-visit-pop-false');
        Navigator.of(context).pop(false);
        return;
      }
      setState(() => _autoVisitMessage = null);
    }
  }

  Future<void> _loadAndWaitForPage(String url) async {
    final completer = Completer<String>();
    _pageFinishedCompleter = completer;
    _waitingForUrl = url;
    await _controller.loadRequest(Uri.parse(url));
    try {
      final finishedUrl =
          await completer.future.timeout(const Duration(seconds: 18));
      _debug('auto-visit-finished', finishedUrl);
    } finally {
      if (identical(_pageFinishedCompleter, completer)) {
        _pageFinishedCompleter = null;
      }
      if (_waitingForUrl == url) {
        _waitingForUrl = null;
      }
    }
  }

  bool _isRelevantFinishedUrl(String requestedUrl, String finishedUrl) {
    if (finishedUrl.startsWith(requestedUrl)) {
      return true;
    }
    final requested = Uri.tryParse(requestedUrl);
    final finished = Uri.tryParse(finishedUrl);
    if (requested == null || finished == null) {
      return false;
    }
    if (requested.host == finished.host && requested.path == finished.path) {
      return true;
    }
    if (requested.host == finished.host &&
        finished.path.endsWith('/login_slogin.html')) {
      return true;
    }
    return false;
  }

  void _debug(String status, [String? url]) {
    final label = widget.debugLabel ?? widget.title;
    final nextUrl = url ?? _debugUrl;
    debugPrint(
      '[LEHU_WEBVIEW $label] $status${nextUrl.isEmpty ? '' : ' | $nextUrl'}',
    );
    if (!widget.showDebugInfo || !mounted) {
      return;
    }
    setState(() {
      _debugStatus = status;
      if (url != null) {
        _debugUrl = url;
      }
    });
  }
}

class _WebViewDebugPanel extends StatelessWidget {
  const _WebViewDebugPanel({
    required this.label,
    required this.status,
    required this.url,
  });

  final String label;
  final String status;
  final String url;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF333333)),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 11,
              height: 1.25,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DEBUG $label · $status'),
                if (url.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(url, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoVisitOverlay extends StatelessWidget {
  const _AutoVisitOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(message),
            ],
          ),
        ),
      ),
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
