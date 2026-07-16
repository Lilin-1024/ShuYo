import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/certificate_policy.dart';
import '../../core/forum_constants.dart';
import '../../shared/widgets/info_confirm_dialog.dart';

class LoginWebViewPage extends StatefulWidget {
  const LoginWebViewPage({super.key});

  @override
  State<LoginWebViewPage> createState() => _LoginWebViewPageState();
}

class _LoginWebViewPageState extends State<LoginWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _completed = false;
  bool _noticeShowing = false;
  bool _finishAfterNotice = false;
  Uri? _currentUri;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _currentUri = Uri.tryParse(url);
            setState(() => _loading = true);
          },
          onPageFinished: (url) {
            _currentUri = Uri.tryParse(url);
            if (mounted) {
              setState(() => _loading = false);
            }
            _finishIfLoggedIn(url);
          },
          onNavigationRequest: (request) {
            _currentUri = Uri.tryParse(request.url);
            return NavigationDecision.navigate;
          },
          onSslAuthError: _handleSslAuthError,
        ),
      )
      ..loadRequest(Uri.parse('${ForumConstants.baseUrl}/latest'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showLoginNotice());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录论坛'),
        actions: [
          TextButton(
            onPressed: _finishManually,
            child: const Text('完成'),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
    );
  }

  void _finishManually() {
    if (!_completed) {
      _completed = true;
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _showLoginNotice() async {
    if (!mounted) {
      return;
    }
    _noticeShowing = true;
    await showInfoConfirmDialog(
      context,
      title: '登录说明',
      message:
          '这里会打开论坛网页登录页面。账号和密码只会在网页登录页中输入，客户端不会收集或保存你的账号密码。登录完成后返回客户端即可继续使用。',
      confirmDelay: const Duration(seconds: 5),
    );
    _noticeShowing = false;
    if (_finishAfterNotice && mounted && !_completed) {
      _finishAfterNotice = false;
      _completeLogin();
    }
  }

  Future<void> _finishIfLoggedIn(String url) async {
    if (_completed) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (!_isForumLoggedInPage(uri)) {
      return;
    }
    if (_noticeShowing) {
      _finishAfterNotice = true;
      return;
    }
    _completed = true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _completeLogin() {
    _completed = true;
    Navigator.of(context).pop(true);
  }

  bool _isForumLoggedInPage(Uri? uri) {
    if (uri == null || uri.host != ForumConstants.host) {
      return false;
    }
    final path = uri.path.toLowerCase();
    if (path == '/login' || path.startsWith('/login/')) {
      return false;
    }
    if (path.startsWith('/auth/')) {
      return false;
    }
    return path == '/latest' || path == '/latest/' || path == '/';
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
}
