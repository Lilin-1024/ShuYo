import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shuyo/data/models/client_backend.dart';
import 'package:shuyo/data/services/client_backend_api_client.dart';

http.Response jsonResponse(Object data, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), status);

void main() {
  test(
      'student feedback and presence use Bearer credentials; legacy lookup keeps its token',
      () async {
    final requests = <http.Request>[];
    final client =
        ClientBackendApiClient(httpClient: MockClient((request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/api/v1/student/feedback':
          if (request.method == 'POST') {
            return jsonResponse({
              'success': true,
              'data': {'id': 'sf_one', 'status': 'open'}
            }, 201);
          }
          return jsonResponse({
            'success': true,
            'data': [
              {
                'id': 'sf_one',
                'title': '新版',
                'content': '内容',
                'status': 'open',
                'replies': []
              }
            ]
          }, 200);
        case '/api/v1/student/feedback/sf_one':
          return jsonResponse({
            'success': true,
            'data': {
              'id': 'sf_one',
              'title': '新版',
              'content': '内容',
              'status': 'open',
              'replies': []
            }
          }, 200);
        case '/api/v1/student/feedback/sf_one/close':
          return jsonResponse({
            'success': true,
            'data': {
              'id': 'sf_one',
              'title': '新版',
              'content': '内容',
              'status': 'closed',
              'replies': []
            }
          }, 200);
        case '/api/v1/student/presence/heartbeat':
          return http.Response('', 204);
        case '/api/v1/feedback/fb_old':
          return jsonResponse({
            'success': true,
            'data': {
              'id': 'fb_old',
              'title': '旧版',
              'content': '内容',
              'status': 'open',
              'replies': []
            }
          }, 200);
      }
      return http.Response('not found', 404);
    }));
    const token = 'student-session-token';
    final list = await client.listStudentFeedback(token);
    expect(list.single.lookupToken, isEmpty);
    const draft = ClientFeedbackDraft(
      title: '新版',
      content: '内容',
      contact: '',
      deviceId: '',
      appVersion: '1.0',
      platform: 'ios',
    );
    expect((await client.submitStudentFeedback(token, draft)).id, 'sf_one');
    expect(
        (await client.closeStudentFeedback(token, 'sf_one')).status, 'closed');
    await client.reportStudentPresence(token);
    expect(
        (await client.fetchFeedback('fb_old', 'old-lookup-token')).lookupToken,
        'old-lookup-token');
    for (final request in requests
        .where((item) => item.url.path.startsWith('/api/v1/student/'))) {
      expect(request.headers['authorization'], 'Bearer $token');
      expect(request.headers.containsKey('x-feedback-token'), isFalse);
    }
    expect(requests.last.headers['x-feedback-token'], 'old-lookup-token');
  });
}
