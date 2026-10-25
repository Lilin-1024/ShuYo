import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/course_review.dart';

void main() {
  const unitJson = {
    'id': 'u_1',
    'role': 'co',
    'reviewCount': 3,
    'average': 8.3,
    'lastReviewedAt': '2026-10-08T09:00:00.000Z',
    'course': {'id': 'GBK001', 'name': '体育(1)', 'college': '体育学院', 'credits': '1'},
    'teacher': {
      'id': 't_1',
      'name': '王五',
      'college': '体育学院',
      'title': '讲师',
      'duplicateName': true,
    },
  };

  test('unit summary parses scores and disambiguates duplicate names', () {
    final unit = RateUnit.fromJson(unitJson);
    expect(unit.isCoTeacher, isTrue);
    expect(unit.average, 8.3);
    expect(unit.teacher.displayName, '王五（体育学院）');
    expect(unit.course.metaText, 'GBK001 · 体育学院 · 1 学分');
    final empty = RateUnit.fromJson({...unitJson, 'average': null});
    expect(empty.average, isNull);
  });

  test('lookup results map every server status', () {
    final results = [
      {'status': 'unit', 'unit': unitJson},
      {'status': 'course', 'courseId': 'C1', 'units': [unitJson]},
      {'status': 'search', 'query': '体育(1) 王五'},
      {'status': 'none', 'query': '不存在'},
    ].map(RateLookupResult.fromJson).toList();
    expect(results.map((item) => item.status), RateLookupStatus.values);
    expect(results[0].unit?.id, 'u_1');
    expect(results[1].units.single.id, 'u_1');
    expect(results[2].query, '体育(1) 王五');
  });

  test('schedule course and review draft only send what the server needs', () {
    const course = RateScheduleCourse(
      teachingClassId: '',
      courseCode: '',
      courseName: '计算思维实训',
      teacherName: '赵俊娟',
    );
    expect(course.toJson(), {'courseName': '计算思维实训', 'teacherName': '赵俊娟'});
    const draft = RateReviewDraft(overall: 4, answers: {
      'workload': ['none'],
      'grading': [],
    });
    expect(draft.toJson(), {
      'overall': 4,
      'answers': {
        'workload': ['none'],
      },
    });
  });

  test('question stats keep highlight flags', () {
    final stat = RateQuestionStat.fromJson({
      'key': 'attendance_method',
      'title': '签到方式',
      'multiple': true,
      'answered': 2,
      'options': [
        {'key': 'qr', 'label': '扫码签到', 'count': 2, 'percent': 100, 'top': true},
        {'key': 'quiz', 'label': '小测', 'count': 1, 'percent': 50, 'top': false},
      ],
    });
    expect(stat.options.where((option) => option.top).single.key, 'qr');
  });
}
