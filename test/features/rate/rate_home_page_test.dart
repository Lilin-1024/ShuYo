import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/course_review.dart';
import 'package:shuyo/data/repositories/academic_schedule_repository.dart';
import 'package:shuyo/data/repositories/course_review_repository.dart';
import 'package:shuyo/data/services/student_identity_service.dart';
import 'package:shuyo/features/rate/rate_home_page.dart';
import 'package:shuyo/features/rate/rate_list_pages.dart';
import 'package:shuyo/features/rate/rate_widgets.dart';

RateUnit _unit(String id, String name, double average, int count) =>
    RateUnit.fromJson({
      'id': id,
      'role': 'lead',
      'average': average,
      'reviewCount': count,
      'course': {'id': id, 'name': name, 'college': '测试学院', 'credits': '2'},
      'teacher': {'id': 'teacher-$id', 'name': '测试教师'},
    });

final _recent = _unit('recent', '最近评价课程', 8.6, 11);
final _rankings = [
  RateRankingPreview(
    key: 'general',
    title: '通识课',
    total: 1,
    items: [_unit('general', '通识课程', 9.0, 17)],
  ),
  RateRankingPreview(
    key: 'pe',
    title: '体育',
    total: 1,
    items: [_unit('pe', '体育课程', 8.0, 23)],
  ),
  RateRankingPreview(
    key: 'public',
    title: '公共基础课',
    total: 1,
    items: [_unit('public', '公共基础课程', 7.0, 29)],
  ),
];

class _FakeCourseReviewRepository extends CourseReviewRepository {
  _FakeCourseReviewRepository()
      : super(
          studentIdentityService: StudentIdentityService(),
          scheduleRepository: AcademicScheduleRepository(),
        );

  @override
  Future<RateHome> home() async => RateHome(
        recent: [_recent],
        rankings: [
          ..._rankings,
          RateRankingPreview(
            key: 'seminar',
            title: '新生研讨课',
            total: 1,
            items: [_unit('seminar', '研讨课程', 9.0, 31)],
          ),
        ],
        colleges: const [],
      );

  @override
  Future<List<RateScheduleMatch>> matchSchedule() async => const [];

  @override
  Future<RateRankingResult> ranking(String category,
      {String sub = '', int page = 1}) async {
    final ranking = _rankings.singleWhere((item) => item.key == category);
    return RateRankingResult(
      key: ranking.key,
      title: ranking.title,
      subcategories: const [],
      total: ranking.total,
      page: page,
      pageSize: 20,
      items: ranking.items,
    );
  }
}

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = _FakeCourseReviewRepository();
  addTearDown(repository.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RateHomePage(repository: repository, active: false),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('homepage rankings match recent cards and show stars without counts',
      (tester) async {
    await _pumpHome(tester);
    final recentCard = find.ancestor(
      of: find.text(_recent.course.name),
      matching: find.byType(RateCard),
    );
    final recentSurface = tester.widget<Material>(
      find.descendant(of: recentCard, matching: find.byType(Material)),
    );
    expect(tester.getSize(recentCard), const Size(156, 112));
    for (final ranking in _rankings) {
      expect(find.text(ranking.title), findsOneWidget);
      final unit = ranking.items.single;
      final card = find.ancestor(
        of: find.text('1  ${unit.course.name}'),
        matching: find.byType(RateCard),
      );
      expect(tester.getSize(card), tester.getSize(recentCard));
      final surface = tester.widget<Material>(
        find.descendant(of: card, matching: find.byType(Material)),
      );
      expect(surface.shape, recentSurface.shape);
      expect(surface.color, recentSurface.color);
      expect(
        find.descendant(of: card, matching: find.byType(RateStars)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text(rateScoreText(unit.average)),
        ),
        findsOneWidget,
      );
    }
    expect(find.textContaining('份'), findsNothing);
    expect(find.text('新生研讨课'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (var index = 0; index < _rankings.length; index++) {
    final ranking = _rankings[index];
    testWidgets('${ranking.title} list retains review counts', (tester) async {
      await _pumpHome(tester);
      await tester.tap(find.byType(RateMoreButton).at(index));
      await tester.pumpAndSettle();
      expect(find.byType(RateRankingPage), findsOneWidget);
      expect(
        find.text('${ranking.items.single.reviewCount} 份评价'),
        findsOneWidget,
      );
      expect(find.byType(RateScoreTrailing), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
