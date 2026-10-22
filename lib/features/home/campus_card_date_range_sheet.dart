import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../shared/shuyo_text_styles.dart';
import '../../shared/theme/shuyo_theme.dart';

Future<DateTimeRange?> showCampusCardDateRangeSheet(
  BuildContext context, {
  required DateTimeRange initialRange,
}) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.shuyoColors.surface,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => CampusCardDateRangeSheet(initialRange: initialRange),
  );
}

class CampusCardDateRangeSheet extends StatefulWidget {
  const CampusCardDateRangeSheet({super.key, required this.initialRange});

  final DateTimeRange initialRange;

  @override
  State<CampusCardDateRangeSheet> createState() =>
      _CampusCardDateRangeSheetState();
}

class _CampusCardDateRangeSheetState extends State<CampusCardDateRangeSheet> {
  late DateTime _start = DateUtils.dateOnly(widget.initialRange.start);
  late DateTime _end = DateUtils.dateOnly(widget.initialRange.end);
  final _today = DateUtils.dateOnly(DateTime.now());
  bool _selectingEnd = false;
  late DateTime _focusedDay = _start;

  void _selectDate(DateTime date) {
    setState(() {
      if (_selectingEnd) {
        _end = date;
      } else {
        _start = date;
        if (_end.isBefore(date)) _end = date;
        _selectingEnd = true;
      }
      _focusedDay = _selectingEnd ? _end : _start;
    });
  }

  void _activateEndpoint(bool end) {
    setState(() {
      _selectingEnd = end;
      _focusedDay = end ? _end : _start;
    });
  }

