typedef JsonMap = Map<String, dynamic>;

int intValue(Object? value, [int fallback = 0]) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

String stringValue(Object? value, [String fallback = '']) {
  if (value == null) {
    return fallback;
  }
  return value.toString();
}

bool boolValue(Object? value, [bool fallback = false]) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

DateTime? dateValue(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
