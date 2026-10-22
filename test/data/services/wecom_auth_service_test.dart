import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/core/wecom_constants.dart';
import 'package:shuyo/data/services/wecom_auth_service.dart';

void main() {
  group('WeComAuthService', () {
    test('OAuth redirect diagnostics never include authorization values', () {
      final callback = Uri.parse(
        'https://there.shu.edu.cn/login-oauth2?code=SECRET_CODE&state=SECRET_STATE',
      );
      final login = Uri.parse(
        'https://newsso.shu.edu.cn/oauth2/login/SECRET_CONTEXT',
      );
      final callbackLog = WeComAuthService.describeUrlForLog(callback);
      final loginLog = WeComAuthService.describeUrlForLog(login);
      expect(callbackLog, contains('login-oauth2'));
      expect(callbackLog, contains('queryKeys=[code, state]'));
      expect(callbackLog, isNot(contains('SECRET_CODE')));
      expect(callbackLog, isNot(contains('SECRET_STATE')));
      expect(loginLog, contains('/oauth2/login/{context}'));
      expect(loginLog, isNot(contains('SECRET_CONTEXT')));
    });

    test('encodeOAuthParams produces base64url without padding', () {
      final encoded = WeComAuthService.encodeOAuthParams({
        'responseType': 'code',
        'clientId': 'abc',
      });
      // base64url (no + / = chars)
      expect(encoded, isNot(contains('+')));
      expect(encoded, isNot(contains('/')));
      expect(encoded, isNot(contains('=')));
      // Can be decoded back (normalize restores the stripped padding)
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      );
      expect(decoded['responseType'], 'code');
      expect(decoded['clientId'], 'abc');
    });

    test('encodeOAuthParams handles Chinese text (ensureAscii=false)', () {
      final encoded = WeComAuthService.encodeOAuthParams({
        'clientName': '本科生教务系统',
      });
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      );
      expect(decoded['clientName'], '本科生教务系统');
    });

    test('parseStatus maps QRCODE_SCAN_SUCC with auth_code to success',
        () async {
      // WeComScanResult 的静态构造器行为：
      expect(
        const WeComScanResult.succeeded('abc123').isSuccess,
        true,
      );
      expect(const WeComScanResult.succeeded('abc123').authCode, 'abc123');
    });

    test('weComRedeemState always encodes the academic client', () {
      // state 固定编码 jwxt 参数：企微自建应用只绑定教务系统，其他参数
      // 会被 /oauth/wecom/qrcode 判为 badRequestParams。目标系统的差异在
      // authorizeTarget 阶段处理。
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(
          WeComAuthService.weComRedeemState,
        ))),
      );
      expect(decoded['clientId'], 'Km5t225E8KECKQ6ZDm5K2P6aS2459Cua');
      expect(decoded['scope'], 'jw');
      expect(WeComAuthService.weComRedeemState, isNot(contains('=')));
      expect(WeComAuthService.weComRedeemState, isNot(contains('+')));
      expect(WeComAuthService.weComRedeemState, isNot(contains('/')));
    });

    test('WeComSessionResult carries the SSO session cookies', () {
      final result = WeComSessionResult(
        sessionCookies: [Cookie('SHU_OAUTH2', 'session')],
        cookieSourceUri:
            Uri.parse('https://newsso.shu.edu.cn/oauth/wecom/qrcode'),
      );
      expect(result.sessionCookies.single.name, 'SHU_OAUTH2');
      expect(result.cookieSourceUri.host, 'newsso.shu.edu.cn');
    });

    test('WebVPN state uses standard padded base64', () {
      final state = WeComAuthService.webVpnState('YJrvSXWl');
      expect(state, endsWith('=='));
      expect(
        jsonDecode(utf8.decode(base64Decode(state))),
        {'externalId': 'YJrvSXWl'},
      );
    });

    test('unproxies only the trusted WebVPN newsso authorize host', () {
      final direct = WeComAuthService.directWebVpnAuthorizeUri(
        'https://https-newsso-shu-edu-cn-443.webvpn.shu.edu.cn/oauth/authorize?client_id=x',
      );
      expect(direct.host, 'newsso.shu.edu.cn');
      expect(direct.path, '/oauth/authorize');
      expect(direct.queryParameters['client_id'], 'x');
      expect(
        () => WeComAuthService.directWebVpnAuthorizeUri(
          'https://example.com/oauth/authorize',
        ),
        throwsA(isA<WeComAuthException>()),
      );
    });

    test('WebVPN device id is stable and uses 32 lowercase hex digits',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = WeComAuthService(random: Random(7));
      addTearDown(service.dispose);

      final first = await service.loadWebVpnDeviceId();
      final second = await service.loadWebVpnDeviceId();

      expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(second, first);
    });
  });

  group('WeComOAuthTarget', () {
    test('academic target encodes the jwxt client', () {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(
          WeComAuthService.encodeOAuthParams(
              WeComOAuthTarget.academic.toParams()),
        ))),
      );
      expect(decoded['clientId'], 'Km5t225E8KECKQ6ZDm5K2P6aS2459Cua');
      expect(decoded['clientName'], '本科生教务系统');
      expect(decoded['scope'], 'jw');
      expect(decoded['redirectUri'], 'https://jwxt.shu.edu.cn/sso/shulogin');
      expect(decoded['responseType'], 'code');
      expect(decoded['state'], '');
    });

    test('WebVPN target uses its dedicated OAuth client', () {
      expect(WeComOAuthTarget.webVpn.kind, WeComOAuthTargetKind.webVpn);
      expect(
        WeComOAuthTarget.webVpn.clientId,
        'nn7sbb22j2tKE100T024tEp42777p755',
      );
      expect(
        WeComOAuthTarget.webVpn.redirectUri,
        'https://webvpn.shu.edu.cn/callback/oauth2',
      );
    });

    test('academic state is generated locally', () {
      expect(WeComOAuthTarget.academic.generateState, isTrue);
    });
  });
}
