import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/features/auth/webvpn_oauth_completion_page.dart';

void main() {
  test('redirect progress invalidates a transient WebVPN resource error', () {
    const callback = 'https://webvpn.shu.edu.cn/callback/oauth2';
    const academic =
        'https://https-jwxt-shu-edu-cn-443.webvpn.shu.edu.cn/jwglxt/xtgl/index_initMenu.html';

    expect(hasWebVpnNavigationProgressed(callback, academic), isTrue);
    expect(hasWebVpnNavigationProgressed(callback, '$callback/'), isFalse);
    expect(hasWebVpnNavigationProgressed(null, academic), isFalse);
  });
}
