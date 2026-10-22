import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/core/academic_constants.dart';
import 'package:shuyo/core/academic_url_resolver.dart';

void main() {
  test('direct mode resolves the campus entry and ticket URLs', () {
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

  test('WebVPN setting does not change the academic route', () {
    expect(AcademicUrlResolver.entryUri.host, AcademicConstants.host);
    expect(
      AcademicUrlResolver.isTicketLoginUrl(
        'https://${AcademicUrlResolver.webVpnHost}/jwglxt/ticketlogin',
      ),
      isFalse,
    );
    expect(
      AcademicUrlResolver.isAcademicSessionUrl(
        'https://${AcademicConstants.host}/jwglxt/xtgl/index_initMenu.html',
      ),
      isTrue,
    );
    // The login exchange answers with HTTP 200 on these paths even without a
    // session, so neither may be read as a completed login.
    expect(
      AcademicUrlResolver.isAcademicSessionUrl(
        'https://${AcademicConstants.host}/jwglxt/ticketlogin?uid=1',
      ),
      isFalse,
    );
    expect(
      AcademicUrlResolver.isAcademicSessionUrl(
        'https://${AcademicConstants.host}/jwglxt/xtgl/login_slogin.html',
      ),
      isFalse,
    );
    expect(
      AcademicUrlResolver.isAcademicSessionUrl(
        'https://${AcademicUrlResolver.webVpnHost}/jwglxt/xtgl/index_initMenu.html',
      ),
      isFalse,
    );
  });
}
