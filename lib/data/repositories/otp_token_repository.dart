import 'package:flutter/foundation.dart';

import '../models/otp_token.dart';
import '../services/otp_token_api_client.dart';

/// Exposes the school dynamic password to the UI.
///
/// The token is read from the server on every call, so the repository stays a
/// thin seam over [OtpTokenApiClient]; keeping it separate lets the demo build
/// supply its own rotating value without touching the page.
class OtpTokenRepository extends ChangeNotifier {
  OtpTokenRepository({
    OtpTokenApiClient? apiClient,
    OtpTokenApiClient Function()? clientFactory,
    bool sessionActive = true,
  })  : assert(apiClient == null || clientFactory == null),
        _apiClient = apiClient,
        _clientFactory = clientFactory ?? OtpTokenApiClient.new,
        _sessionActive = sessionActive;

  final OtpTokenApiClient Function() _clientFactory;
  OtpTokenApiClient? _apiClient;
  OtpTokenApiClient get _client => _apiClient ??= _clientFactory();
  int _sessionRevision = 0;
  bool _sessionActive;

  bool get sessionActive => _sessionActive;

  Future<OtpToken> fetchToken() async {
    if (!_sessionActive) throw _sessionChanged();
    final revision = _sessionRevision;
    final client = _client;
    late final OtpToken token;
    try {
      token = await client.fetchToken();
    } on Object {
      if (revision != _sessionRevision) throw _sessionChanged();
      rethrow;
    }
    if (revision != _sessionRevision) throw _sessionChanged();
    return token;
  }

  /// Discards every cookie held by the old account, including OTP's business
  /// session and the adopted SSO and WebVPN cookies.
  void resetSession({bool sessionActive = true}) {
    _sessionRevision++;
    _sessionActive = sessionActive;
    _apiClient?.dispose();
    _apiClient = null;
    notifyListeners();
  }

  OtpTokenException _sessionChanged() => const OtpTokenException(
        OtpTokenException.sessionNotReused,
        '校园登录状态已变更，请重试',
      );

  @override
  void dispose() {
    _apiClient?.dispose();
    _apiClient = null;
    super.dispose();
  }
}
