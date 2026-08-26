import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/core/forum_url_resolver.dart';
import 'package:shuyo/data/models/current_user.dart';
import 'package:shuyo/data/models/discourse_user.dart';
import 'package:shuyo/data/models/user_profile.dart';
import 'package:shuyo/data/repositories/forum_repository.dart';
import 'package:shuyo/data/services/forum_account_snapshot.dart';
import 'package:shuyo/data/services/discourse_api_client.dart';
import 'package:shuyo/data/services/forum_auth_service.dart';
import 'package:shuyo/data/services/forum_image_cache.dart';
import 'package:shuyo/data/services/forum_persistent_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ForumUrlResolver.configure(useWebVpn: false);
  });

  test('account snapshot round trips the last local account', () async {
    SharedPreferences.setMockInitialValues({});
    final user = const DiscourseUser(
      id: 42,
      username: 'Lilin',
      avatarTemplate: '/user_avatar/lilin/{size}/x.png',
    );
    final session = CurrentUserSession(
      user: user,
      unreadNotifications: 3,
      allUnreadNotifications: 4,
      newPersonalMessages: 2,
      canCreateTopic: true,
    );
    final profile = UserProfile(user: user, bioRaw: 'hello');
    final summary = const UserSummary(
      likesGiven: 1,
      likesReceived: 2,
      topicsEntered: 3,
      postsReadCount: 4,
      daysVisited: 5,
      topicCount: 6,
      postCount: 7,
      timeReadSeconds: 8,
    );
    final store = const ForumAccountSnapshotStore();
    await store.save(
      ForumAccountSnapshot(
        session: session,
        profile: profile,
        summary: summary,
        lastOnlineAt: DateTime(2026, 8, 21),
        profileUpdatedAt: DateTime(2026, 8, 20),
        summaryUpdatedAt: DateTime(2026, 8, 21),
        activityCounts: const {'topics': 6, 'read': 3, 'bookmarks': 1},
        activityUpdatedAt: DateTime(2026, 8, 21),
      ),
    );

    final restored = await store.load();
    expect(restored?.session.username, 'Lilin');
    expect(restored?.session.user.id, 42);
    expect(restored?.profile.bioRaw, 'hello');
    expect(restored?.summary?.topicCount, 6);
    expect(restored?.activityCounts?['bookmarks'], 1);
  });

  test('expired topic feeds remain readable for offline startup', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = await ForumPersistentCache.open(username: 'Lilin');
    await cache.saveTopicFeed('all:latest', {
      'topic_list': {
        'topics': [
          {'id': 99, 'title': 'cached topic'},
        ],
      },
    });

    final preferences = await SharedPreferences.getInstance();
    final entryKey = preferences.getKeys().singleWhere(
          (key) => key.contains('.feed.'),
        );
    final oldValue = jsonDecode(preferences.getString(entryKey)!) as Map;
    oldValue['savedAt'] = DateTime(2020).toIso8601String();
    await preferences.setString(entryKey, jsonEncode(oldValue));

    final restored = await cache.loadTopicFeeds();
    expect(restored, contains('all:latest'));
    expect(
        (restored['all:latest']!['topic_list'] as Map)['topics'], isNotEmpty);
  });

  test('private cache namespaces are account-specific', () {
    expect(
      ForumImageCache.privateNamespaceFor('Lilin'),
      'private:lilin',
    );
    expect(
      ForumImageCache.privateNamespaceFor('Other'),
      isNot(ForumImageCache.privateNamespaceFor('Lilin')),
    );
  });

  test('offline force refresh fails while cached feed remains readable',
      () async {
    SharedPreferences.setMockInitialValues({});
    const user = DiscourseUser(
      id: 42,
      username: 'Lilin',
      avatarTemplate: '/user_avatar/lilin/{size}/x.png',
    );
    await const ForumAccountSnapshotStore().save(
      ForumAccountSnapshot(
        session: CurrentUserSession(
          user: user,
          unreadNotifications: 0,
          allUnreadNotifications: 0,
          newPersonalMessages: 0,
          canCreateTopic: false,
        ),
        profile: UserProfile(user: user),
        summary: null,
        lastOnlineAt: DateTime(2026, 8, 21),
        profileUpdatedAt: null,
        summaryUpdatedAt: null,
        activityCounts: null,
        activityUpdatedAt: null,
      ),
    );
    final cache = await ForumPersistentCache.open(username: 'Lilin');
    await cache.saveTopicFeed('all:latest', {
      'topic_list': {
        'topics': [
          {'id': 99, 'title': 'cached topic'},
        ],
      },
    });

    final fallback = await FixtureForumRepository.load();
    final repository = await OnlineForumRepository.restoreOffline(
      fallback: fallback,
      authService: _NoCookieForumAuthService(),
    );
    expect(repository, isNotNull);
    expect(
      (await repository!.fetchTopicFeed(const TopicFeedQuery())).single.id,
      99,
    );
    await expectLater(
      repository.fetchTopicFeed(
        const TopicFeedQuery(),
        forceRefresh: true,
      ),
      throwsA(isA<ForumOfflineCacheMissException>()),
    );
  });
}

class _NoCookieForumAuthService implements ForumAuthService {
  @override
  Future<String?> cookieHeader() async => null;

  @override
  Future<void> clearCachedCookies() async {}

  @override
  Future<void> clearCookies() async {}

  @override
  Future<bool> hasForumCookies() async => false;

  @override
  Future<void> persistLastCookieHeader() async {}

  @override
  Future<void> refreshFromWebView() async {}

  @override
  Future<void> updateFromSetCookieHeaders(
    Uri responseUri,
    Iterable<String> headerValues,
  ) async {}
}
