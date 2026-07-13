class TimeFormat {
  const TimeFormat._();

  static String compact(DateTime? value, {DateTime? now}) {
    if (value == null) {
      return '';
    }
    final local = value.toLocal();
    final current = (now ?? DateTime.now()).toLocal();
    final diff = current.difference(local);

    if (!diff.isNegative) {
      if (diff.inMinutes < 1) {
        return '刚刚';
      }
      if (diff.inHours < 1) {
        return '${diff.inMinutes}分钟前';
      }
    }

    final time = '${_two(local.hour)}:${_two(local.minute)}';
    if (_sameDate(local, current)) {
      return time;
    }
    final date = local.year == current.year
        ? '${local.month}/${local.day}'
        : '${local.year}/${local.month}/${local.day}';
    return '$date $time';
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _two(int value) => value.toString().padLeft(2, '0');
}
