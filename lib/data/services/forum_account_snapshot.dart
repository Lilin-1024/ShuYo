import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/forum_url_resolver.dart';
import '../models/common.dart';
import '../models/current_user.dart';
import '../models/user_profile.dart';

class ForumAccountSnapshot {
  const ForumAccountSnapshot({
    required this.session,
    required this.profile,
    required this.summary,
    required this.lastOnlineAt,
    required this.profileUpdatedAt,
    required this.summaryUpdatedAt,
    required this.activityCounts,
    required this.activityUpdatedAt,
  });

  final CurrentUserSession session;
  final UserProfile profile;
  final UserSummary? summary;
  final DateTime lastOnlineAt;
  final DateTime? profileUpdatedAt;
  final DateTime? summaryUpdatedAt;
  final JsonMap? activityCounts;
  final DateTime? activityUpdatedAt;

  factory ForumAccountSnapshot.fromJson(JsonMap json) {
    final sessionJson = json['session'];
    final profileJson = json['profile'];
    if (sessionJson is! JsonMap || profileJson is! JsonMap) {
      throw const FormatException('invalid forum account snapshot');
    }
    final summaryJson = json['summary'];
    final activity = json['activity_counts'];
    return ForumAccountSnapshot(
      session: CurrentUserSession.fromJson(sessionJson),
      profile: UserProfile.fromJson(profileJson),
      summary:
          summaryJson is JsonMap ? UserSummary.fromJson(summaryJson) : null,
      lastOnlineAt: dateValue(json['last_online_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      profileUpdatedAt: dateValue(json['profile_updated_at']),
      summaryUpdatedAt: dateValue(json['summary_updated_at']),
      activityCounts: activity is JsonMap ? activity : null,
      activityUpdatedAt: dateValue(json['activity_updated_at']),
    );
  }

  JsonMap toJson() {
    return {
      'version': 1,
      'user_id': session.user.id,
      'username': session.username,
      'session': session.toJson(),
      'profile': profile.toJson(),
      if (summary != null) 'summary': summary!.toJson(),
      'last_online_at': lastOnlineAt.toIso8601String(),
      if (profileUpdatedAt != null)
        'profile_updated_at': profileUpdatedAt!.toIso8601String(),
      if (summaryUpdatedAt != null)
        'summary_updated_at': summaryUpdatedAt!.toIso8601String(),
      if (activityCounts != null) 'activity_counts': activityCounts,
      if (activityUpdatedAt != null)
        'activity_updated_at': activityUpdatedAt!.toIso8601String(),
    };
  }
}

class ForumAccountSnapshotStore {
  const ForumAccountSnapshotStore({
    this.preferencesLoader = SharedPreferences.getInstance,
  });

  final Future<SharedPreferences> Function() preferencesLoader;

  String get _key => 'forum.account.snapshot.v1.${ForumUrlResolver.mode.name}';

  Future<ForumAccountSnapshot?> load() async {
    final preferences = await preferencesLoader();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is JsonMap ? ForumAccountSnapshot.fromJson(decoded) : null;
    } on Object {
      return null;
    }
  }

  Future<void> save(ForumAccountSnapshot snapshot) async {
    final preferences = await preferencesLoader();
    await preferences.setString(_key, jsonEncode(snapshot.toJson()));
  }

  Future<void> clear() async {
    final preferences = await preferencesLoader();
    await preferences.remove(_key);
  }
}
