import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/core/classroom_url_resolver.dart';

void main() {
  tearDown(() {
    ClassroomUrlResolver.configure(useWebVpn: false);
  });

  test('classroom routing switches with WebVPN setting', () {
    ClassroomUrlResolver.configure(useWebVpn: false);
    expect(ClassroomUrlResolver.baseUri.host, ClassroomUrlResolver.directHost);

    ClassroomUrlResolver.configure(useWebVpn: true);
    expect(ClassroomUrlResolver.baseUri.host, ClassroomUrlResolver.webVpnHost);
  });

  test('uses Shanghai time for classroom external access boundaries', () {
    expect(
      ClassroomAccessWindow.isExternalAccessOpen(
        DateTime.utc(2026, 9, 6, 23),
      ),
      isTrue,
    );
    expect(
      ClassroomAccessWindow.isExternalAccessOpen(
        DateTime.utc(2026, 9, 7, 15),
      ),
      isFalse,
    );
  });

  test('closed-window failure explains campus and WebVPN alternatives', () {
    final message = ClassroomAccessWindow.directFailureMessage(
      now: DateTime.utc(2026, 9, 7, 16),
    );

    expect(message, contains('每日23:00至次日07:00'));
    expect(message, contains('校园网'));
    expect(message, contains('开启WebVPN'));
  });
}
