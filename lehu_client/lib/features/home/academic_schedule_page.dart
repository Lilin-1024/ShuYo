import 'package:flutter/material.dart';

import '../../data/models/academic_schedule.dart';
import '../../data/repositories/academic_schedule_repository.dart';
import '../../data/services/academic_schedule_api_client.dart';
import '../../data/services/academic_schedule_notification_service.dart';
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
    required this.onLoginRequired,
  });

  final AcademicScheduleRepository repository;
  final AcademicScheduleNotificationService notificationService;
  final Future<void> Function() onLoginRequired;

  @override
  State<AcademicSchedulePage> createState() => _AcademicSchedulePageState();
}

class _AcademicSchedulePageState extends State<AcademicSchedulePage> {
  late Future<void> _loadFuture;
  AcademicSchedule? _schedule;
  ScheduleWeekState? _weekState;
  int _displayedWeek = 1;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadCached();
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
            return const Center(child: CircularProgressIndicator());
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
                : () => setState(() => _displayedWeek--),
            onNextWeek: _displayedWeek >= schedule.maxWeek
                ? null
                : () => setState(() => _displayedWeek++),
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
    });
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
      });
      await widget.notificationService.syncScheduleReminders();
      _showSnack('课表已同步');
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
    _showSnack('登录完成后请再次点击刷新');
  }

  Future<void> _setDisplayedWeekAsCurrent() async {
    await widget.repository.setCurrentWeek(_displayedWeek);
    final weekState = await widget.repository.loadWeekState();
    if (!mounted) {
      return;
    }
    setState(() => _weekState = weekState);
    await widget.notificationService.syncScheduleReminders();
    _showSnack('已设为当前周');
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
      _showSnack('系统通知权限未开启，课程提醒已关闭');
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
}

enum _ScheduleMenuAction {
  refreshSchedule,
  settings,
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

class _ScheduleBody extends StatelessWidget {
  const _ScheduleBody({
    required this.schedule,
    required this.weekState,
    required this.displayedWeek,
    required this.onPreviousWeek,
    required this.onNextWeek,
  });

  final AcademicSchedule schedule;
  final ScheduleWeekState weekState;
  final int displayedWeek;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;

  @override
  Widget build(BuildContext context) {
    final sessions = schedule.sessionsForWeek(displayedWeek);
    final untimed = schedule.untimedForWeek(displayedWeek);
    final weekdays = _visibleWeekdays(sessions);

    return Column(
      children: [
        _WeekSwitcher(
          week: displayedWeek,
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
    required this.onPrevious,
    required this.onNext,
  });

  final int week;
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
              '第 $week 周',
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
  });

  static const leftWidth = 68.0;
  static const _headerHeight = 54.0;
  static const _rowHeight = 68.0;
  static const _sectionCount = 12;

  final List<CourseSession> sessions;
  final List<int> weekdays;
  final ScheduleWeekState weekState;
  final int displayedWeek;

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
                weekdays: weekdays,
                dayWidth: dayWidth,
                leftWidth: leftWidth,
                headerHeight: _headerHeight,
                rowHeight: _rowHeight,
                sectionCount: _sectionCount,
                weekState: weekState,
                displayedWeek: displayedWeek,
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
                    child: _CourseBlock(session: session),
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
    required this.weekdays,
    required this.dayWidth,
    required this.leftWidth,
    required this.headerHeight,
    required this.rowHeight,
    required this.sectionCount,
    required this.weekState,
    required this.displayedWeek,
  });

  final List<int> weekdays;
  final double dayWidth;
  final double leftWidth;
  final double headerHeight;
  final double rowHeight;
  final int sectionCount;
  final ScheduleWeekState weekState;
  final int displayedWeek;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
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
                    child: Padding(
                      padding: const EdgeInsets.all(_scheduleCellInset),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.scheduleEmptyCell,
                          borderRadius:
                              BorderRadius.circular(_scheduleCellRadius),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
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
  const _CourseBlock({required this.session});

  final CourseSession session;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final color = _courseColor(context, session.courseName);
    return Material(
      color: colors.scheduleCourseFill,
      borderRadius: BorderRadius.circular(_scheduleCourseRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_scheduleCourseRadius),
        onTap: () => _showCourseSheet(context, session, color),
        child: Container(
          padding: const EdgeInsets.all(7),
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

  void _showCourseSheet(
    BuildContext context,
    CourseSession session,
    Color color,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = context.lehuColors;
        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
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
                _DetailLine(Icons.schedule,
                    '${session.sectionText} ${session.weekText}'),
                if (session.placeText.isNotEmpty)
                  _DetailLine(Icons.place_outlined, session.placeText),
                if (session.teacherName.isNotEmpty)
                  _DetailLine(Icons.person_outline, session.teacherName),
                if (session.credit.isNotEmpty)
                  _DetailLine(Icons.school_outlined, '${session.credit} 学分'),
              ],
            ),
          ),
        );
      },
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
