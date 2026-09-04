import 'package:shared_preferences/shared_preferences.dart';

class AcademicScheduleDisplaySettings {
  const AcademicScheduleDisplaySettings({
    required this.colorful,
    required this.showTeacher,
  });

  final bool colorful;
  final bool showTeacher;

  AcademicScheduleDisplaySettings copyWith({
    bool? colorful,
    bool? showTeacher,
  }) {
    return AcademicScheduleDisplaySettings(
      colorful: colorful ?? this.colorful,
      showTeacher: showTeacher ?? this.showTeacher,
    );
  }
}

class AcademicScheduleDisplaySettingsService {
  AcademicScheduleDisplaySettingsService({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _colorfulKey = 'academic.schedule.display.colorful';
  static const _showTeacherKey = 'academic.schedule.display.showTeacher';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<AcademicScheduleDisplaySettings> loadSettings() async {
    final prefs = await _preferencesLoader();
    return AcademicScheduleDisplaySettings(
      colorful: prefs.getBool(_colorfulKey) ?? false,
      showTeacher: prefs.getBool(_showTeacherKey) ?? false,
    );
  }

  Future<AcademicScheduleDisplaySettings> saveSettings(
    AcademicScheduleDisplaySettings settings,
  ) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(_colorfulKey, settings.colorful);
    await prefs.setBool(_showTeacherKey, settings.showTeacher);
    return settings;
  }
}
