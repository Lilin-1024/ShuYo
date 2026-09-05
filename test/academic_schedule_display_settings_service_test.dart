import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/academic_schedule_display_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('schedule display settings default to disabled', () async {
    final service = AcademicScheduleDisplaySettingsService();

    final settings = await service.loadSettings();

    expect(settings.colorful, isFalse);
    expect(settings.showTeacher, isFalse);
  });

  test('schedule display settings are persisted', () async {
    final service = AcademicScheduleDisplaySettingsService();

    await service.saveSettings(
      const AcademicScheduleDisplaySettings(
        colorful: true,
        showTeacher: true,
      ),
    );
    final settings = await service.loadSettings();

    expect(settings.colorful, isTrue);
    expect(settings.showTeacher, isTrue);
  });

  test('custom course colors are persisted by course identity', () async {
    final service = AcademicScheduleDisplaySettingsService();

    await service.saveCourseColor('CS101', 0xFF6C96CA);

    expect(await service.loadCourseColors(), {'CS101': 0xFF6C96CA});
  });
}
