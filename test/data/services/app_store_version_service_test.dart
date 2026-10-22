import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shuyo/core/client_user_agent.dart';
import 'package:shuyo/core/client_update_policy.dart';
import 'package:shuyo/data/services/app_store_version_service.dart';

void main() {
  test('compares App Store dotted versions numerically', () {
    expect(
      AppStoreVersionInfo.compareVersions('1.10.0', '1.9.9'),
      greaterThan(0),
    );
    expect(AppStoreVersionInfo.compareVersions('1.2', '1.2.0'), 0);
    expect(AppStoreVersionInfo.compareVersions('2.0.0', '2.0.1'), lessThan(0));
  });

  test('returns a newer App Store version and uses bundle lookup', () async {
    late http.Request capturedRequest;
    final service = AppStoreVersionService(
      bundleId: 'work.shuyo.app',
      currentVersion: '0.3.6',
      httpClient: MockClient((request) async {
        capturedRequest = request;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'resultCount': 1,
              'results': [
                {
                  'bundleId': 'work.shuyo.app',
                  'version': '0.4.0',
                  'trackId': 123456789,
                  'trackViewUrl':
                      'https://apps.apple.com/cn/app/shuyo/id123456789',
                },
              ],
            }),
          ),
          200,
        );
      }),
    );

    final update = await service.checkForUpdate();

    expect(update?.version, '0.4.0');
    expect(update?.productUrl, contains('id123456789'));
    expect(capturedRequest.url.host, 'itunes.apple.com');
    expect(capturedRequest.url.queryParameters['bundleId'], 'work.shuyo.app');
    expect(capturedRequest.url.queryParameters['country'], 'cn');
  });

  test('returns null when the App Store version is not newer', () async {
    final service = AppStoreVersionService(
      bundleId: 'work.shuyo.app',
      currentVersion: '0.3.6',
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'resultCount': 1,
            'results': [
              {
                'bundleId': 'work.shuyo.app',
                'version': '0.3.6',
                'trackId': 123456789,
                'trackViewUrl': 'https://apps.apple.com/app/id123456789',
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(await service.checkForUpdate(), isNull);
  });

  test('reports an unavailable version before the first App Store release',
      () async {
    final service = AppStoreVersionService(
      bundleId: 'work.shuyo.app',
      currentVersion: '0.3.6',
      httpClient: MockClient((request) async {
        return http.Response('{"resultCount":0,"results":[]}', 200);
      }),
    );

    expect(
      service.checkForUpdate(),
      throwsA(isA<AppStoreVersionUnavailableException>()),
    );
  });

  test('selects a browser user agent for each mobile platform', () {
    expect(
      ClientUserAgent.forPlatform(TargetPlatform.iOS),
      contains('iPhone'),
    );
    expect(
      ClientUserAgent.forPlatform(TargetPlatform.android),
      contains('Android'),
    );
  });

  test('uses App Store updates only on iOS', () {
    expect(
      ClientUpdatePolicy.forPlatform(TargetPlatform.iOS),
      ClientUpdateSource.appStore,
    );
    expect(
      ClientUpdatePolicy.forPlatform(TargetPlatform.android),
      ClientUpdateSource.backend,
    );
  });
}
