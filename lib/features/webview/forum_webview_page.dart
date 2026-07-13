import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/certificate_policy.dart';

class ForumWebViewPage extends StatefulWidget {
  const ForumWebViewPage({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  State<ForumWebViewPage> createState() => _ForumWebViewPageState();
}

class _ForumWebViewPageState extends State<ForumWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;
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
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _loading = false);
            }
          },
          onNavigationRequest: (request) {
            _currentUri = Uri.tryParse(request.url);
            return NavigationDecision.navigate;
          },
          onSslAuthError: _handleSslAuthError,
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
