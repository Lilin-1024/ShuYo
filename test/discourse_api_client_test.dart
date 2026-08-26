import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shuyo/core/forum_url_resolver.dart';
import 'package:shuyo/data/services/discourse_api_client.dart';
import 'package:shuyo/data/services/forum_auth_service.dart';

void main() {
  tearDown(() {
    ForumUrlResolver.configure(useWebVpn: false);
  });

  test('repairs WebVPN polluted unicode escapes in JSON responses', () async {
    ForumUrlResolver.configure(useWebVpn: true);
    const body = r'''{
      "post_stream": {
        "posts": [
          {
            "cooked": "\u003ca href=\"https://https-yingxin-shu-edu-cn-443.webvpn.shu.edu.cn/bksyxrk.htm\" rel=\"noopener nofollow ugc\"\https-u003eyingxin-shu-edu-cn-443.webvpn.shu.edu.cn\u003c/a\u003e"
          }
        ]
      }
    }''';
    final client = DiscourseApiClient(
      authService: _NoCookieForumAuthService(),
      httpClient: MockClient((request) async {
        return http.Response.bytes(utf8.encode(body), 200);
      }),
    );

    final json = await client.getJson('/t/topic/884.json');
    final posts =
        (json['post_stream'] as Map<String, dynamic>)['posts'] as List;
    final cooked = (posts.single as Map<String, dynamic>)['cooked'] as String;

    expect(cooked, contains('rel="noopener nofollow ugc">'));
    expect(cooked, contains('yingxin-shu-edu-cn-443.webvpn.shu.edu.cn'));
  });

  test('uses WebVPN specific message when polluted JSON cannot be repaired',
      () async {
    ForumUrlResolver.configure(useWebVpn: true);
    final client = DiscourseApiClient(
      authService: _NoCookieForumAuthService(),
      httpClient: MockClient((request) async {
        return http.Response.bytes(utf8.encode(r'{"value":"\q"}'), 200);
      }),
    );

    expect(
      client.getJson('/t/topic/884.json'),
      throwsA(
        isA<ForumApiException>().having(
          (error) => error.message,
          'message',
          forumWebVpnParseFailedMessage,
        ),
      ),
    );
  });

  test('persists Set-Cookie values returned by native API requests', () async {
    final auth = _NoCookieForumAuthService();
    final client = DiscourseApiClient(
      authService: auth,
      httpClient: MockClient((request) async {
        return http.Response(
          '{"current_user":null}',
          200,
          headers: const {
            'set-cookie': '_forum_session=rotated; Path=/; Max-Age=3600',
          },
        );
      }),
    );

    await client.getJson('/session/current.json');

    expect(auth.responseCookieHeaders,
        contains('_forum_session=rotated; Path=/; Max-Age=3600'));
  });
}

class _NoCookieForumAuthService implements ForumAuthService {
  final responseCookieHeaders = <String>[];

  @override
  Future<String?> cookieHeader() async => null;

  @override
  Future<void> clearCachedCookies() async {}

  @override
  Future<void> clearCookies() async {}

  @override
  Future<bool> hasForumCookies() async => false;

  @override
  Future<void> persistLastCookieHeader() async {}

  @override
  Future<void> refreshFromWebView() async {}

  @override
  Future<void> updateFromSetCookieHeaders(
    Uri responseUri,
    Iterable<String> headerValues,
  ) async {
    responseCookieHeaders.addAll(headerValues);
  }
}
