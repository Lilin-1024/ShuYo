import '../models/academic_schedule.dart';
import '../models/announcement.dart';
import '../models/classroom.dart';
import '../models/course_rating.dart';
import '../repositories/academic_schedule_repository.dart';
import '../repositories/announcement_repository.dart';
import '../repositories/classroom_repository.dart';
import '../repositories/course_rating_repository.dart';

class DemoAcademicScheduleRepository extends AcademicScheduleRepository {
  DemoAcademicScheduleRepository(this.schedule);

  final AcademicSchedule schedule;

  @override
  Future<AcademicSchedule?> loadCachedSchedule() async => schedule;

  @override
  Future<AcademicSchedule> refreshSchedule() async => schedule;

  @override
  Future<void> saveCachedSchedule(AcademicSchedule schedule) async {}
}

class DemoAnnouncementRepository extends AnnouncementRepository {
  DemoAnnouncementRepository({
    required this.items,
    required this.details,
  });

  final List<AnnouncementListItem> items;
  final Map<String, AnnouncementDetail> details;

  @override
  Future<List<AnnouncementListItem>> loadCachedAnnouncements() async => items;

  @override
  Future<List<AnnouncementListItem>> fetchAnnouncements(
          {bool forceRefresh = false}) async =>
      items;

  @override
  Future<AnnouncementDetail> fetchDetail(AnnouncementListItem item) async =>
      details[item.title] ??
      AnnouncementDetail(title: item.title, url: item.url, blocks: const []);

  @override
  Future<AnnouncementHomeSummary> homeSummary() async => items.isEmpty
      ? const AnnouncementHomeSummary('点击查看通知公告')
      : AnnouncementHomeSummary(items.first.title);
}

class DemoClassroomRepository extends ClassroomRepository {
  DemoClassroomRepository({
    required this.options,
    required this.schedule,
  });

  final ClassroomSearchOptions options;
  final ClassroomBuildingSchedule schedule;

  @override
  Future<ClassroomSearchOptions> loadOptions(
          {bool forceRefresh = false}) async =>
      options;

  @override
  Future<ClassroomAvailabilityResult> search(ClassroomAvailabilityQuery query,
      {bool forceRefresh = false}) async {
    final supported = query.building.id == schedule.building.id &&
        query.date.year == 2026 &&
        query.date.month == 9 &&
        query.date.day == 1;
    if (!supported) {
      return ClassroomAvailabilityResult(
        building: query.building,
        date: query.date,
        startSection: query.startSection,
        endSection: query.endSection,
        floors: const [],
      );
    }
    final floors = schedule.floors.map((floor) {
      final available = floor.rooms
          .where((room) => room.isFreeFor(query.startSection, query.endSection))
          .toList(growable: false);
      return ClassroomFloorAvailability(
          floor: floor, rooms: floor.rooms, availableRooms: available);
    }).toList(growable: false);
    return ClassroomAvailabilityResult(
        building: query.building,
        date: query.date,
        startSection: query.startSection,
        endSection: query.endSection,
        floors: floors);
  }
}

class DemoCourseRatingRepository extends CourseRatingRepository {
  DemoCourseRatingRepository(this.latest);

  final CourseRatingLatestResult latest;

  @override
  Future<CourseRatingLatestResult> fetchLatest(
          {bool forceRefresh = false}) async =>
      latest;

  @override
  Future<CourseRatingSearchResult> search(String keyword,
      {bool forceRefresh = false}) async {
    final query = normalizeKeyword(keyword).toLowerCase();
    if (query.isEmpty) {
      return const CourseRatingSearchResult(
          query: '', courses: [], teachers: []);
    }
    final courses = <CourseRatingCourse>[];
    final teachers = <CourseRatingTeacher>[];
    for (final item in latest.ratings) {
      if (item.courseName.toLowerCase().contains(query) ||
          item.courseCode.toLowerCase().contains(query)) {
        courses.add(CourseRatingCourse(
            id: item.courseId,
            name: item.courseName,
            courseCode: item.courseCode));
      }
      if (item.teacherName.toLowerCase().contains(query)) {
        teachers.add(
            CourseRatingTeacher(id: item.teacherId, name: item.teacherName));
      }
    }
    return CourseRatingSearchResult(
        query: keyword,
        courses: _uniqueCourses(courses),
        teachers: _uniqueTeachers(teachers));
  }

  @override
  Future<CourseRatingCourseTeachers> fetchCourseTeachers(
      CourseRatingCourse course,
      {bool forceRefresh = false}) async {
    final teachers = latest.ratings
        .where((item) => item.courseName == course.name)
        .map((item) =>
            CourseRatingTeacher(id: item.teacherId, name: item.teacherName))
        .toList();
    return CourseRatingCourseTeachers(
        course: course, teachers: _uniqueTeachers(teachers));
  }

  @override
  Future<CourseRatingTeacherCourses> fetchTeacherCourses(
      CourseRatingTeacher teacher,
      {bool forceRefresh = false}) async {
    final courses = latest.ratings
        .where((item) => item.teacherName == teacher.name)
        .map((item) => CourseRatingCourse(
            id: item.courseId,
            name: item.courseName,
            courseCode: item.courseCode))
        .toList();
    return CourseRatingTeacherCourses(
        teacher: teacher, courses: _uniqueCourses(courses));
  }

  @override
  Future<CourseRatingDetail> fetchRatingDetail(
      {required CourseRatingCourse course,
      required CourseRatingTeacher teacher,
      int page = 1,
      bool forceRefresh = false}) async {
    final ratings = latest.ratings
        .where((item) =>
            item.courseName == course.name && item.teacherName == teacher.name)
        .map((item) => CourseRatingItem(
            id: item.id,
            score: item.score,
            content: item.content,
            createdAt: item.createdAt,
            upvotes: item.upvotes,
            user: item.user))
        .toList(growable: false);
    final average = ratings.isEmpty
        ? 0.0
        : ratings.map((item) => item.score).reduce((a, b) => a + b) /
            ratings.length;
    return CourseRatingDetail(
        course: course,
        teacher: teacher,
        average: average,
        total: ratings.length,
        page: page,
        perPage: ratings.length,
        ratings: ratings,
        radar: const CourseRatingRadar(categories: [], values: []));
  }

  static List<CourseRatingCourse> _uniqueCourses(
      List<CourseRatingCourse> values) {
    final map = <String, CourseRatingCourse>{};
    for (final value in values) {
      map[value.name] = value;
    }
    return map.values.toList(growable: false);
  }

  static List<CourseRatingTeacher> _uniqueTeachers(
      List<CourseRatingTeacher> values) {
    final map = <int, CourseRatingTeacher>{};
    for (final value in values) {
      map[value.id] = value;
    }
    return map.values.toList(growable: false);
  }
}
