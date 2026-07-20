import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/certificate_policy.dart';
import '../../core/forum_url_resolver.dart';
import '../../data/services/discourse_api_client.dart';
import '../../data/services/forum_auth_service.dart';
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
  bool _checkingSession = false;
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
      ..loadRequest(ForumUrlResolver.uri('/login'));
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
            onPressed: _checkingSession ? null : _finishManually,
            child: Text(_checkingSession ? '检测中' : '完成'),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading || _checkingSession)
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
    );
  }

  void _finishManually() {
    unawaited(_verifyAndComplete(showFailure: true));
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
          '这里会打开论坛网页登录页面。\n\n如果你是新用户，请点击“注册”完成注册。\n\n如果你是老用户，请直接点击登录。\n\n账号和密码只会在网页中输入，客户端不会收集或保存你的账号密码。登录完成后返回客户端即可继续使用。',
      confirmDelay: const Duration(seconds: 5),
    );
    _noticeShowing = false;
    if (_finishAfterNotice && mounted && !_completed) {
      _finishAfterNotice = false;
      final url = _currentUri?.toString();
      if (url != null) {
        unawaited(_finishIfLoggedIn(url));
      }
    }
  }

  Future<void> _finishIfLoggedIn(String url) async {
    if (_completed) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (!_isForumCompletionCandidate(uri)) {
      return;
    }
    if (_noticeShowing) {
      _finishAfterNotice = true;
      return;
    }
    await _verifyAndComplete();
  }

  Future<void> _verifyAndComplete({bool showFailure = false}) async {
    if (!mounted || _completed || _checkingSession) {
      return;
    }
    setState(() => _checkingSession = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!await _hasActiveForumSession()) {
        if (showFailure && mounted) {
          _showSnack('还没有检测到登录态，请完成登录或注册后再试');
        }
        return;
      }
      if (mounted) {
        _completeLogin();
      }
    } on Object {
      if (showFailure && mounted) {
        _showSnack('还没有检测到登录态，请完成登录或注册后再试');
      }
    } finally {
      if (mounted && !_completed) {
        setState(() => _checkingSession = false);
      }
    }
  }

  Future<bool> _hasActiveForumSession() async {
    final client = DiscourseApiClient(authService: ForumAuthService());
    final json = await client.getJson('/session/current.json');
    return json['current_user'] is Map;
  }

  void _completeLogin() {
    _completed = true;
    Navigator.of(context).pop(true);
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _isForumCompletionCandidate(Uri? uri) {
    if (uri == null || !ForumUrlResolver.isActiveForumHost(uri.host)) {
      return false;
    }
    final path = uri.path.toLowerCase();
    if (path == '/login' || path.startsWith('/login/')) {
      return false;
    }
    if (path.startsWith('/auth/')) {
      return false;
    }
    return path == '/' || path == '/latest' || path == '/latest/';
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
