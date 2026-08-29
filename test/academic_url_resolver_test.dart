import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/core/academic_constants.dart';
import 'package:shuyo/core/academic_url_resolver.dart';
import 'package:shuyo/core/forum_url_resolver.dart';

void main() {
  tearDown(() => ForumUrlResolver.configure(useWebVpn: false));

  test('direct mode resolves the campus entry and ticket URLs', () {
    ForumUrlResolver.configure(useWebVpn: false);

    expect(AcademicUrlResolver.entryUri.host, AcademicConstants.host);
    expect(
      AcademicUrlResolver.isTicketLoginUrl(
        'https://${AcademicConstants.host}/jwglxt/ticketlogin?uid=1',
      ),
      isTrue,
    );
    expect(
      AcademicUrlResolver.isTicketLoginUrl(
        'https://${AcademicUrlResolver.webVpnHost}/jwglxt/ticketlogin',
      ),
      isFalse,
    );
  });

  test('WebVPN mode resolves the transformed campus host', () {
    ForumUrlResolver.configure(useWebVpn: true);

    expect(AcademicUrlResolver.entryUri.host, AcademicUrlResolver.webVpnHost);
    expect(
      AcademicUrlResolver.isTicketLoginUrl(
        'https://${AcademicUrlResolver.webVpnHost}/jwglxt/ticketlogin',
      ),
      isTrue,
    );
    expect(
      AcademicUrlResolver.isPreparedWebVpnAcademicUrl(
        'https://${AcademicUrlResolver.webVpnHost}/jwglxt/xtgl/index_initMenu.html',
      ),
      isTrue,
    );
  });
}
