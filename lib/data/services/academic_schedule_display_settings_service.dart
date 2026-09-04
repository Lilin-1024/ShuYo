import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
  static const _courseColorsKey = 'academic.schedule.display.courseColors';

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

  Future<Map<String, int>> loadCourseColors() async {
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(_courseColorsKey);
    if (raw == null || raw.isEmpty) {
      return <String, int>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, int>{};
      }
      return <String, int>{
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
      };
    } on Object {
      return <String, int>{};
    }
  }

  Future<void> saveCourseColor(String key, int colorValue) async {
    final colors = await loadCourseColors();
    colors[key] = colorValue;
    final prefs = await _preferencesLoader();
    await prefs.setString(_courseColorsKey, jsonEncode(colors));
  }
}
