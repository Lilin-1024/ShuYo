// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/academic_schedule.dart';
import '../../data/repositories/academic_schedule_repository.dart';
import '../../data/services/academic_schedule_api_client.dart';
import '../../data/services/academic_schedule_display_settings_service.dart';
import '../../data/services/academic_schedule_notification_service.dart';
import '../../data/services/academic_schedule_widget_service.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../../shared/widgets/empty_state.dart';
import 'academic_schedule_editor_page.dart';

const _scheduleCellInset = 2.5;
const _scheduleCourseInset = 2.5;
const _scheduleCellRadius = 4.0;
const _scheduleCourseRadius = 5.0;

class AcademicSchedulePage extends StatefulWidget {
  const AcademicSchedulePage({
    super.key,
    required this.repository,
    required this.notificationService,
    required this.widgetService,
    required this.onLoginRequired,
  });

  final AcademicScheduleRepository repository;
  final AcademicScheduleNotificationService notificationService;
  final AcademicScheduleWidgetService widgetService;
  final Future<void> Function() onLoginRequired;

  @override
  State<AcademicSchedulePage> createState() => _AcademicSchedulePageState();
}

class _AcademicSchedulePageState extends State<AcademicSchedulePage> {
  late Future<void> _loadFuture;
  AcademicSchedule? _schedule;
  ScheduleWeekState? _weekState;
  _ScheduleSlot? _selectedManualSlot;
  int _displayedWeek = 1;
  bool _refreshing = false;
  bool _followsCurrentWeek = true;
  Timer? _weekTimer;
  final _displaySettingsService = AcademicScheduleDisplaySettingsService();
  AcademicScheduleDisplaySettings _displaySettings =
      const AcademicScheduleDisplaySettings(
          colorful: false, showTeacher: false);
  Map<String, int> _courseColorValues = const {};

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadCached();
    unawaited(_loadDisplaySettings());
    _weekTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshDisplayedWeekIfNeeded(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_schedule?.term.displayName ?? '课表'),
        actions: [
          TextButton(
            onPressed: _schedule == null ? null : _setDisplayedWeekAsCurrent,
            child: const Text('设为当周'),
          ),
          IconButton(
            tooltip: '更多',
            onPressed: _openMoreMenu,
            icon: const Icon(Icons.more_horiz),
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 3));
          }
          if (snapshot.hasError) {
            return _ScheduleErrorState(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _loadFuture = _loadCached()),
            );
          }
          final schedule = _schedule;
          final weekState = _weekState;
          if (schedule == null || weekState == null) {
            return EmptyState(
              icon: Icons.calendar_month_outlined,
              title: '还没有课表',
              message: '登录教务后刷新一次，就可以在本地显示课表。',
              action: FilledButton.icon(
                onPressed: _refreshSchedule,
                icon: const Icon(Icons.refresh),
                label: const Text('同步课表'),
              ),
            );
          }
          return _ScheduleBody(
            schedule: schedule,
            weekState: weekState,
            displayedWeek: _displayedWeek,
            displaySettings: _displaySettings,
            courseColorValues: _courseColorValues,
            onPreviousWeek: _displayedWeek <= 0
                ? null
                : () => setState(() {
                      _displayedWeek--;
                      _followsCurrentWeek = false;
                      _selectedManualSlot = null;
                    }),
            onNextWeek: _displayedWeek >= schedule.vacationWeek
                ? null
                : () => setState(() {
                      _displayedWeek++;
                      _followsCurrentWeek = false;
                      _selectedManualSlot = null;
                    }),
            onQuickWeekSelected: (week) => setState(() {
              _displayedWeek = week;
              _followsCurrentWeek = false;
              _selectedManualSlot = null;
            }),
            selectedManualSlot: _selectedManualSlot,
            canAddCourse: !schedule.isVacationWeek(_displayedWeek),
            onEmptySlotTap: _handleEmptySlotTap,
            onCourseTap: _handleCourseTap,
          );
        },
      ),
    );
  }

  Future<void> _loadDisplaySettings() async {
    final settings = await _displaySettingsService.loadSettings();
    final colorValues = await _displaySettingsService.loadCourseColors();
    if (!mounted) {
      return;
    }
    setState(() {
      _displaySettings = settings;
      _courseColorValues = colorValues;
    });
  }

  Future<void> _loadCached() async {
    final schedule = await widget.repository.loadCachedSchedule();
    final weekState = await widget.repository.loadWeekState();
    if (!mounted) {
      return;
    }
    setState(() {
      _schedule = schedule;
      _weekState = weekState;
      _displayedWeek = schedule == null
          ? 1
          : widget.repository.activeWeekFromState(schedule, weekState);
      _followsCurrentWeek = true;
    });
    unawaited(
      widget.widgetService.syncSchedule(
        schedule: schedule,
        weekState: weekState,
      ),
    );
  }

  Future<void> _refreshSchedule() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      final schedule = await widget.repository.refreshSchedule();
      final weekState = await widget.repository.loadWeekState();
      if (!mounted) {
        return;
      }
      setState(() {
        _schedule = schedule;
        _weekState = weekState;
        _displayedWeek =
            widget.repository.activeWeekFromState(schedule, weekState);
        _followsCurrentWeek = true;
      });
      unawaited(
        widget.widgetService.syncSchedule(
          schedule: schedule,
          weekState: weekState,
        ),
      );
      final reminderCount =
          await widget.notificationService.syncScheduleReminders(
        requestPermission: true,
      );
      _showScheduleReminderSnack('课表已同步', reminderCount);
    } on AcademicAuthException catch (_) {
      await _handleLoginRequired();
    } on Object catch (error) {
      await _showErrorDialog(
        title: '课表刷新失败',
        message: error.toString(),
      );
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _handleLoginRequired() async {
    if (!mounted) {
      return;
    }
    final retry = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('需要登录教务系统'),
          content: const Text('请先在教务系统完成登录，然后回到这里刷新课表。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('去登录'),
            ),
          ],
        );
      },
    );
    if (retry != true || !mounted) {
      return;
    }
    await widget.onLoginRequired();
    if (!mounted) {
      return;
    }
    await _loadCached();
    if (mounted && _schedule != null) _showSnack('课表已同步');
  }

  Future<void> _setDisplayedWeekAsCurrent() async {
    final week = _displayedWeek;
    await widget.repository.setCurrentWeek(week);
    final weekState = await widget.repository.loadWeekState();
    if (!mounted) {
      return;
    }
    setState(() {
      _weekState = weekState;
      _followsCurrentWeek = true;
    });
    unawaited(
      widget.widgetService.syncSchedule(
        schedule: _schedule,
        weekState: weekState,
      ),
    );
    await widget.notificationService.syncScheduleReminders(
      requestPermission: true,
    );
    _showSnack('已将第$week周设为当周');
  }

  Future<void> _handleEmptySlotTap(_ScheduleSlot slot) async {
    final schedule = _schedule;
    if (schedule == null || schedule.isVacationWeek(_displayedWeek)) {
      return;
    }
    final selected = _selectedManualSlot;
    if (selected != null && selected == slot) {
      await _openManualCourseSheet(slot);
      return;
    }
    setState(() => _selectedManualSlot = slot);
  }

  Future<void> _openManualCourseSheet(_ScheduleSlot slot) async {
    final schedule = _schedule;
    if (schedule == null || schedule.isVacationWeek(_displayedWeek)) {
      return;
    }
    final result = await Navigator.of(context).push<ScheduleCourseEditorResult>(
      MaterialPageRoute(
        builder: (context) => AcademicScheduleEditorPage(
          initialWeek: _displayedWeek,
          maxWeek: schedule.maxWeek,
          initialWeekday: slot.weekday,
          initialStartSection: slot.section,
          colorful: _displaySettings.colorful,
          palette: context.shuyoColors.schedulePalette,
          conflictValidator: (result) => _findEditorConflicts(schedule, result),
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final sessions = [
      for (final time in result.times)
        _courseSessionFromDraft(
          time,
          weekday: time.weekday,
          courseName: result.courseName,
          credit: result.credit,
        ),
    ];
    final next = schedule.copyWith(
      sessions: [...schedule.sessions, ...sessions],
    );
    await widget.repository.saveCachedSchedule(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _schedule = next;
      _selectedManualSlot = null;
    });
    if (result.colorValue != null) {
      final colorKey = _courseColorSeed(sessions.first);
      await _displaySettingsService.saveCourseColor(
        colorKey,
        result.colorValue!,
      );
      if (mounted) {
        setState(() => _courseColorValues = {
              ..._courseColorValues,
              colorKey: result.colorValue!,
            });
      }
    }
    unawaited(
      widget.widgetService.syncSchedule(
        schedule: next,
        weekState: _weekState,
      ),
    );
    unawaited(widget.notificationService.syncScheduleReminders());
  }

  Future<void> _handleCourseTap(CourseSession session) async {
    final action = await showModalBottomSheet<_ManualCourseAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = context.shuyoColors;
        final colorValue = _courseColorValues[_courseColorSeed(session)];
        final color = colorValue == null
            ? _courseColorForSession(context, session)
            : Color(colorValue);
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, 18, 20, 18 + bottomPadding),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        session.courseName,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _DetailLine(
                  Icons.schedule,
                  '${_weekdayName(session.weekday)} ${session.sectionText} ${session.weekText}',
                ),
                if (session.placeText.isNotEmpty)
                  _DetailLine(Icons.place_outlined, session.placeText),
                if (session.teacherName.isNotEmpty)
                  _DetailLine(Icons.person_outline, session.teacherName),
                if (session.credit.isNotEmpty)
                  _DetailLine(Icons.school_outlined, '${session.credit} 学分'),
                if (session.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      border: Border(
                        left: BorderSide(color: color, width: 3),
                      ),
                    ),
                    child: Text(
                      session.note.trim(),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop(_ManualCourseAction.edit),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('编辑'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context)
                            .pop(_ManualCourseAction.delete),
                        icon: Icon(Icons.delete_outline, color: colors.danger),
                        label: Text(
                          '删除',
                          style: TextStyle(color: colors.danger),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _ManualCourseAction.edit:
        await _openCourseEditSheet(session);
      case _ManualCourseAction.delete:
        final scope = await _openDeleteScopeMenu(session);
        if (scope == null || !mounted) {
          return;
        }
        final confirmed = await _confirmDeleteCourse(session, scope);
        if (confirmed) {
          await _deleteCourse(session, scope);
        }
    }
  }

  Future<void> _openCourseEditSheet(CourseSession session) async {
    final schedule = _schedule;
    if (schedule == null) {
      return;
    }
    final relatedSessions =
        schedule.sessions.where((item) => _sameCourse(item, session)).toList();
    final colorKey = _courseColorSeed(session);
    final result = await Navigator.of(context).push<ScheduleCourseEditorResult>(
      MaterialPageRoute(
        builder: (context) => AcademicScheduleEditorPage(
          initialWeek: _displayedWeek,
          maxWeek: schedule.maxWeek,
          initialWeekday: session.weekday,
          initialStartSection: session.startSection,
          initialSessions: relatedSessions,
          colorful: _displaySettings.colorful,
          palette: context.shuyoColors.schedulePalette,
          initialColorValue: _courseColorValues[colorKey],
          conflictValidator: (result) => _findEditorConflicts(
            schedule,
            result,
            excludingCourse: session,
          ),
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final nextSessions =
        schedule.sessions.where((item) => !_sameCourse(item, session)).toList();
    for (var index = 0; index < result.times.length; index++) {
      final time = result.times[index];
      nextSessions.add(_courseSessionFromDraft(
        time,
        weekday: time.weekday,
        base: index < relatedSessions.length ? relatedSessions[index] : session,
        courseName: result.courseName,
        credit: result.credit,
        forceNewId: index >= relatedSessions.length,
      ));
    }
    final next = schedule.copyWith(sessions: nextSessions);
    await widget.repository.saveCachedSchedule(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _schedule = next;
      _selectedManualSlot = null;
    });
    if (result.colorValue != null) {
      final nextColorKey = _courseColorSeed(nextSessions.last);
      await _displaySettingsService.saveCourseColor(
        nextColorKey,
        result.colorValue!,
      );
      if (mounted) {
        setState(() => _courseColorValues = {
              ..._courseColorValues,
              nextColorKey: result.colorValue!,
            });
      }
    }
    unawaited(
      widget.widgetService.syncSchedule(
        schedule: next,
        weekState: _weekState,
      ),
    );
    unawaited(widget.notificationService.syncScheduleReminders());
  }

  Future<void> _deleteCourse(
    CourseSession target,
    _CourseDeleteScope scope,
  ) async {
    final schedule = _schedule;
    if (schedule == null) {
      return;
    }
    final nextSessions = <CourseSession>[];
    var changed = false;
    for (final session in schedule.sessions) {
      final sameCourse = _sameCourse(session, target);
      final sameSlot = _sameCourseSlot(session, target);
      if (scope == _CourseDeleteScope.allCourseSlots && sameCourse) {
        changed = true;
        continue;
      }
      if (scope == _CourseDeleteScope.allWeeksInSlot &&
          sameCourse &&
          sameSlot) {
        changed = true;
        continue;
      }
      if (scope == _CourseDeleteScope.singleOccurrence &&
          _sameCourseIdentity(session, target)) {
        final weeks = session.weeks.isEmpty
            ? [
                for (var week = 1; week <= schedule.maxWeek; week++)
                  if (week != _displayedWeek) week,
              ]
            : session.weeks.where((week) => week != _displayedWeek).toList();
        if (weeks.isEmpty) {
          changed = true;
          continue;
        }
        changed = true;
        nextSessions.add(
          _copySessionWithWeeks(session, weeks),
        );
        continue;
      }
      nextSessions.add(session);
    }
    if (!changed) {
      return;
    }
    final next = schedule.copyWith(sessions: nextSessions);
    await widget.repository.saveCachedSchedule(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _schedule = next;
      _selectedManualSlot = null;
    });
    unawaited(
      widget.widgetService.syncSchedule(
        schedule: next,
        weekState: _weekState,
      ),
    );
    unawaited(widget.notificationService.syncScheduleReminders());
  }

  Future<_CourseDeleteScope?> _openDeleteScopeMenu(
    CourseSession session,
  ) {
    return showModalBottomSheet<_CourseDeleteScope>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = context.shuyoColors;
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
        final week = _displayedWeek;
        final weekday = _weekdayName(session.weekday);
        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomPadding),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: Text('仅第$week周$weekday的这节课'),
                  onTap: () => Navigator.of(context)
                      .pop(_CourseDeleteScope.singleOccurrence),
                ),
                ListTile(
                  leading: const Icon(Icons.view_week_outlined),
                  title: Text('全部$weekday的这节课'),
                  onTap: () => Navigator.of(context)
                      .pop(_CourseDeleteScope.allWeeksInSlot),
                ),
                ListTile(
                  leading:
                      Icon(Icons.delete_sweep_outlined, color: colors.danger),
                  title: Text(
                    '这门课程的全部时间段',
                    style: TextStyle(color: colors.danger),
                  ),
                  onTap: () => Navigator.of(context)
                      .pop(_CourseDeleteScope.allCourseSlots),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDeleteCourse(
    CourseSession session,
    _CourseDeleteScope scope,
  ) async {
    final description = switch (scope) {
      _CourseDeleteScope.singleOccurrence =>
        '仅删除第$_displayedWeek周${_weekdayName(session.weekday)}的这节课。',
      _CourseDeleteScope.allWeeksInSlot =>
        '删除${_weekdayName(session.weekday)}该时间段的全部周次。',
      _CourseDeleteScope.allCourseSlots => '删除这门课程的全部时间段。',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = context.shuyoColors;
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text('${session.courseName}\n$description'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: colors.danger,
                foregroundColor: Colors.white,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  // ignore: unused_element
  bool _hasScheduleConflict(
    AcademicSchedule schedule,
    ScheduleCourseTimeDraft draft,
    int weekday, {
    CourseSession? excluding,
  }) {
    final draftWeeks = draft.weeks.toSet();
    return schedule.sessions.any((session) {
      if (excluding != null && _sameCourseIdentity(session, excluding)) {
        return false;
      }
      if (session.weekday != weekday) {
        return false;
      }
      if (!_sectionRangesOverlap(
        session.startSection,
        session.endSection,
        draft.startSection,
        draft.endSection,
      )) {
        return false;
      }
      if (session.weeks.isEmpty) {
        return true;
      }
      return session.weeks.any(draftWeeks.contains);
    });
  }

  List<String> _findScheduleConflicts(
    AcademicSchedule schedule,
    ScheduleCourseTimeDraft draft, {
    CourseSession? excludingCourse,
  }) {
    final conflicts = <String>{};
    for (final session in schedule.sessions) {
      if (excludingCourse != null && _sameCourse(session, excludingCourse)) {
        continue;
      }
      if (session.weekday != draft.weekday ||
          !_sectionRangesOverlap(
            session.startSection,
            session.endSection,
            draft.startSection,
            draft.endSection,
          )) {
        continue;
      }
      final overlaps = session.weeks.isEmpty ||
          draft.weeks.isEmpty ||
          session.weeks.any(draft.weeks.toSet().contains);
      if (overlaps) {
        conflicts.add(
          '${session.courseName} · ${_formatSessionTime(session)}',
        );
      }
    }
    return conflicts.toList();
  }

  List<String> _findEditorConflicts(
    AcademicSchedule schedule,
    ScheduleCourseEditorResult result, {
    CourseSession? excludingCourse,
  }) {
    final conflicts = <String>[];
    for (var index = 0; index < result.times.length; index++) {
      final time = result.times[index];
      conflicts.addAll(
        _findScheduleConflicts(
          schedule,
          time,
          excludingCourse: excludingCourse,
        ),
      );
      for (var previous = 0; previous < index; previous++) {
        final other = result.times[previous];
        if (_timeDraftsOverlap(time, other)) {
          conflicts.add(_formatDraftTime(other));
        }
      }
    }
    return conflicts;
  }

  Future<void> _openMoreMenu() async {
    final action = await showModalBottomSheet<_ScheduleMenuAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
        final colors = context.shuyoColors;
        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomPadding),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: _refreshing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.refresh),
                  title: const Text('刷新课表'),
                  enabled: !_refreshing,
                  onTap: () => Navigator.of(context)
                      .pop(_ScheduleMenuAction.refreshSchedule),
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_none),
                  title: const Text('通知设置'),
                  onTap: () =>
                      Navigator.of(context).pop(_ScheduleMenuAction.settings),
                ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('显示设置'),
                  onTap: () => Navigator.of(context)
                      .pop(_ScheduleMenuAction.displaySettings),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _ScheduleMenuAction.refreshSchedule:
        await _refreshSchedule();
      case _ScheduleMenuAction.settings:
        await _openNotificationSettings();
      case _ScheduleMenuAction.displaySettings:
        await _openDisplaySettings();
    }
  }

  Future<void> _openDisplaySettings() async {
    final next = await showModalBottomSheet<AcademicScheduleDisplaySettings>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _DisplaySettingsSheet(initial: _displaySettings),
    );
    if (!mounted || next == null) {
      return;
    }
    final saved = await _displaySettingsService.saveSettings(next);
    if (!mounted) {
      return;
    }
    setState(() => _displaySettings = saved);
  }

  Future<void> _openNotificationSettings() async {
    final initial = await widget.notificationService.loadSettings();
    if (!mounted) {
      return;
    }
    final next =
        await showModalBottomSheet<AcademicScheduleNotificationSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NotificationSettingsSheet(initial: initial),
    );
    if (!mounted || next == null) {
      return;
    }
    final saved = await widget.notificationService.saveSettingsAndSync(
      next,
      requestPermission: next.enabled,
    );
    if (!mounted) {
      return;
    }
    if (next.enabled && !saved.enabled) {
      _showSnack('系统通知或精确提醒权限未开启，课程提醒已关闭');
      return;
    }
    _showSnack(
      saved.enabled ? '课程提醒已开启，提前 ${saved.leadMinutes} 分钟' : '课程提醒已关闭',
    );
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showScheduleReminderSnack(String prefix, int reminderCount) {
    final schedule = _schedule;
    if (schedule != null && schedule.isVacationWeek(_displayedWeek)) {
      _showSnack('$prefix，假期中无课程提醒');
      return;
    }
    if (reminderCount > 0) {
      _showSnack('$prefix，已安排 $reminderCount 条课程提醒');
      return;
    }
    _showSnack('$prefix，未安排课程提醒，请检查通知/精确提醒权限或当前周设置');
  }

  Future<void> _showErrorDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SelectableText(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  void _refreshDisplayedWeekIfNeeded() {
    final schedule = _schedule;
    final weekState = _weekState;
    if (!mounted ||
        !_followsCurrentWeek ||
        schedule == null ||
        weekState == null) {
      return;
    }
    final activeWeek = widget.repository.activeWeekFromState(
      schedule,
      weekState,
    );
    if (activeWeek == _displayedWeek) {
      return;
    }
    setState(() {
      _displayedWeek = activeWeek;
      _selectedManualSlot = null;
    });
    unawaited(
      widget.widgetService.syncSchedule(
        schedule: schedule,
        weekState: weekState,
      ),
    );
  }

  @override
  void dispose() {
    _weekTimer?.cancel();
    super.dispose();
  }
}

enum _ScheduleMenuAction {
  refreshSchedule,
  settings,
  displaySettings,
}

enum _ManualCourseAction {
  edit,
  delete,
}

enum _CourseDeleteScope {
  singleOccurrence,
  allWeeksInSlot,
  allCourseSlots,
}

// Kept until the legacy bottom-sheet editor is removed after the full-page
// editor rollout is verified.
class _ManualCourseDraft {
  const _ManualCourseDraft({
    required this.courseName,
    required this.location,
    required this.startSection,
    required this.endSection,
    required this.weeks,
  });

  final String courseName;
  final String location;
  final int startSection;
  final int endSection;
  final List<int> weeks;
}

class _DisplaySettingsSheet extends StatefulWidget {
  const _DisplaySettingsSheet({required this.initial});

  final AcademicScheduleDisplaySettings initial;

  @override
  State<_DisplaySettingsSheet> createState() => _DisplaySettingsSheetState();
}

class _DisplaySettingsSheetState extends State<_DisplaySettingsSheet> {
  late bool _colorful;
  late bool _showTeacher;

  @override
  void initState() {
    super.initState();
    _colorful = widget.initial.colorful;
    _showTeacher = widget.initial.showTeacher;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomPadding),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(
                '显示设置',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('多彩显示'),
              value: _colorful,
              onChanged: (value) => setState(() => _colorful = value),
            ),
            SwitchListTile(
              title: const Text('显示教师'),
              value: _showTeacher,
              onChanged: (value) => setState(() => _showTeacher = value),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    AcademicScheduleDisplaySettings(
                      colorful: _colorful,
                      showTeacher: _showTeacher,
                    ),
                  ),
                  child: const Text('完成'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleSlot {
  const _ScheduleSlot({
    required this.weekday,
    required this.section,
  });

  final int weekday;
  final int section;

  @override
  bool operator ==(Object other) {
    return other is _ScheduleSlot &&
        other.weekday == weekday &&
        other.section == section;
  }

  @override
  int get hashCode => Object.hash(weekday, section);
}

CourseSession _courseSessionFromDraft(
  ScheduleCourseTimeDraft draft, {
  required int weekday,
  CourseSession? base,
  required String courseName,
  required String credit,
  bool forceNewId = false,
}) {
  final sections = [
    for (var section = draft.startSection;
        section <= draft.endSection;
        section++)
      section,
  ];
  final weeks = [...draft.weeks]..sort();
  return CourseSession(
    id: !forceNewId && base != null
        ? base.id
        : '${CourseSession.manualIdPrefix}$weekday:'
            '${draft.startSection}-${draft.endSection}:'
            '${DateTime.now().microsecondsSinceEpoch}',
    courseName: courseName,
    courseCode: base?.courseCode ?? CourseSession.manualCode,
    teacherName: draft.teacherName,
    campus: base?.campus ?? '',
    location: draft.location,
    weekday: weekday,
    startSection: draft.startSection,
    endSection: draft.endSection,
    sections: sections,
    weeks: weeks,
    weekText: _formatWeekText(weeks),
    credit: credit,
    note: draft.note,
  );
}

bool _sameCourseIdentity(CourseSession session, CourseSession target) {
  return session.id == target.id &&
      session.weekday == target.weekday &&
      session.startSection == target.startSection &&
      session.endSection == target.endSection;
}

bool _sameCourse(CourseSession session, CourseSession target) {
  final sessionCode = session.courseCode.trim();
  final targetCode = target.courseCode.trim();
  if (!session.isManual &&
      !target.isManual &&
      sessionCode.isNotEmpty &&
      targetCode.isNotEmpty) {
    return sessionCode == targetCode;
  }
  return session.courseName.trim() == target.courseName.trim();
}

bool _sameCourseSlot(CourseSession session, CourseSession target) {
  return session.weekday == target.weekday &&
      session.startSection == target.startSection &&
      session.endSection == target.endSection;
}

CourseSession _copySessionWithWeeks(CourseSession session, List<int> weeks) {
  final sorted = [...weeks]..sort();
  return CourseSession(
    id: session.id,
    courseName: session.courseName,
    courseCode: session.courseCode,
    teacherName: session.teacherName,
    campus: session.campus,
    location: session.location,
    weekday: session.weekday,
    startSection: session.startSection,
    endSection: session.endSection,
    sections: session.sections,
    weeks: sorted,
    weekText: _formatWeekText(sorted),
    credit: session.credit,
    note: session.note,
  );
}

bool _sectionRangesOverlap(
  int startA,
  int endA,
  int startB,
  int endB,
) {
  return startA <= endB && startB <= endA;
}

bool _timeDraftsOverlap(
  ScheduleCourseTimeDraft a,
  ScheduleCourseTimeDraft b,
) {
  if (a.weekday != b.weekday ||
      !_sectionRangesOverlap(
        a.startSection,
        a.endSection,
        b.startSection,
        b.endSection,
      )) {
    return false;
  }
  final weeksA = a.weeks.toSet();
  final weeksB = b.weeks.toSet();
  return weeksA.isEmpty || weeksB.isEmpty || weeksA.any(weeksB.contains);
}

String _formatDraftTime(ScheduleCourseTimeDraft draft) {
  return '${_weekdayName(draft.weekday)} 第${draft.startSection}-${draft.endSection}节 '
      '（${_formatWeekText(draft.weeks)}）';
}

String _formatSessionTime(CourseSession session) {
  return '${_weekdayName(session.weekday)} ${session.sectionText} '
      '（${session.weekText.isEmpty ? _formatWeekText(session.weeks) : session.weekText}）';
}

String _formatWeekText(List<int> weeks) {
  if (weeks.isEmpty) {
    return '';
  }
  final sorted = [...weeks]..sort();
  final ranges = <String>[];
  var start = sorted.first;
  var previous = sorted.first;
  for (final week in sorted.skip(1)) {
    if (week == previous + 1) {
      previous = week;
      continue;
    }
    ranges.add(start == previous ? '$start周' : '$start-$previous周');
    start = week;
    previous = week;
  }
  ranges.add(start == previous ? '$start周' : '$start-$previous周');
  return ranges.join(',');
}

class _NotificationSettingsSheet extends StatefulWidget {
  const _NotificationSettingsSheet({required this.initial});

  final AcademicScheduleNotificationSettings initial;

  @override
  State<_NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState
    extends State<_NotificationSettingsSheet> {
  late bool _enabled;
  late int _leadMinutes;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initial.enabled;
    _leadMinutes = widget.initial.leadMinutes;
  }

  @override
  Widget build(BuildContext context) {
    final minuteOptions =
        <int>{5, 10, 15, 20, 30, 45, 60, _leadMinutes}.toList()..sort();
    final mediaQuery = MediaQuery.of(context);
    final colors = context.shuyoColors;
    final bottomInset = mediaQuery.viewInsets.bottom > 0
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.viewPadding.bottom;

    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          18 + bottomInset,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '通知设置',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('课程开始前提醒'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _leadMinutes,
              decoration: const InputDecoration(
                labelText: '提前多久提醒',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final value in minuteOptions)
                  DropdownMenuItem(
                    value: value,
                    child: Text('$value 分钟'),
                  ),
              ],
              onChanged: _enabled
                  ? (value) {
                      if (value != null) {
                        setState(() => _leadMinutes = value);
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(
                    AcademicScheduleNotificationSettings(
                      enabled: _enabled,
                      leadMinutes: _leadMinutes,
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _CourseEditorPage extends StatelessWidget {
  const _CourseEditorPage({
    required this.initialWeek,
    required this.maxWeek,
    required this.weekday,
    required this.initialStartSection,
    required this.submitLabel,
  });

  final int initialWeek;
  final int maxWeek;
  final int weekday;
  final int initialStartSection;
  final String submitLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加课程'),
      ),
      body: _ManualCourseSheet(
        initialWeek: initialWeek,
        maxWeek: maxWeek,
        weekday: weekday,
        initialStartSection: initialStartSection,
        submitLabel: submitLabel,
        fullPage: true,
      ),
    );
  }
}

class _ManualCourseSheet extends StatefulWidget {
  const _ManualCourseSheet({
    required this.initialWeek,
    required this.maxWeek,
    required this.weekday,
    required this.initialStartSection,
    required this.submitLabel,
    this.fullPage = false,
    // ignore: unused_element_parameter
    this.initialCourse,
  });

  final int initialWeek;
  final int maxWeek;
  final int weekday;
  final int initialStartSection;
  final String submitLabel;
  final bool fullPage;
  final CourseSession? initialCourse;

  @override
  State<_ManualCourseSheet> createState() => _ManualCourseSheetState();
}

class _ManualCourseSheetState extends State<_ManualCourseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _courseNameController = TextEditingController();
  final _locationController = TextEditingController();
  late int _startSection;
  late int _endSection;
  late Set<int> _weeks;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _courseNameController.addListener(_markDirty);
    _locationController.addListener(_markDirty);
    final initialCourse = widget.initialCourse;
    if (initialCourse != null) {
      _courseNameController.text = initialCourse.courseName;
      _locationController.text = initialCourse.location;
      _startSection = initialCourse.startSection.clamp(1, 12);
      _endSection = initialCourse.endSection.clamp(_startSection, 12);
      _weeks = initialCourse.weeks.isEmpty
          ? {for (var week = 1; week <= widget.maxWeek; week++) week}
          : initialCourse.weeks
              .where((week) => week >= 1 && week <= widget.maxWeek)
              .toSet();
      if (_weeks.isEmpty) {
        _weeks = {widget.initialWeek.clamp(1, widget.maxWeek)};
      }
      return;
    }
    _startSection = widget.initialStartSection.clamp(1, 12);
    _endSection = _startSection;
    _weeks = {widget.initialWeek.clamp(1, widget.maxWeek)};
  }

  @override
  void dispose() {
    _courseNameController.removeListener(_markDirty);
    _locationController.removeListener(_markDirty);
    _courseNameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom > 0
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.viewPadding.bottom;
    final content = SafeArea(
      top: false,
      bottom: false,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight:
              widget.fullPage ? double.infinity : mediaQuery.size.height * 0.88,
        ),
        padding: EdgeInsets.fromLTRB(20, 14, 20, 18 + bottomInset),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.fullPage)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.initialCourse == null
                              ? '${_weekdayName(widget.weekday)} 添加课程'
                              : '${_weekdayName(widget.weekday)} 编辑课程',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: _requestClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                if (!widget.fullPage) const SizedBox(height: 10),
                TextFormField(
                  controller: _courseNameController,
                  decoration: const InputDecoration(
                    labelText: '课程名称',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return '请填写课程名称';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: '上课地点',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _startSection,
                        decoration: const InputDecoration(
                          labelText: '起始节',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (var section = 1; section <= 12; section++)
                            DropdownMenuItem(
                              value: section,
                              child: Text('$section'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _dirty = true;
                            _startSection = value;
                            if (_endSection < _startSection) {
                              _endSection = _startSection;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _endSection,
                        decoration: const InputDecoration(
                          labelText: '结束节',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (var section = _startSection;
                              section <= 12;
                              section++)
                            DropdownMenuItem(
                              value: section,
                              child: Text('$section'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _dirty = true;
                              _endSection = value;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '上课周次',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (var week = 1; week <= widget.maxWeek; week++)
                      FilterChip(
                        label: Text('$week'),
                        selected: _weeks.contains(week),
                        onSelected: (selected) {
                          setState(() {
                            _dirty = true;
                            if (selected) {
                              _weeks.add(week);
                            } else if (_weeks.length > 1) {
                              _weeks.remove(week);
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submit,
                    child: Text(widget.submitLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return WillPopScope(onWillPop: _handleWillPop, child: content);
  }

  void _markDirty() {
    if (!_dirty && mounted) {
      setState(() => _dirty = true);
    }
  }

  Future<bool> _handleWillPop() async {
    if (!_dirty) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('放弃未保存的修改？'),
            content: const Text('当前修改尚未保存，确定要返回吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('放弃'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('继续修改'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _requestClose() async {
    if (await _handleWillPop() && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      _ManualCourseDraft(
        courseName: _courseNameController.text.trim(),
        location: _locationController.text.trim(),
        startSection: _startSection,
        endSection: _endSection,
        weeks: (_weeks.toList()..sort()),
      ),
    );
  }
}

class _ScheduleBody extends StatelessWidget {
  const _ScheduleBody({
    required this.schedule,
    required this.weekState,
    required this.displayedWeek,
    required this.displaySettings,
    required this.courseColorValues,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onQuickWeekSelected,
    required this.selectedManualSlot,
    required this.canAddCourse,
    required this.onEmptySlotTap,
    required this.onCourseTap,
  });

  final AcademicSchedule schedule;
  final ScheduleWeekState weekState;
  final int displayedWeek;
  final AcademicScheduleDisplaySettings displaySettings;
  final Map<String, int> courseColorValues;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;
  final ValueChanged<int> onQuickWeekSelected;
  final _ScheduleSlot? selectedManualSlot;
  final bool canAddCourse;
  final ValueChanged<_ScheduleSlot> onEmptySlotTap;
  final ValueChanged<CourseSession> onCourseTap;

  @override
  Widget build(BuildContext context) {
    final sessions = schedule.sessionsForWeek(displayedWeek);
    final untimed = schedule.untimedForWeek(displayedWeek);
    const weekdays = [1, 2, 3, 4, 5, 6, 7];

    return Column(
      children: [
        _WeekSwitcher(
          week: displayedWeek,
          isVacation: schedule.isVacationWeek(displayedWeek),
          maxWeek: schedule.maxWeek,
          onPrevious: onPreviousWeek,
          onNext: onNextWeek,
          onQuickWeekSelected: onQuickWeekSelected,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final weekdayWidth =
                  (constraints.maxWidth - _ScheduleGrid.leftWidth) / 5;
              final gridWidth =
                  _ScheduleGrid.leftWidth + weekdays.length * weekdayWidth;
              final grid = SingleChildScrollView(
                key: const PageStorageKey('academic-schedule-vertical-scroll'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: gridWidth,
                      child: _ScheduleGrid(
                        sessions: sessions,
                        weekdays: weekdays,
                        weekState: weekState,
                        displayedWeek: displayedWeek,
                        displaySettings: displaySettings,
                        courseColorValues: courseColorValues,
                        selectedManualSlot: selectedManualSlot,
                        canAddCourse: canAddCourse,
                        onEmptySlotTap: onEmptySlotTap,
                        onCourseTap: onCourseTap,
                      ),
                    ),
                    if (untimed.isNotEmpty)
                      _UntimedCourseList(courses: untimed),
                    const SizedBox(height: 24),
                  ],
                ),
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: gridWidth, child: grid),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekSwitcher extends StatefulWidget {
  const _WeekSwitcher({
    required this.week,
    required this.isVacation,
    required this.maxWeek,
    required this.onPrevious,
    required this.onNext,
    required this.onQuickWeekSelected,
  });

  final int week;
  final bool isVacation;
  final int maxWeek;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onQuickWeekSelected;

  @override
  State<_WeekSwitcher> createState() => _WeekSwitcherState();
}

class _WeekSwitcherState extends State<_WeekSwitcher> {
  bool _fastSwitching = false;
  int _previewWeek = 1;
  double _dragStartDx = 0;
  int _dragStartWeek = 1;
  double _dragWidth = 1;
  double _scheduleAreaTop = 0;
  OverlayEntry? _previewOverlay;

  @override
  void initState() {
    super.initState();
    _previewWeek = widget.week.clamp(1, widget.maxWeek);
  }

  @override
  void didUpdateWidget(covariant _WeekSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_fastSwitching &&
        (oldWidget.week != widget.week ||
            oldWidget.maxWeek != widget.maxWeek)) {
      _previewWeek = widget.week.clamp(1, widget.maxWeek);
    }
  }

  @override
  void dispose() {
    _removePreviewOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一周',
            onPressed: _fastSwitching ? null : widget.onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: widget.maxWeek > 1
                      ? (details) => _beginFastSwitch(
                            details,
                            constraints.maxWidth,
                          )
                      : null,
                  onHorizontalDragUpdate:
                      widget.maxWeek > 1 ? _updateFastSwitch : null,
                  onHorizontalDragEnd:
                      widget.maxWeek > 1 ? _finishFastSwitch : null,
                  onHorizontalDragCancel:
                      widget.maxWeek > 1 ? _cancelFastSwitch : null,
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 120),
                        child: _fastSwitching
                            ? SizedBox(
                                key: const ValueKey('quick-week-scrubber'),
                                width: constraints.maxWidth.clamp(120.0, 190.0),
                                child: _WeekScrubber(
                                  week: _previewWeek,
                                  maxWeek: widget.maxWeek,
                                ),
                              )
                            : Text(
                                widget.isVacation
                                    ? '假期中'
                                    : '第 ${widget.week} 周',
                                key: const ValueKey('week-title'),
                                textAlign: TextAlign.center,
                                style: ShuYoTextStyles.title(
                                  size: 16.5,
                                  weight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: _fastSwitching ? null : widget.onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  void _beginFastSwitch(DragStartDetails details, double width) {
    setState(() {
      _fastSwitching = true;
      _previewWeek = widget.week.clamp(1, widget.maxWeek);
      _dragStartWeek = _previewWeek;
      _dragStartDx = details.localPosition.dx;
      _dragWidth = width;
    });
    _showPreviewOverlay();
  }

  void _updateFastSwitch(DragUpdateDetails details) {
    if (!_fastSwitching) return;
    final range = widget.maxWeek - 1;
    if (range <= 0) return;
    final pixelsPerWeek = (_dragWidth / (range * 2)).clamp(6.0, 18.0);
    final offset =
        ((details.localPosition.dx - _dragStartDx) / pixelsPerWeek).round();
    final week = (_dragStartWeek + offset).clamp(1, widget.maxWeek);
    if (week != _previewWeek) {
      setState(() => _previewWeek = week);
      _previewOverlay?.markNeedsBuild();
    }
  }

  void _finishFastSwitch(DragEndDetails details) {
    if (!_fastSwitching) return;
    final week = _previewWeek;
    _removePreviewOverlay();
    setState(() => _fastSwitching = false);
    widget.onQuickWeekSelected(week);
  }

  void _cancelFastSwitch() {
    if (!_fastSwitching) return;
    _removePreviewOverlay();
    setState(() => _fastSwitching = false);
  }

  void _showPreviewOverlay() {
    _removePreviewOverlay();
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox) {
      _scheduleAreaTop =
          renderObject.localToGlobal(Offset(0, renderObject.size.height)).dy;
    }
    _previewOverlay = OverlayEntry(
      builder: (context) {
        final colors = context.shuyoColors;
        return Positioned(
          top: _scheduleAreaTop,
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 21, vertical: 9),
                  decoration: BoxDecoration(
                    color: colors.inverseSurface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '第 $_previewWeek 周',
                    style: ShuYoTextStyles.meta(
                      color: colors.inverseOnSurface,
                      size: 16,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_previewOverlay!);
  }

  void _removePreviewOverlay() {
    _previewOverlay?.remove();
    _previewOverlay = null;
  }
}

class _WeekScrubber extends StatelessWidget {
  const _WeekScrubber({required this.week, required this.maxWeek});

  final int week;
  final int maxWeek;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final progress = maxWeek <= 1 ? 0.0 : (week - 1) / (maxWeek - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dotSize = 14.0;
          final dotLeft = (constraints.maxWidth - dotSize) * progress;
          return SizedBox(
            height: dotSize,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Positioned(
                  left: dotLeft,
                  child: Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colors.background.withValues(alpha: 0.28),
                          blurRadius: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ScheduleGrid extends StatelessWidget {
  const _ScheduleGrid({
    required this.sessions,
    required this.weekdays,
    required this.weekState,
    required this.displayedWeek,
    required this.displaySettings,
    required this.courseColorValues,
    required this.selectedManualSlot,
    required this.canAddCourse,
    required this.onEmptySlotTap,
    required this.onCourseTap,
  });

  static const leftWidth = 68.0;
  static const _headerHeight = 54.0;
  static const _rowHeight = 68.0;
  static const _sectionCount = 12;

  final List<CourseSession> sessions;
  final List<int> weekdays;
  final ScheduleWeekState weekState;
  final int displayedWeek;
  final AcademicScheduleDisplaySettings displaySettings;
  final Map<String, int> courseColorValues;
  final _ScheduleSlot? selectedManualSlot;
  final bool canAddCourse;
  final ValueChanged<_ScheduleSlot> onEmptySlotTap;
  final ValueChanged<CourseSession> onCourseTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = (constraints.maxWidth - leftWidth) / weekdays.length;
        final height = _headerHeight + _sectionCount * _rowHeight;
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              _GridBackground(
                sessions: sessions,
                weekdays: weekdays,
                dayWidth: dayWidth,
                leftWidth: leftWidth,
                headerHeight: _headerHeight,
                rowHeight: _rowHeight,
                sectionCount: _sectionCount,
                weekState: weekState,
                displayedWeek: displayedWeek,
                selectedManualSlot: selectedManualSlot,
                canAddCourse: canAddCourse,
                onEmptySlotTap: onEmptySlotTap,
              ),
              for (final session in sessions)
                if (weekdays.contains(session.weekday))
                  Positioned(
                    left: leftWidth +
                        weekdays.indexOf(session.weekday) * dayWidth +
                        _scheduleCourseInset,
                    top: _headerHeight +
                        (session.startSection - 1) * _rowHeight +
                        _scheduleCourseInset,
                    width: dayWidth - _scheduleCourseInset * 2,
                    height: (session.endSection - session.startSection + 1) *
                            _rowHeight -
                        _scheduleCourseInset * 2,
                    child: _CourseBlock(
                      session: session,
                      displaySettings: displaySettings,
                      courseColorValues: courseColorValues,
                      onTap: () => onCourseTap(session),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _GridBackground extends StatelessWidget {
  const _GridBackground({
    required this.sessions,
    required this.weekdays,
    required this.dayWidth,
    required this.leftWidth,
    required this.headerHeight,
    required this.rowHeight,
    required this.sectionCount,
    required this.weekState,
    required this.displayedWeek,
    required this.selectedManualSlot,
    required this.canAddCourse,
    required this.onEmptySlotTap,
  });

  final List<CourseSession> sessions;
  final List<int> weekdays;
  final double dayWidth;
  final double leftWidth;
  final double headerHeight;
  final double rowHeight;
  final int sectionCount;
  final ScheduleWeekState weekState;
  final int displayedWeek;
  final _ScheduleSlot? selectedManualSlot;
  final bool canAddCourse;
  final ValueChanged<_ScheduleSlot> onEmptySlotTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var index = 0; index < weekdays.length; index++)
          Positioned(
            left: leftWidth + index * dayWidth,
            top: 0,
            width: dayWidth,
            height: headerHeight,
            child: _DayHeader(
              weekday: weekdays[index],
              date: weekState.anchorMonday.add(
                Duration(
                  days: (displayedWeek - weekState.currentWeek) * 7 +
                      weekdays[index] -
                      1,
                ),
              ),
            ),
          ),
        for (var section = 1; section <= sectionCount; section++)
          Positioned(
            left: 0,
            right: 0,
            top: headerHeight + (section - 1) * rowHeight,
            height: rowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: leftWidth,
                  child: _SectionLabel(section: section),
                ),
                for (var index = 0; index < weekdays.length; index++)
                  SizedBox(
                    width: dayWidth,
                    child: _EmptyScheduleCell(
                      slot: _ScheduleSlot(
                        weekday: weekdays[index],
                        section: section,
                      ),
                      enabled: canAddCourse &&
                          !_hasCourseAt(weekdays[index], section),
                      selected: selectedManualSlot ==
                          _ScheduleSlot(
                            weekday: weekdays[index],
                            section: section,
                          ),
                      onTap: onEmptySlotTap,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  bool _hasCourseAt(int weekday, int section) {
    return sessions.any((session) {
      return session.weekday == weekday &&
          session.startSection <= section &&
          session.endSection >= section;
    });
  }
}

class _EmptyScheduleCell extends StatelessWidget {
  const _EmptyScheduleCell({
    required this.slot,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final _ScheduleSlot slot;
  final bool enabled;
  final bool selected;
  final ValueChanged<_ScheduleSlot> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Padding(
      padding: const EdgeInsets.all(_scheduleCellInset),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onTap(slot) : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.scheduleEmptyCell,
            borderRadius: BorderRadius.circular(_scheduleCellRadius),
          ),
          child: Center(
            child: AnimatedOpacity(
              opacity: selected && enabled ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Icon(
                Icons.add,
                size: 22,
                color: colors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.weekday, required this.date});

  final int weekday;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _weekdayName(weekday),
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${date.month}/${date.day}',
          style: TextStyle(color: colors.textMuted, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.section});

  final int section;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$section',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            AcademicScheduleRepository.sectionTimeText(section),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 9.5,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({
    required this.session,
    required this.displaySettings,
    required this.courseColorValues,
    required this.onTap,
  });

  final CourseSession session;
  final AcademicScheduleDisplaySettings displaySettings;
  final Map<String, int> courseColorValues;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final fillColor = displaySettings.colorful
        ? (courseColorValues[_courseColorSeed(session)] == null
            ? _courseColorForSession(context, session)
            : Color(courseColorValues[_courseColorSeed(session)]!))
        : colors.scheduleCourseFill;
    final courseTextColor = displaySettings.colorful
        ? const Color(0xFFFFFFFF)
        : colors.scheduleCourseText;
    final metaTextColor = displaySettings.colorful
        ? const Color(0xD9FFFFFF)
        : colors.scheduleCourseMetaText;
    return Material(
      color: fillColor,
      borderRadius: BorderRadius.circular(_scheduleCourseRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_scheduleCourseRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_scheduleCourseRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.courseName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: courseTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  height: 1.2,
                ),
              ),
              if (displaySettings.showTeacher &&
                  session.teacherName.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  session.teacherName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: metaTextColor,
                    fontSize: 10.5,
                  ),
                ),
              ],
              const Spacer(),
              if (session.location.isNotEmpty)
                Text(
                  session.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: metaTextColor,
                    fontSize: 10.5,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: colors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _UntimedCourseList extends StatelessWidget {
  const _UntimedCourseList({required this.courses});

  final List<UntimedCourse> courses;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final courseText = courses
        .map(_formatUntimedCourse)
        .where((text) => text.isNotEmpty)
        .join('；');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(
        '其它课程：$courseText；',
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 12.5,
          height: 1.45,
        ),
      ),
    );
  }

  String _formatUntimedCourse(UntimedCourse course) {
    final summary = course.summary.trim();
    if (summary.isNotEmpty) {
      return summary.replaceFirst(RegExp(r'[;；]\s*$'), '');
    }
    final details = [
      course.teacherName,
      course.weekText,
      course.campus,
    ].where((item) => item.trim().isNotEmpty).join('/');
    return '${course.courseName}$details'.replaceFirst(
      RegExp(r'[;；]\s*$'),
      '',
    );
  }
}

class _ScheduleErrorState extends StatelessWidget {
  const _ScheduleErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: '课表加载失败',
      message: message,
      action: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重试'),
      ),
    );
  }
}

String _weekdayName(int weekday) {
  return switch (weekday) {
    1 => '周一',
    2 => '周二',
    3 => '周三',
    4 => '周四',
    5 => '周五',
    6 => '周六',
    7 => '周日',
    _ => '',
  };
}

Color _courseColor(BuildContext context, String seed) {
  final colors = context.shuyoColors.schedulePalette;
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash + unit) & 0x7fffffff;
  }
  return colors[hash % colors.length];
}

Color _courseColorForSession(BuildContext context, CourseSession session) {
  return _courseColor(context, _courseColorSeed(session));
}

String _courseColorSeed(CourseSession session) {
  final code = session.courseCode.trim();
  if (!session.isManual && code.isNotEmpty) {
    return code;
  }
  return session.courseName.trim();
}
