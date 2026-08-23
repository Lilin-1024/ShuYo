import 'package:shared_preferences/shared_preferences.dart';

import 'academic_native_auth_service.dart';

class VerificationDeliveryService {
  VerificationDeliveryService({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const cooldown = Duration(seconds: 60);
  static const _lastMethodKey = 'auth.verification.last_method';
  static const _sentAtPrefix = 'auth.verification.sent_at.';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<AcademicVerificationMethod> preferredMethod(
    Iterable<AcademicVerificationMethod> available,
  ) async {
    final methods = available.toSet();
    if (methods.isEmpty) {
      throw StateError('No verification method is available');
    }
    final prefs = await _preferencesLoader();
    final last = _fromName(prefs.getString(_lastMethodKey));
    if (last != null && methods.length > 1) {
      final alternate = AcademicVerificationMethod.values.firstWhere(
        (method) => method != last && methods.contains(method),
        orElse: () => methods.first,
      );
      return alternate;
    }
    return methods.contains(AcademicVerificationMethod.wecom)
        ? AcademicVerificationMethod.wecom
        : methods.first;
  }

  Future<Duration> remainingCooldown(
    AcademicVerificationMethod method,
  ) async {
    final prefs = await _preferencesLoader();
    final sentAtMillis = prefs.getInt('$_sentAtPrefix${method.name}');
    if (sentAtMillis == null) return Duration.zero;
    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(sentAtMillis),
    );
    final remaining = cooldown - elapsed;
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  Future<void> markSent(AcademicVerificationMethod method) async {
    final prefs = await _preferencesLoader();
    await Future.wait([
      prefs.setString(_lastMethodKey, method.name),
      prefs.setInt(
        '$_sentAtPrefix${method.name}',
        DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
  }

  AcademicVerificationMethod? _fromName(String? value) => switch (value) {
        'wecom' => AcademicVerificationMethod.wecom,
        'sms' => AcademicVerificationMethod.sms,
        _ => null,
      };
}
