import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../models/academic_schedule.dart';
import '../repositories/academic_schedule_repository.dart';
import 'client_settings_service.dart';

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

class AcademicScheduleAlarmSettings {
  const AcademicScheduleAlarmSettings({
    required this.enabled,
    required this.leadMinutes,
  });

  final bool enabled;
  final int leadMinutes;

  AcademicScheduleAlarmSettings copyWith({
    bool? enabled,
    int? leadMinutes,
  }) {
    return AcademicScheduleAlarmSettings(
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
    MethodChannel? alarmChannel,
  })  : _repository = repository,
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
        _alarmChannel = alarmChannel ??
            const MethodChannel('work.shuyo.app/early_class_alarms');

  static const _enabledKey = 'academic.schedule.notifications.enabled';
  static const _leadMinutesKey = 'academic.schedule.notifications.leadMinutes';
  static const _alarmEnabledKey = 'academic.schedule.alarms.enabled';
  static const _alarmLeadMinutesKey = 'academic.schedule.alarms.leadMinutes';
  static const _channelId = 'course_reminders';
  static const _baseNotificationId = 420000;
  static const _maxPendingReminders = 64;

  final AcademicScheduleRepository _repository;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final FlutterLocalNotificationsPlugin _notifications;
  final MethodChannel _alarmChannel;
  bool _initialized = false;

  Future<AcademicScheduleNotificationSettings> loadSettings() async {
    final prefs = await _preferencesLoader();
    return AcademicScheduleNotificationSettings(
      // Keep reminders disabled until the user turns them on manually.
      enabled: prefs.getBool(_enabledKey) ?? false,
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
      final notificationAllowed = await _ensureNotificationPermission(
        request: requestPermission,
      );
      final exactAllowed = notificationAllowed &&
          await _ensureExactAlarmPermission(request: requestPermission);
      if (!notificationAllowed || !exactAllowed) {
        next = next.copyWith(enabled: false);
      }
    }
    final saved = await saveSettings(next);
    await syncScheduleReminders(requestPermission: false);
    return saved;
  }

