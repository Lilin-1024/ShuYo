import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shuyo/data/models/academic_schedule.dart';
import 'package:shuyo/data/services/schedule_comparison.dart';
import 'package:shuyo/data/services/schedule_share_service.dart';

const term = AcademicTerm(
  yearCode: '2026',
  termCode: '3',
  academicYearName: '2026-2027',
  termName: '秋',
  studentName: '不应上传',
  studentId: '12345678',
  className: '一班',
);

CourseSession course(String name, int weekday, List<int> weeks,
        {List<int> sections = const [1, 2]}) =>
    CourseSession(
      id: 'manual:random',
      courseName: name,
      courseCode: '_manual',
      teacherName: '张老师',
      campus: '宝山',
      location: '一教',
      weekday: weekday,
      startSection: sections.first,
      endSection: sections.last,
      sections: sections,
      weeks: weeks,
      weekText: '自定义',
      credit: '3',
      note: '私人备注',
    );

AcademicSchedule schedule(List<CourseSession> sessions) => AcademicSchedule(
      term: term,
      sessions: sessions,
      untimedCourses: const [
        UntimedCourse(
          id: 'untimed-random',
          courseName: '实践课',
          teacherName: '李老师',
          campus: '宝山',
          weeks: [1, 2],
          weekText: '1-2周',
          summary: '自主安排',
          credit: '1',
        )
      ],
      fetchedAt: DateTime.utc(2026, 10, 8),
    );

void main() {
  test('share requests keep student token in the header and code in the body',
      () async {
    final requests = <http.Request>[];
    final api = ScheduleShareApi(client: MockClient((request) async {
      requests.add(request);
      final data = switch (request.url.path) {
        '/api/v1/student/shares' => {
            'id': 'share-one',
            'code': 'Ab3D4e',
            'expiresAt': '2026-10-22T00:00:00Z',
            'termLabel': '2026 秋',
            'includeNote': false
          },
        '/api/v1/shares/resolve' => {
            'snapshot': scheduleShareSnapshot(
                schedule([
                  course('高数', 1, [1])
                ]),
                includeNote: false),
            'digest': 'digest-one'
          },
        _ => null,
      };
      return http.Response.bytes(
          utf8.encode(jsonEncode({'success': true, 'data': data})),
          request.method == 'POST' && request.url.path.endsWith('/shares')
              ? 201
              : 200);
    }));
    final info = await api.generate(
        'student-token',
        schedule([
          course('高数', 1, [1])
        ]),
        includeNote: false,
        requestId: 'request-aaaaaaaa');
    expect(info.code, 'Ab3D4e');
    await api.resolve(info.code);
    expect(requests.first.headers['authorization'], 'Bearer student-token');
    expect(requests.first.body.contains('12345678'), isFalse);
    expect(requests.last.url.toString().contains(info.code), isFalse);
    expect(jsonDecode(requests.last.body)['code'], info.code);
  });

  test(
      'share snapshot includes hand edits but strips identity and local display data',
      () {
    final snapshot = scheduleShareSnapshot(
        schedule([
          course('高数', 1, [1, 3])
        ]),
        includeNote: false);
    expect(snapshot['term']['studentId'], isNull);
    expect(snapshot['term']['studentName'], isNull);
    expect(snapshot['term']['className'], isNull);
    expect(snapshot['sessions'][0]['id'], isNull);
    expect(snapshot['sessions'][0]['note'], isNull);
    expect(snapshot['sessions'][0]['teacherName'], '张老师');
    expect(snapshot['untimedCourses'][0]['summary'], '自主安排');
    expect(
        scheduleShareSnapshot(
            schedule([
              course('高数', 1, [1, 3])
            ]),
            includeNote: true)['sessions'][0]['note'],
        '私人备注');
  });

  test('imported copies are separate files, deduplicated locally and read only',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('shuyo-import-test-');
    try {
      final store = ImportedScheduleStore(directory: directory);
      final result = SharedScheduleResult(
        snapshot: scheduleShareSnapshot(
            schedule([
              course('高数', 1, [1, 3])
            ]),
            includeNote: false),
        digest: 'digest-one',
      );
      final imported = await store.save(result);
      expect(imported.name, '课表 1');
      expect((await store.save(result)).id, imported.id);
      final second = await store.save(SharedScheduleResult(
        snapshot: result.snapshot, digest: 'digest-two'));
      expect(second.name, '课表 2');
      expect((await store.list()).length, 2);
      final copy = imported.toSchedule(localWeekCount: 16);
      expect(copy.term.studentId, isEmpty);
      expect(copy.sessions.single.courseName, '高数');
      expect(copy.maxWeek, 16);
      await store.rename(imported, '朋友课表');
      expect((await store.list()).any((item) => item.name == '朋友课表'), isTrue);
      await store.delete(imported.id);
      expect((await store.list()).single.name, '课表 2');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('common free cells use each schedule’s actual week and exact sections',
      () {
    final first = schedule([
      course('单周', 1, [1], sections: [1, 3])
    ]);
    final second = schedule([
      course('双周', 1, [2], sections: [2])
    ]);
    final one = commonFreeSections([first, second], 1);
    expect(one.contains((1, 1)), isFalse);
    expect(one.contains((1, 2)), isTrue);
    expect(one.contains((1, 3)), isFalse);
    final two = commonFreeSections([first, second], 2);
    expect(two.contains((1, 1)), isTrue);
    expect(two.contains((1, 2)), isFalse);
    expect(commonFreeSections([first], 1), isEmpty);
    final lateClass = schedule([course('晚课', 2, [1], sections: [13, 14])]);
    final extended = commonFreeSections([first, lateClass], 1, maxSection: 14);
    expect(extended.contains((2, 13)), isFalse);
    expect(extended.contains((2, 12)), isTrue);
  });
}
