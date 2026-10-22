import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/academic_schedule_display_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('schedule display settings use expected defaults', () async {
    final service = AcademicScheduleDisplaySettingsService();

    final settings = await service.loadSettings();

    expect(settings.colorful, isTrue);
    expect(settings.showTeacher, isTrue);
    expect(settings.showCredit, isFalse);
    expect(settings.showNote, isFalse);
    expect(settings.showNonCurrentWeekCourses, isTrue);
  });

  test('schedule display settings are persisted', () async {
    final service = AcademicScheduleDisplaySettingsService();

    await service.saveSettings(
      const AcademicScheduleDisplaySettings(
        colorful: false,
        showTeacher: false,
        showCredit: true,
        showNote: true,
        showNonCurrentWeekCourses: false,
      ),
    );
    final settings = await service.loadSettings();

    expect(settings.colorful, isFalse);
    expect(settings.showTeacher, isFalse);
    expect(settings.showCredit, isTrue);
    expect(settings.showNote, isTrue);
    expect(settings.showNonCurrentWeekCourses, isFalse);
  });

  test('custom course colors are persisted by course identity', () async {
    final service = AcademicScheduleDisplaySettingsService();

    await service.saveCourseColor('CS101', 0xFF6C96CA);

    expect(await service.loadCourseColors(), {'CS101': 0xFF6C96CA});
  });
}