  Future<void> _jumpToMonth() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _focusedDay,
      firstDate: DateTime(1970),
      lastDate: _today,
      initialDatePickerMode: DatePickerMode.year,
      helpText: '跳转到月份',
      confirmText: '跳转',
    );
    if (date != null && mounted) setState(() => _focusedDay = date);
  }

  void _stepMonth(int step) {
    setState(() =>
        _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + step));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('消费记录日期',
                          style: ShuYoTextStyles.pageTitle(
                              color: colors.textPrimary)),
                    ),
                  ),
                  IconButton(
                    tooltip: '取消选择日期',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 21),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    LayoutBuilder(builder: (context, constraints) {
                      final fields = [
                        _dateField(
                          title: '开始日期',
                          date: _start,
                          selected: !_selectingEnd,
                          onTap: () => _activateEndpoint(false),
                        ),
                        _dateField(
                          title: '结束日期',
                          date: _end,
                          selected: _selectingEnd,
                          onTap: () => _activateEndpoint(true),
                        ),
                      ];
                      if (constraints.maxWidth <
                          260 *
                              MediaQuery.textScalerOf(context).scale(20) /
                              20) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            fields[0],
                            const SizedBox(height: 12),
                            fields[1]
                          ],
                        );
                      }
                      return Row(children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 12),
                        Expanded(child: fields[1]),
                      ]);
                    }),
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      label: '已选范围：${_fullDate(_start)}至${_fullDate(_end)}',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_fullDate(_start)} — ${_fullDate(_end)}',
                            style: ShuYoTextStyles.meta(
                                color: colors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _selectingEnd ? '选择结束日期' : '选择开始日期',
                            style: ShuYoTextStyles.meta(
                                color: colors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _calendar(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(context).pop(
                    DateTimeRange(start: _start, end: _end),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('查询消费记录'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fullDate(DateTime date) => '${date.year}年${date.month}月${date.day}日';

  bool _inRange(DateTime date) =>
      !DateUtils.dateOnly(date).isBefore(_start) &&
      !DateUtils.dateOnly(date).isAfter(_end);

  Widget _calendar() {
    final colors = context.shuyoColors;
    final month = DateTime(_focusedDay.year, _focusedDay.month);
    final lastMonth = DateTime(_today.year, _today.month);
    final textScaler = MediaQuery.textScalerOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _jumpToMonth,
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 4,
                    children: [
                      Text('${month.year}年${month.month}月',
                          style:
                              ShuYoTextStyles.title(color: colors.textPrimary)),
                      Icon(Icons.arrow_drop_down, color: colors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '上个月',
              onPressed:
                  month.isAfter(DateTime(1970)) ? () => _stepMonth(-1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: '下个月',
              onPressed: month.isBefore(lastMonth) ? () => _stepMonth(1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Keep seven day columns readable at the narrowest supported width;
        // the date fields and range summary retain the full system text size.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: TableCalendar<void>(
            firstDay: DateTime(1970),
            lastDay: _today,
            focusedDay: _focusedDay,
            currentDay: _today,
            locale: Localizations.localeOf(context).toString(),
            startingDayOfWeek: StartingDayOfWeek.monday,
            headerVisible: false,
            calendarFormat: CalendarFormat.month,
            availableGestures: AvailableGestures.horizontalSwipe,
            rangeSelectionMode: RangeSelectionMode.disabled,
            rangeStartDay: _start,
            rangeEndDay: _end,
            pageAnimationEnabled: !MediaQuery.disableAnimationsOf(context),
            rowHeight:
                52 + (textScaler.scale(15) - 15).clamp(0, double.infinity),
            daysOfWeekHeight: textScaler.scale(13) * 1.5 + 8,
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: ShuYoTextStyles.meta(color: colors.textTertiary),
              weekendStyle: ShuYoTextStyles.meta(color: colors.textTertiary),
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              cellMargin:
                  const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
              rangeHighlightColor: colors.accentSoft,
            ),
            enabledDayPredicate: (day) =>
                !_selectingEnd || !DateUtils.dateOnly(day).isBefore(_start),
            onDaySelected: (day, _) => _selectDate(DateUtils.dateOnly(day)),
            onPageChanged: (day) => setState(() => _focusedDay = day),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (_, day, __) => _calendarDay(day),
              todayBuilder: (_, day, __) => _calendarDay(day),
              disabledBuilder: (_, day, __) =>
                  _calendarDay(day, disabled: true),
              withinRangeBuilder: (_, day, __) => _calendarDay(day),
              rangeStartBuilder: (_, day, __) =>
                  _calendarDay(day, endpoint: true),
              rangeEndBuilder: (_, day, __) =>
                  _calendarDay(day, endpoint: true),
            ),
          ),
        ),
      ],
    );
  }

  Widget _calendarDay(DateTime date,
      {bool endpoint = false, bool disabled = false}) {
    final colors = context.shuyoColors;
    final day = DateUtils.dateOnly(date);
    final inRange = _inRange(day);
    final today = isSameDay(day, _today);
    final color = disabled
        ? colors.textMuted
        : endpoint
            ? colors.onAccent
            : inRange
                ? colors.onAccentSoft
                : today
                    ? colors.accent
                    : colors.textPrimary;
    return Padding(
      key: ValueKey<DateTime>(day),
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      child: InkWell(
        excludeFromSemantics: true,
        onTap: disabled ? null : () => _selectDate(day),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: endpoint ? colors.accent : null,
            borderRadius: BorderRadius.circular(12),
            border: today && !inRange ? Border.all(color: colors.accent) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${day.day}',
                  style: ShuYoTextStyles.body(
                      color: color,
                      size: 15,
                      weight: endpoint ? FontWeight.w600 : FontWeight.w400)),
              if (endpoint)
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(
                    isSameDay(_start, _end)
                        ? '起止'
                        : isSameDay(day, _start)
                            ? '开始'
                            : '结束',
                    style: ShuYoTextStyles.meta(color: color)
                        .copyWith(fontSize: 9),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateField({
    required String title,
    required DateTime date,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.shuyoColors;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title，${date.year}年${date.month}月${date.day}日',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.accentSoft : colors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? colors.accent : colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: ShuYoTextStyles.meta(
                        color: selected
                            ? colors.onAccentSoft
                            : colors.textTertiary)),
                const SizedBox(height: 6),
                Text(
                  '${date.month}月${date.day}日',
                  style: ShuYoTextStyles.title(
                    color: selected ? colors.onAccentSoft : colors.textPrimary,
                    size: 20,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text('${date.year}年',
                    style: ShuYoTextStyles.meta(
                        color: selected
                            ? colors.onAccentSoft
                            : colors.textTertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
