import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/models/academic_ranking.dart';
import 'package:shuyo/data/repositories/academic_ranking_repository.dart';
import 'package:shuyo/data/services/academic_account_store.dart';
import 'package:shuyo/data/services/academic_auth_service.dart';
import 'package:shuyo/data/services/academic_ranking_api_client.dart';
import 'package:shuyo/data/services/academic_ranking_parser.dart';
import 'package:shuyo/data/services/academic_schedule_api_client.dart';

class _AuthWithCookie extends AcademicAuthService {
  _AuthWithCookie()
      : super(cookieLoader: (_) async => [], cookieSetter: (_) async {});

  @override
  Future<String?> cookieHeader({Uri? targetUri}) async => 'JSESSIONID=test';
}

const _rankingResponse = '''
{"items":[{"xh_id":"DEMO0001","xnm":"2026","xqm":"3",
"xnmc":"2026-2027","xqmc":"秋","jgmc":"计算机工程与科学学院",
"xxzymc":"计算机科学与技术","njjgpjjdpm":"315","njjgrs":"460",
"njxxzypjjdpm":"73","njxxzyrs":"103","czsj":"2026-09-30 15:16:04"}],
"totalCount":1}
''';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('parses college and major ranking from the supplied field names', () {
    final ranking = AcademicRankingParser.parse(
      _rankingResponse,
      expectedStudentId: 'DEMO0001',
      fetchedAt: DateTime(2026, 10, 2),
    );
    expect(ranking.collegeRank, 315);
    expect(ranking.collegeCount, 460);
    expect(ranking.majorRank, 73);
    expect(ranking.majorCount, 103);
    expect(ranking.academicYear, '2026-2027');
    expect(ranking.term, '秋');
    expect(ranking.hasRank, isTrue);
    expect(
      AcademicRanking.fromJson(jsonDecode(jsonEncode(ranking.toJson())))
          .collegeRank,
      315,
    );
  });

  test('empty results are valid and another student is rejected', () {
    final empty = AcademicRankingParser.parse('{"items":[],"totalCount":0}',
        expectedStudentId: 'DEMO0001');
    expect(empty.hasRank, isFalse);
    expect(empty.studentId, 'DEMO0001');
    expect(
      () => AcademicRankingParser.parse(
        _rankingResponse,
        expectedStudentId: 'OTHER',
      ),
      throwsFormatException,
    );
  });

  test('chooses the latest term when the response contains several rows', () {
    final response = jsonDecode(_rankingResponse) as Map<String, dynamic>;
    final latest = (response['items'] as List).single as Map<String, dynamic>;
    response['items'] = [
      {...latest, 'xnm': '2025', 'xqm': '32', 'njjgpjjdpm': '8'},
      latest,
    ];
    final ranking = AcademicRankingParser.parse(
      jsonEncode(response),
      expectedStudentId: 'DEMO0001',
    );
    expect(ranking.collegeRank, 315);
  });

  test('queries with the campus cookie and keeps cache after a failure',
      () async {
    final requests = <http.Request>[];
    var fail = false;
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response.bytes(utf8.encode('<html>排名页面</html>'), 200);
      }
      if (fail) return http.Response('unavailable', 503);
      return http.Response.bytes(utf8.encode(_rankingResponse), 200,
          headers: {'content-type': 'application/json;charset=UTF-8'});
    });
    final repository = AcademicRankingRepository(
      apiClient: AcademicRankingApiClient(
        authService: _AuthWithCookie(),
        httpClient: client,
      ),
    );
    await AcademicAccountStore().saveStudentId('DEMO0001');
    final first = await repository.refreshRanking();
    expect(first.collegeRank, 315);
    expect(requests.length, 2);
    final post = requests.last;
    expect(post.method, 'POST');
    expect(post.url.queryParameters['doType'], 'query');
    expect(post.headers['cookie'], 'JSESSIONID=test');
    expect(post.bodyFields['queryModel.showCount'], '15');
    expect(post.bodyFields['queryModel.currentPage'], '1');
    expect(post.bodyFields['queryModel.sortName'], ' ');
    expect(post.bodyFields['nd'], isNotEmpty);

    fail = true;
    await expectLater(
        repository.refreshRanking(), throwsA(isA<AcademicApiException>()));
    expect((await repository.loadCachedRanking())?.collegeRank, 315);
    await AcademicAccountStore().saveStudentId('OTHER');
    expect(await repository.loadCachedRanking(), isNull);
  });
}
