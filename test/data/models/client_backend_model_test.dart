import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/client_backend.dart';

void main() {
  test('parses WebVPN status from the client bootstrap payload', () {
    final bootstrap = ClientBootstrapInfo.fromJson({
      'success': true,
      'data': {
        'version': {'latestBuild': 1},
        'webVpnStatus': {
          'status': 'available',
          'checkedAt': '2026-09-07T12:00:00.000Z',
          'statusSince': '2026-09-07T11:00:00.000Z',
          'lastSuccessAt': '2026-09-07T12:00:00.000Z',
          'latencyMs': 320,
          'reason': 'ok',
        },
      },
    });

    expect(bootstrap.webVpnStatus.state, WebVpnServiceState.available);
    expect(bootstrap.webVpnStatus.latencyMs, 320);
    expect(
      bootstrap.webVpnStatus.checkedAt,
      DateTime.parse('2026-09-07T12:00:00.000Z'),
    );
  });

  test('keeps compatibility with a bootstrap payload without WebVPN status',
      () {
    final bootstrap = ClientBootstrapInfo.fromJson({
      'success': true,
      'data': {
        'version': {'latestBuild': 1},
      },
    });

    expect(bootstrap.webVpnStatus.state, WebVpnServiceState.unknown);
  });

  test('treats stale WebVPN monitoring data as unknown', () {
    final status = WebVpnServiceStatus(
      state: WebVpnServiceState.available,
      checkedAt: DateTime.parse('2026-09-07T12:00:00.000Z'),
      statusSince: null,
      lastSuccessAt: null,
      latencyMs: 100,
      reason: 'ok',
    );

    expect(
      status.effectiveStateAt(DateTime.parse('2026-09-07T12:06:00.000Z')),
      WebVpnServiceState.unknown,
    );
  });
}
