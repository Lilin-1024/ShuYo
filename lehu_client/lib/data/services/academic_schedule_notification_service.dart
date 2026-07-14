import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../models/academic_schedule.dart';
import '../repositories/academic_schedule_repository.dart';

class AcademicScheduleNotificationSettings {
  const AcademicScheduleNotificationSettings({
    required this.enabled,
    required this.leadMinutes,
  });

  final bool enabled;
  final int leadMinutes;

  AcademicScheduleNotificationSettings copyWith({
    bool? enabled,
    int? leadMinutes,
  }) {
    return AcademicScheduleNotificationSettings(
      enabled: enabled ?? this.enabled,
      leadMinutes: leadMinutes ?? this.leadMinutes,
    );
  }
}

class AcademicScheduleNotificationService {
  AcademicScheduleNotificationService({
    required AcademicScheduleRepository repository,
    Future<SharedPreferences> Function()? preferencesLoader,
    FlutterLocalNotificationsPlugin? notifications,
  })  : _repository = repository,
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  static const _enabledKey = 'academic.schedule.notifications.enabled';
  static const _leadMinutesKey = 'academic.schedule.notifications.leadMinutes';
  static const _channelId = 'course_reminders';
  static const _baseNotificationId = 420000;
  static const _maxPendingReminders = 64;

  final AcademicScheduleRepository _repository;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final FlutterLocalNotificationsPlugin _notifications;
  bool _initialized = false;

  Future<AcademicScheduleNotificationSettings> loadSettings() async {
    final prefs = await _preferencesLoader();
    return AcademicScheduleNotificationSettings(
      enabled: prefs.getBool(_enabledKey) ?? true,
      leadMinutes: prefs.getInt(_leadMinutesKey) ?? 20,
    );
  }

  Future<AcademicScheduleNotificationSettings> saveSettings(
    AcademicScheduleNotificationSettings settings,
  ) async {
    final prefs = await _preferencesLoader();
    final normalized = settings.copyWith(
      leadMinutes: settings.leadMinutes.clamp(1, 120),
    );
    await prefs.setBool(_enabledKey, normalized.enabled);
    await prefs.setInt(_leadMinutesKey, normalized.leadMinutes);
    return normalized;
  }

  Future<AcademicScheduleNotificationSettings> saveSettingsAndSync(
    AcademicScheduleNotificationSettings settings, {
    bool requestPermission = false,
  }) async {
    var next = settings;
    if (next.enabled) {
      final allowed = await _ensureNotificationPermission(
        request: requestPermission,
      );
      if (!allowed) {
        next = next.copyWith(enabled: false);
      }
    }
    final saved = await saveSettings(next);
    await syncScheduleReminders(requestPermission: false);
    return saved;
  }

  Future<int> syncScheduleReminders({bool requestPermission = false}) async {
    await _ensureInitialized();
    await _cancelCourseReminders();

    final settings = await loadSettings();
    if (!settings.enabled) {
      return 0;
    }
    final allowed = await _ensureNotificationPermission(
      request: requestPermission,
    );
    if (!allowed) {
      return 0;
    }

    final schedule = await _repository.loadCachedSchedule();
    if (schedule == null) {
      return 0;
    }
    final weekState = await _repository.loadWeekState();
    final reminders = _upcomingReminders(
      schedule: schedule,
      weekState: weekState,
      leadMinutes: settings.leadMinutes,
      now: DateTime.now(),
    ).take(_maxPendingReminders).toList();

    for (var index = 0; index < reminders.length; index++) {
      final reminder = reminders[index];
      await _notifications.zonedSchedule(
        id: _baseNotificationId + index,
        title: reminder.session.courseName,
        body: reminder.body(settings.leadMinutes),
        scheduledDate: timezone.TZDateTime.from(
          reminder.fireTime,
          timezone.local,
        ),
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'course:${reminder.session.id}',
      );
    }
    return reminders.length;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    timezone_data.initializeTimeZones();
    timezone.setLocalLocation(timezone.getLocation('Asia/Shanghai'));
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<bool> _ensureNotificationPermission({required bool request}) async {
    await _ensureInitialized();
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidEnabled = await android?.areNotificationsEnabled();
    if (androidEnabled == false && request) {
      final granted = await android?.requestNotificationsPermission();
      if (granted == false) {
        return false;
      }
    } else if (androidEnabled == false) {
      return false;
    }

    if (request) {
      final ios = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final iosGranted = await ios?.requestPermissions(
        alert: true,
        sound: true,
      );
      if (iosGranted == false) {
        return false;
      }

      final macOS = _notifications.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final macOSGranted = await macOS?.requestPermissions(
        alert: true,
        sound: true,
      );
      if (macOSGranted == false) {
        return false;
      }
    }

    return true;
  }

  Future<void> _cancelCourseReminders() async {
    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending) {
      final isCourseReminder = request.id >= _baseNotificationId &&
          request.id < _baseNotificationId + _maxPendingReminders;
      if (isCourseReminder) {
        await _notifications.cancel(id: request.id);
      }
    }
  }

  Iterable<_CourseReminder> _upcomingReminders({
    required AcademicSchedule schedule,
    required ScheduleWeekState weekState,
    required int leadMinutes,
    required DateTime now,
  }) sync* {
    final reminders = <_CourseReminder>[];
    final today = DateTime(now.year, now.month, now.day);
    final maxDays = schedule.maxWeek * 7 + 7;
    for (var dayOffset = 0; dayOffset < maxDays; dayOffset++) {
      final day = today.add(Duration(days: dayOffset));
      final week = _rawWeekForDate(weekState, day);
      if (week < 1) {
        continue;
      }
      if (week > schedule.maxWeek) {
        break;
      }
      final sessions = schedule.sessions.where(
        (session) =>
            session.weekday == day.weekday && session.occursInWeek(week),
      );
      for (final session in sessions) {
        final start = AcademicScheduleRepository.sectionStartTime(
          session.startSection,
          day,
        );
        if (start == null) {
          continue;
        }
        final fireTime = start.subtract(Duration(minutes: leadMinutes));
        if (fireTime.isAfter(now.add(const Duration(seconds: 30)))) {
          reminders.add(_CourseReminder(session: session, fireTime: fireTime));
        }
      }
    }
    reminders.sort((a, b) => a.fireTime.compareTo(b.fireTime));
    yield* reminders;
  }

  int _rawWeekForDate(ScheduleWeekState state, DateTime date) {
    final monday = AcademicScheduleRepository.startOfWeek(date);
    final offset = monday.difference(state.anchorMonday).inDays ~/ 7;
    return state.currentWeek + offset;
  }

  static const _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      '课程提醒',
      channelDescription: '在课程开始前提醒',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );
}

class _CourseReminder {
  const _CourseReminder({
    required this.session,
    required this.fireTime,
  });

  final CourseSession session;
  final DateTime fireTime;

  String body(int leadMinutes) {
    final location = session.location.isEmpty ? '' : ' · ${session.location}';
    return '$leadMinutes 分钟后开始$location';
  }
}
