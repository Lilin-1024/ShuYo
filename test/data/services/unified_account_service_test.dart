import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/academic_auth_service.dart';
import 'package:shuyo/data/services/shu_sso_session_store.dart';
import 'package:shuyo/data/services/unified_account_service.dart';
import 'package:shuyo/data/services/wecom_auth_service.dart';

class _SessionStore extends ShuSsoSessionStore {
  _SessionStore(this.available);

  final bool available;
  int reads = 0;

  @override
  Future<List<({Cookie cookie, String domain, String path})>>
      sessionCookies() async {
    reads++;
    if (!available) return [];
    return [
      (
        cookie: Cookie('SHU_OAUTH2', 'session'),
        domain: 'newsso.shu.edu.cn',
        path: '/',
      ),
    ];
  }
}

class _BusinessSession extends AcademicAuthService {
  _BusinessSession(this.status)
      : super(cookieLoader: (_) async => [], cookieSetter: (_) async {});

  final WebVpnSessionStatus status;

  @override
  Future<WebVpnSessionStatus> validateWebVpnSession() async => status;
}

class _RejectedWebVpn extends WeComAuthService {
  @override
  Future<WeComRedeemResult> completeWebVpnLogin() async =>
      throw const WeComAuthException('webVpnFinishFailed', 'WebVPN 拒绝兑换');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a valid business session needs no SSO authorization', () async {
    final sso = _SessionStore(false);
    final account = UnifiedAccountService(
      ssoSessionStore: sso,
      academicAuthService: _BusinessSession(WebVpnSessionStatus.valid),
    );
    expect(await account.recoverWebVpn(), WebVpnRecoveryOutcome.alreadyValid);
    expect(sso.reads, 0);
    expect(await account.isWebVpnPendingRecovery(), isFalse);
  });

  test('an uncertain business response keeps credentials for retry', () async {
    final sso = _SessionStore(true);
    final account = UnifiedAccountService(
      ssoSessionStore: sso,
      academicAuthService: _BusinessSession(WebVpnSessionStatus.unavailable),
    );
    expect(await account.recoverWebVpn(), WebVpnRecoveryOutcome.unavailable);
    expect(sso.reads, 0);
    expect(await account.isWebVpnPendingRecovery(), isTrue);
  });

  test('a missing SSO session asks for authentication only after rejection',
      () async {
    final account = UnifiedAccountService(
      ssoSessionStore: _SessionStore(false),
      academicAuthService: _BusinessSession(WebVpnSessionStatus.loginRequired),
    );
    expect(await account.recoverWebVpn(),
        WebVpnRecoveryOutcome.needsAuthentication);
    expect(await account.isWebVpnPendingRecovery(), isTrue);
  });

  test('WebVPN redemption failure is not an expired SSO session', () async {
    final account = UnifiedAccountService(
      ssoSessionStore: _SessionStore(true),
      academicAuthService: _BusinessSession(WebVpnSessionStatus.loginRequired),
      weComAuthServiceFactory: _RejectedWebVpn.new,
    );
    expect(
        await account.recoverWebVpn(), WebVpnRecoveryOutcome.businessFailure);
    expect(account.lastWebVpnFailureMessage, 'WebVPN 拒绝兑换');
    expect(await account.isWebVpnPendingRecovery(), isTrue);
  });
}
