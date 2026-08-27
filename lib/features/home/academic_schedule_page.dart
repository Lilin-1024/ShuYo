import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/academic_schedule.dart';
import '../../data/repositories/academic_schedule_repository.dart';
import '../../data/services/academic_schedule_api_client.dart';
import '../../data/services/academic_schedule_notification_service.dart';
import '../../data/services/academic_schedule_widget_service.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/widgets/empty_state.dart';

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

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadCached();
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
            onPreviousWeek: _displayedWeek <= 1
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
            selectedManualSlot: _selectedManualSlot,
            canAddCourse: !schedule.isVacationWeek(_displayedWeek),
            onEmptySlotTap: _handleEmptySlotTap,
            onCourseTap: _handleCourseTap,
          );
        },
      ),
    );
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
    _showSnack('已将第${week}周设为当周');
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
    final draft = await showModalBottomSheet<_ManualCourseDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ManualCourseSheet(
          initialWeek: _displayedWeek,
          maxWeek: schedule.maxWeek,
          weekday: slot.weekday,
          initialStartSection: slot.section,
          submitLabel: '添加',
        );
      },
    );
    if (!mounted || draft == null) {
      return;
    }
    if (_hasScheduleConflict(schedule, draft, slot.weekday)) {
      _showSnack('所选时间已有课程');
      return;
    }
    final session = _courseSessionFromDraft(
      draft,
      weekday: slot.weekday,
    );
    final next = schedule.copyWith(
      sessions: [...schedule.sessions, session],
    );
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

  Future<void> _handleCourseTap(CourseSession session) async {
    final action = await showModalBottomSheet<_ManualCourseAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = context.lehuColors;
        final color = _courseColor(context, session.courseName);
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
        final confirmed = await _confirmDeleteCourseGroup(session);
        if (confirmed) {
          await _deleteCourseGroup(session);
        }
    }
  }

  Future<void> _openCourseEditSheet(CourseSession session) async {
    final schedule = _schedule;
    if (schedule == null) {
      return;
    }
    final draft = await showModalBottomSheet<_ManualCourseDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ManualCourseSheet(
          initialWeek: _displayedWeek,
          maxWeek: schedule.maxWeek,
          weekday: session.weekday,
          initialStartSection: session.startSection,
          initialCourse: session,
          submitLabel: '保存',
        );
      },
    );
    if (!mounted || draft == null) {
      return;
    }
    if (_hasScheduleConflict(
      schedule,
      draft,
      session.weekday,
      excluding: session,
    )) {
      _showSnack('所选时间已有课程');
      return;
    }
    final updated = _courseSessionFromDraft(
      draft,
      weekday: session.weekday,
      base: session,
    );
    final nextSessions = [
      for (final item in schedule.sessions)
        if (_sameCourseIdentity(item, session)) updated else item,
    ];
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

  Future<void> _deleteCourseGroup(CourseSession target) async {
    final schedule = _schedule;
    if (schedule == null) {
      return;
    }
    final nextSessions = schedule.sessions
        .where((session) => !_sameCourseSlotGroup(session, target))
        .toList();
    if (nextSessions.length == schedule.sessions.length) {
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

  Future<bool> _confirmDeleteCourseGroup(CourseSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = context.lehuColors;
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text(
            '将删除 ${session.courseName}，同节次的课程将会一起删除。',
          ),
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

  bool _hasScheduleConflict(
    AcademicSchedule schedule,
    _ManualCourseDraft draft,
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

  Future<void> _openMoreMenu() async {
    final action = await showModalBottomSheet<_ScheduleMenuAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
        final colors = context.lehuColors;
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
    }
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
}

enum _ManualCourseAction {
  edit,
  delete,
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

CourseSession _courseSessionFromDraft(
  _ManualCourseDraft draft, {
  required int weekday,
  CourseSession? base,
}) {
  final sections = [
    for (var section = draft.startSection;
        section <= draft.endSection;
        section++)
      section,
  ];
  final weeks = [...draft.weeks]..sort();
  return CourseSession(
    id: base?.id ??
        '${CourseSession.manualIdPrefix}$weekday:'
            '${draft.startSection}-${draft.endSection}:'
            '${DateTime.now().microsecondsSinceEpoch}',
    courseName: draft.courseName,
    courseCode: base?.courseCode ?? CourseSession.manualCode,
    teacherName: base?.teacherName ?? '',
    campus: base?.campus ?? '',
    location: draft.location,
    weekday: weekday,
    startSection: draft.startSection,
    endSection: draft.endSection,
    sections: sections,
    weeks: weeks,
    weekText: _formatWeekText(weeks),
    credit: base?.credit ?? '',
    note: base?.note ?? '',
  );
}

bool _sameCourseIdentity(CourseSession session, CourseSession target) {
  return session.id == target.id &&
      session.weekday == target.weekday &&
      session.startSection == target.startSection &&
      session.endSection == target.endSection;
}

bool _sameCourseSlotGroup(CourseSession session, CourseSession target) {
  return session.weekday == target.weekday &&
      session.startSection == target.startSection &&
      session.endSection == target.endSection;
}

bool _sectionRangesOverlap(
  int startA,
  int endA,
  int startB,
  int endB,
) {
  return startA <= endB && startB <= endA;
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
    final colors = context.lehuColors;
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

class _ManualCourseSheet extends StatefulWidget {
  const _ManualCourseSheet({
    required this.initialWeek,
    required this.maxWeek,
    required this.weekday,
    required this.initialStartSection,
    required this.submitLabel,
    this.initialCourse,
  });

  final int initialWeek;
  final int maxWeek;
  final int weekday;
  final int initialStartSection;
  final String submitLabel;
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

  @override
  void initState() {
    super.initState();
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
    _courseNameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom > 0
        ? mediaQuery.viewInsets.bottom
        : mediaQuery.viewPadding.bottom;
    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: mediaQuery.size.height * 0.88,
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
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                            setState(() => _endSection = value);
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
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.selectedManualSlot,
    required this.canAddCourse,
    required this.onEmptySlotTap,
    required this.onCourseTap,
  });

  final AcademicSchedule schedule;
  final ScheduleWeekState weekState;
  final int displayedWeek;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;
  final _ScheduleSlot? selectedManualSlot;
  final bool canAddCourse;
  final ValueChanged<_ScheduleSlot> onEmptySlotTap;
  final ValueChanged<CourseSession> onCourseTap;

  @override
  Widget build(BuildContext context) {
    final sessions = schedule.sessionsForWeek(displayedWeek);
    final untimed = schedule.untimedForWeek(displayedWeek);
    final weekdays = _visibleWeekdays(sessions);

    return Column(
      children: [
        _WeekSwitcher(
          week: displayedWeek,
          isVacation: schedule.isVacationWeek(displayedWeek),
          onPrevious: onPreviousWeek,
          onNext: onNextWeek,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final needsHorizontalScroll = weekdays.length > 5;
              final weekdayWidth =
                  (constraints.maxWidth - _ScheduleGrid.leftWidth) / 5;
              final gridWidth = needsHorizontalScroll
                  ? _ScheduleGrid.leftWidth + weekdays.length * weekdayWidth
                  : constraints.maxWidth;
              final grid = SingleChildScrollView(
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
              if (!needsHorizontalScroll) {
                return grid;
              }
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

  List<int> _visibleWeekdays(List<CourseSession> sessions) {
    final hasWeekend = sessions.any((session) => session.weekday >= 6);
    return hasWeekend ? const [1, 2, 3, 4, 5, 6, 7] : const [1, 2, 3, 4, 5];
  }
}

class _WeekSwitcher extends StatelessWidget {
  const _WeekSwitcher({
    required this.week,
    required this.isVacation,
    required this.onPrevious,
    required this.onNext,
  });

  final int week;
  final bool isVacation;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一周',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              isVacation ? '假期中' : '第 $week 周',
              textAlign: TextAlign.center,
              style: LehuTextStyles.title(
                size: 16.5,
                weight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
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
    final colors = context.lehuColors;
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
    final colors = context.lehuColors;
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
    final colors = context.lehuColors;
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
    required this.onTap,
  });

  final CourseSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Material(
      color: colors.scheduleCourseFill,
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
                  color: colors.scheduleCourseText,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  height: 1.2,
                ),
              ),
              const Spacer(),
              if (session.location.isNotEmpty)
                Text(
                  session.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.scheduleCourseMetaText,
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
    final colors = context.lehuColors;
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
    final colors = context.lehuColors;
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
  final colors = context.lehuColors.schedulePalette;
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash + unit) & 0x7fffffff;
  }
  return colors[hash % colors.length];
}
