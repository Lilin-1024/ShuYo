import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/core/classroom_url_resolver.dart';
import 'package:shuyo/data/services/classroom_auth_service.dart';
import 'package:shuyo/data/services/session_cookie_jar.dart';

void main() {
  tearDown(() => ClassroomUrlResolver.configure(useWebVpn: false));

  test('direct classroom requests do not read WebVPN cookies', () async {
    ClassroomUrlResolver.configure(useWebVpn: false);
    var calls = 0;
    final auth = ClassroomAuthService(cookieLoader: (_) async {
      calls++;
      return const [];
    });
    expect(await auth.cookieHeader(), isNull);
    expect(calls, 0);
  });

  test('proxied classroom requests use portal and classroom cookies', () async {
    ClassroomUrlResolver.configure(useWebVpn: true);
    final hosts = <String>[];
    final auth = ClassroomAuthService(cookieLoader: (uri) async {
      hosts.add(uri.host);
      if (uri.host == 'webvpn.shu.edu.cn') {
        return const [
          SessionCookie(
            name: 'webvpn-token',
            value: 'session',
            domain: 'webvpn.shu.edu.cn',
          ),
        ];
      }
      return [
        SessionCookie(name: 'classroom', value: 'ok', domain: uri.host),
      ];
    });
    expect(await auth.cookieHeader(), 'webvpn-token=session; classroom=ok');
    expect(hosts, ['webvpn.shu.edu.cn', ClassroomUrlResolver.webVpnHost]);
  });
}
