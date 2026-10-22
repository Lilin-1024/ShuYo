import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'client_backend_api_client.dart';
import 'schedule_share_service.dart';
import 'student_identity_service.dart';

/// Keeps the last successful lookup, including an absent share code, across
/// visits. Local identity changes invalidate both memory and persisted data.
class ScheduleShareCache extends ChangeNotifier {
  ScheduleShareCache({
    required StudentIdentityService identityService,
    Future<SharedPreferences> Function()? preferencesLoader,
    DateTime Function()? now,
  })  : _identity = identityService,
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _now = now ?? DateTime.now {
    _identity.addListener(_identityChanged);
  }

  static final _instances = Expando<ScheduleShareCache>();
  static const _key = 'academic.schedule.share.current.v1';
  static const freshness = Duration(minutes: 5);

  static ScheduleShareCache forIdentity(StudentIdentityService identity) =>
      _instances[identity] ??= ScheduleShareCache(identityService: identity);

  final StudentIdentityService _identity;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final DateTime Function() _now;
  StudentIdentitySession? _session;
  ShareCodeInfo? _code;
  DateTime? _checkedAt;
  bool _loaded = false;
  int _revision = 0;
  Future<void>? _refreshTask;
  Future<void> _writes = Future<void>.value();

  ShareCodeInfo? get code {
    final now = _now();
    if (_session == null ||
        !now.isBefore(_session!.expiresAt) ||
        _code == null ||
        !now.isBefore(_code!.expiresAt)) {
      return null;
    }
    return _code;
  }

  DateTime? get validUntil {
    final current = code;
    if (current == null) return null;
    return current.expiresAt.isBefore(_session!.expiresAt)
        ? current.expiresAt
        : _session!.expiresAt;
  }

  bool get _isFresh {
    final checkedAt = _checkedAt;
    if (checkedAt == null) return false;
    final age = _now().difference(checkedAt);
    return !age.isNegative &&
        age < freshness &&
        (_code == null || code != null);
  }

  Future<void> refresh(ScheduleShareApi api, {bool force = false}) {
    final pending = _refreshTask;
    if (pending != null) return pending;
    late final Future<void> task;
    task = _refresh(api, force: force).whenComplete(() {
      if (identical(_refreshTask, task)) _refreshTask = null;
    });
    _refreshTask = task;
    return task;
  }

  Future<void> _refresh(ScheduleShareApi api, {required bool force}) async {
    var revision = _revision;
    try {
      final session = await _identity.loadLocalSession();
      if (revision != _revision) return;
      if (session == null) {
        clear();
        return;
      }
      final changedSession =
          _session != null && _session!.token != session.token;
      if (changedSession) {
        revision = ++_revision;
        _code = null;
        _checkedAt = null;
        _loaded = false;
      }
      _session = session;
      if (!_loaded) {
        await _loadPersisted(session, revision);
        if (revision != _revision) return;
        notifyListeners();
      }
      if (!force && !changedSession && _isFresh) return;

      final verified = await _identity.checkCurrentSession();
      if (revision != _revision) return;
      if (verified == null || verified.token != session.token) {
        clear();
        return;
      }
      final current = await api.current(session.token);
      if (revision != _revision) return;
      final latest = await _identity.loadLocalSession();
      if (revision != _revision) return;
      if (latest == null || latest.token != session.token) {
        clear();
        return;
      }
      await _commit(latest, current);
    } on ClientBackendApiException catch (error) {
      if (revision == _revision && error.statusCode == 401) clear();
    } on Object {
      // A failed background check must not erase a still-valid cached code.
    }
  }

  Future<void> _loadPersisted(
      StudentIdentitySession session, int revision) async {
    try {
      await _writes;
      if (revision != _revision) return;
      final raw = (await _preferencesLoader()).getString(_key);
      if (revision != _revision || raw == null) return;
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['studentId'] != session.studentId) {
        return;
      }
      final checkedAt = DateTime.parse(value['checkedAt'] as String);
      final stored = value['code'];
      final current = stored == null
          ? null
          : ShareCodeInfo.fromJson(stored as Map<String, dynamic>);
      if (current != null &&
          (current.id.isEmpty ||
              !RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(current.code))) {
        return;
      }
      _code = current;
      _checkedAt = checkedAt;
    } on Object {
      // Ignore a damaged or unavailable cache and query the server instead.
    } finally {
      if (revision == _revision) _loaded = true;
    }
  }

  /// A mutation supersedes any lookup that began before it completed.
  Future<bool> replace(
      StudentIdentitySession session, ShareCodeInfo? current) async {
    final revision = ++_revision;
    _refreshTask = null;
    final latest = await _identity.loadLocalSession();
    if (revision != _revision || latest?.token != session.token) return false;
    await _commit(latest!, current);
    return true;
  }

  Future<void> _commit(
      StudentIdentitySession session, ShareCodeInfo? current) async {
    _revision++;
    _session = session;
    _code = current;
    _checkedAt = _now();
    _loaded = true;
    _persist(jsonEncode({
      'studentId': session.studentId,
      'checkedAt': _checkedAt!.toIso8601String(),
      'code': current?.toJson(),
    }));
    notifyListeners();
    await _writes;
  }

  void _identityChanged() {
    if (!_identity.isVerified) clear();
  }

  void clear() {
    _revision++;
    _refreshTask = null;
    _session = null;
    _code = null;
    _checkedAt = null;
    _loaded = false;
    _persist(null);
    notifyListeners();
  }

  void _persist(String? value) {
    // Serialize writes so a slow earlier lookup cannot restore a removed code.
    _writes = _writes.then((_) async {
      final prefs = await _preferencesLoader();
      if (value == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, value);
      }
    }).catchError((Object _) {
      // Memory remains usable if local persistence is unavailable.
    });
  }

  @override
  void dispose() {
    _revision++;
    _refreshTask = null;
    _identity.removeListener(_identityChanged);
    super.dispose();
  }
}
