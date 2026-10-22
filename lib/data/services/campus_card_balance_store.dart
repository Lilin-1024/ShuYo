import 'dart:convert';

import 'academic_account_store.dart';
import 'secure_app_store.dart';

/// Keeps only the last successful balance, scoped to its campus account.
class CampusCardBalanceStore {
  final _store = SecureAppStore();
  final _accounts = AcademicAccountStore();

  Future<({double balance, DateTime queriedAt})?> load(String studentId) async {
    final raw = await _store.read(SecureAppStore.campusCardBalanceKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> || data['studentId'] != studentId) {
        return null;
      }
      final balance = data['balance'];
      final queriedAt = DateTime.tryParse(data['queriedAt']?.toString() ?? '');
      if (balance is! num || !balance.isFinite || queriedAt == null) {
        return null;
      }
      return (balance: balance.toDouble(), queriedAt: queriedAt);
    } on FormatException {
      return null;
    }
  }

  Future<void> save({
    required String studentId,
    required double balance,
    required DateTime queriedAt,
  }) async {
    if (await _accounts.loadStudentId() != studentId) return;
    await _store.write(
      SecureAppStore.campusCardBalanceKey,
      jsonEncode({
        'studentId': studentId,
        'balance': balance,
        'queriedAt': queriedAt.toIso8601String(),
      }),
    );
    if (await _accounts.loadStudentId() != studentId) {
      final raw = await _store.read(SecureAppStore.campusCardBalanceKey);
      if (raw != null && (jsonDecode(raw) as Map)['studentId'] == studentId) {
        await _store.delete(SecureAppStore.campusCardBalanceKey);
      }
    }
  }
}
