String compactCount(int value) {
  if (value <= 0) {
    return '0';
  }
  if (value < 10000) {
    return '$value';
  }
  if (value >= 100000) {
    return '${value ~/ 10000}w+';
  }
  final compact = value / 10000;
  final text = compact.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}w';
}