  Future<bool> supportsEarlyClassAlarms() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return false;
    }
    try {
      return await _alarmChannel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<AcademicScheduleAlarmSettings> loadAlarmSettings() async {
    final prefs = await _preferencesLoader();
    return AcademicScheduleAlarmSettings(
      enabled: prefs.getBool(_alarmEnabledKey) ?? false,
      leadMinutes: prefs.getInt(_alarmLeadMinutesKey) ?? 20,
    );
  }

  Future<AcademicScheduleAlarmSettings> saveAlarmSettings(
    AcademicScheduleAlarmSettings settings,
  ) async {
    final prefs = await _preferencesLoader();
    final normalized = settings.copyWith(
      leadMinutes: settings.leadMinutes.clamp(1, 120),
    );
    await prefs.setBool(_alarmEnabledKey, normalized.enabled);
    await prefs.setInt(_alarmLeadMinutesKey, normalized.leadMinutes);
    return normalized;
  }

  Future<AcademicScheduleAlarmSettings> saveAlarmSettingsAndSync(
    AcademicScheduleAlarmSettings settings, {
    bool requestPermission = false,
  }) async {
    var next = settings;
    if (next.enabled && requestPermission) {
      final allowed =
          await _alarmChannel.invokeMethod<bool>('requestAuthorization') ??
              false;
      if (!allowed) {
        next = next.copyWith(enabled: false);
      }
    }
    await saveAlarmSettings(next);
    await syncEarlyClassAlarms();
    return loadAlarmSettings();
  }

  Future<int> syncEarlyClassAlarms({DateTime? now}) async {
    if (!await supportsEarlyClassAlarms()) {
      return 0;
    }
    await _ensureInitialized();
    final settings = await loadAlarmSettings();
    final schedule =
        settings.enabled ? await _repository.loadCachedSchedule() : null;
    final alarms = <_EarlyClassAlarm>[];
    if (schedule != null) {
      final weekState = await _repository.loadWeekState();
      alarms.addAll(
        _upcomingEarlyClassAlarms(
          schedule: schedule,
          weekState: weekState,
          leadMinutes: settings.leadMinutes,
          now: now ?? DateTime.now(),
        ),
      );
    }
    final count = await _alarmChannel.invokeMethod<int>('sync', {
          'alarms': alarms.map((alarm) => alarm.toMap()).toList(),
        }) ??
        0;
    if (count < 0) {
      if (settings.enabled) {
        await saveAlarmSettings(settings.copyWith(enabled: false));
      }
      return 0;
    }
    return count;
  }

  Future<int> syncScheduleReminders({bool requestPermission = false}) async {
    try {
      await syncEarlyClassAlarms();
    } on PlatformException {
      // Local notification syncing remains independent of AlarmKit.
    }
    await _ensureInitialized();
    await _cancelCourseReminders();

    final clientSettings = await ClientSettingsService(
      preferencesLoader: _preferencesLoader,
    ).loadNotificationSettings();
    if (!clientSettings.scheduleEnabled) {
      return 0;
    }

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
    final exactAllowed = await _ensureExactAlarmPermission(
      request: requestPermission,
    );
    if (!exactAllowed) {
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
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

    final ios = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      if (!request) {
        final permissions = await ios.checkPermissions();
        if (permissions?.isEnabled == false) {
          return false;
        }
      } else {
        final iosGranted = await ios.requestPermissions(
          alert: true,
          sound: true,
        );
        if (iosGranted == false) {
          return false;
        }
      }
    }

    if (request) {
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

  Future<bool> _ensureExactAlarmPermission({required bool request}) async {
    await _ensureInitialized();
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canScheduleExact = await android?.canScheduleExactNotifications();
    if (canScheduleExact == false && request) {
      final granted = await android?.requestExactAlarmsPermission();
      if (granted == false) {
        return false;
      }
    } else if (canScheduleExact == false) {
      return false;
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

  Iterable<_EarlyClassAlarm> _upcomingEarlyClassAlarms({
    required AcademicSchedule schedule,
    required ScheduleWeekState weekState,
    required int leadMinutes,
    required DateTime now,
  }) sync* {
    final shanghaiNow = timezone.TZDateTime.from(now, timezone.local);
    final today =
        DateTime(shanghaiNow.year, shanghaiNow.month, shanghaiNow.day);
    final alarms = <_EarlyClassAlarm>[];
    final maxDays = schedule.maxWeek * 7 + 7;

    for (var dayOffset = 0; dayOffset < maxDays; dayOffset++) {
      final day = today.add(Duration(days: dayOffset));
      final week = _rawWeekForDate(weekState, day);
      if (week < 1) {
        continue;
      }
      if (schedule.isVacationWeek(week)) {
        break;
      }

      CourseSession? earliest;
      for (final session in schedule.sessions) {
        final range =
            AcademicScheduleRepository.sectionTimes[session.startSection];
        final isMorning = range != null && range.$1 < 12;
        if (session.weekday == day.weekday &&
            session.occursInWeek(week) &&
            isMorning &&
            (earliest == null ||
                session.startSection < earliest.startSection)) {
          earliest = session;
        }
      }
      if (earliest == null) {
        continue;
      }

      final range =
          AcademicScheduleRepository.sectionTimes[earliest.startSection]!;
      final start = timezone.TZDateTime(
        timezone.local,
        day.year,
        day.month,
        day.day,
        range.$1,
        range.$2,
      );
      final fireTime = start.subtract(Duration(minutes: leadMinutes));
      if (fireTime.isAfter(shanghaiNow.add(const Duration(seconds: 30)))) {
        alarms.add(
          _EarlyClassAlarm(
            title: earliest.courseName.isEmpty ? '早课' : earliest.courseName,
            fireTime: fireTime,
          ),
        );
      }
    }

    yield* alarms;
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
      if (schedule.isVacationWeek(week)) {
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

class _EarlyClassAlarm {
  const _EarlyClassAlarm({required this.title, required this.fireTime});

  final String title;
  final DateTime fireTime;

  Map<String, Object> toMap() => {
        'title': title,
        'fireTime': fireTime.millisecondsSinceEpoch,
      };
}
