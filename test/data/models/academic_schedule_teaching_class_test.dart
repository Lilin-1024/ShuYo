import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/academic_schedule.dart';

void main() {
  test('parser keeps the teaching class id and cache round-trips it', () {
    final schedule = AcademicScheduleParser.parse({
      'kbList': [
        {
          'jxb_id': 'ABC123',
          'kch_id': 'GBK0102001',
          'kcmc': '离散数学',
          'xm': '盛斌',
          'xqj': '1',
          'jcs': '1-2',
          'zcd': '1-10周',
        },
      ],
    });
    final session = schedule.sessions.single;
    expect(session.teachingClassId, 'ABC123');
    expect(CourseSession.fromJson(session.toJson()).teachingClassId, 'ABC123');
    final legacy = session.toJson()..remove('teachingClassId');
    expect(CourseSession.fromJson(legacy).teachingClassId, '');
  });
}
