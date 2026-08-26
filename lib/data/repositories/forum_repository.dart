import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/forum_constants.dart';
import '../../core/forum_url_resolver.dart';
import '../models/category.dart';
import '../models/common.dart';
import '../models/composer.dart';
import '../models/current_user.dart';
import '../models/discourse_user.dart';
import '../models/forum_activity.dart';
import '../models/forum_notification.dart';
import '../models/forum_poll.dart';
import '../models/forum_report.dart';
import '../models/forum_search.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../models/topic_detail.dart';
import '../models/user_profile.dart';
import '../services/discourse_api_client.dart';
import '../services/client_settings_service.dart';
import '../services/forum_auth_service.dart';
import '../services/forum_account_snapshot.dart';
import '../services/forum_image_cache.dart';
import '../services/html_text.dart';
import '../services/payload_factory.dart';
import '../services/forum_persistent_cache.dart';
import '../services/sha1_hash.dart';

class TopicFeedQuery {
  const TopicFeedQuery({
    this.categoryId,
    this.hot = false,
  });

  final int? categoryId;
  final bool hot;

  String get key => '${categoryId ?? 'all'}:${hot ? 'hot' : 'latest'}';
}

enum ForumConnectionState {
  firstUse,
  cachedOffline,
  reauthenticationRequired,
  online,
}

enum ForumRecoveryStatus {
  restored,
  requiresReauthentication,
  unavailable,
}

class ForumRecoveryResult {
  const ForumRecoveryResult({
    required this.status,
    required this.repository,
    this.error,
  });

  final ForumRecoveryStatus status;
  final ForumRepository repository;
  final Object? error;

  bool get isRestored => status == ForumRecoveryStatus.restored;
}

const _emptyUserSummary = UserSummary(
  likesGiven: 0,
  likesReceived: 0,
  topicsEntered: 0,
  postsReadCount: 0,
  daysVisited: 0,
  topicCount: 0,
  postCount: 0,
  timeReadSeconds: 0,
);

abstract class ForumRepository {
  ForumConnectionState get connectionState;
  bool get hasLocalAccount => connectionState != ForumConnectionState.firstUse;
  bool get isCacheOnly =>
      connectionState == ForumConnectionState.cachedOffline ||
      connectionState == ForumConnectionState.reauthenticationRequired;
  bool get isOnline;
  Map<int, DiscourseUser> get users;
  List<ForumCategory> get categories;
  UserProfile get profile;
  UserSummary get userSummary;
  bool get hasCachedUserSummary;
  bool get hasCachedActivityCounts;
  bool get hasCachedPrivateMessages;
  int get unreadNotificationCount;
  int get unreadPrivateMessageCount;
  bool get canCreateTopic;
  Future<void> refreshSession();
  void markConnectionUnavailable();
  void markAuthenticationRequired();

  ForumCategory? categoryById(int id);
  bool get canLoadMoreLatest;
  bool get canLoadMoreHot;
  bool canLoadMoreFeed(TopicFeedQuery query);
  Future<List<TopicListItem>> fetchTopicFeed(
    TopicFeedQuery query, {
    bool forceRefresh = false,
  });
  Future<List<TopicListItem>> loadMoreTopicFeed(TopicFeedQuery query);
  Future<List<TopicListItem>> fetchLatestTopics({bool forceRefresh = false});
  Future<List<TopicListItem>> fetchHotTopics({bool forceRefresh = false});
  Future<List<TopicListItem>> loadMoreLatestTopics();
  Future<List<TopicListItem>> loadMoreHotTopics();
  Future<ForumSearchResult> searchForum(
    String query, {
    ForumSearchMode mode = ForumSearchMode.posts,
    ForumSearchSort sort = ForumSearchSort.relevance,
  });
  Future<UserProfile> fetchUserProfile(
    String username, {
    bool forceRefresh = false,
  });
  Future<UserProfile> fetchCurrentUserProfile({
    bool forceRefresh = false,
  });
  Future<UserSummary> fetchUserSummary(
    String username, {
    bool forceRefresh = false,
  });
  Future<ForumActivityCounts> fetchActivityCounts({
    bool forceRefresh = false,
  });
  Future<List<ForumActivityItem>> fetchUserActivity(
    ForumActivityKind kind, {
    bool forceRefresh = false,
  });
  Future<List<ForumActivityItem>> fetchTopicsCreatedBy(
    String username, {
    bool forceRefresh = false,
  });
  Future<ForumBookmark?> findTopicBookmark(
    int topicId, {
    bool forceRefresh = false,
  });
  Future<TopicDetail?> fetchTopicDetail(
    int id, {
    bool forceRefresh = false,
    bool trackVisit = false,
  });
  TopicDetail? cachedTopicDetail(int id);
  Future<void> recordTopicTiming(
    int topicId, {
    required int postNumber,
    required int topicTimeMs,
  });
  Future<void> recordTopicTimings(
    int topicId, {
    required Map<int, int> postTimingsMs,
    required int topicTimeMs,
  });
  Future<TopicPreview> fetchTopicPreview(int id);
  Future<Post> createTopic(CreateTopicDraft draft);
  Future<UploadedImage> uploadImage(PickedImage image);
  Future<ProfileImageUpload> uploadProfileImage(
    PickedImage image,
    ProfileImageUploadType type,
  );
  Future<UserProfile> updateProfileSettings(ProfileSettingsDraft draft);
  Future<UserProfile> useSystemAvatar();
  Future<UserProfile> useCustomAvatar(int uploadId);
  Future<Post> createReply(ReplyDraft draft);
  Future<List<TopicListItem>> fetchPrivateMessages({bool forceRefresh = false});
  Future<Post> createPrivateMessage(PrivateMessageDraft draft);
  Future<List<ForumNotification>> fetchNotifications(
    NotificationFeedFilter filter, {
    bool forceRefresh = false,
  });
  Future<Post> likePost(int postId);
  Future<Post> unlikePost(int postId);
  Future<ForumPollVoteResult> votePoll({
    required int topicId,
    required int postId,
    required String pollName,
    required List<String> optionIds,
  });
  Future<ForumPoll> togglePollStatus({
    required int topicId,
    required int postId,
    required String pollName,
    required String status,
  });
  Future<Post> reportContent(ForumReportDraft draft);
  Future<ForumBookmark> bookmarkTopic(int topicId);
  Future<void> unbookmarkTopic(int bookmarkId);
  Future<void> deleteTopic(TopicListItem topic);
  Future<void> deletePost(Post post);
  Future<void> forgetPrivateMessage(int topicId);
  Future<void> clearLoginCookies();
  Future<void> clearLocalAccount();
  Future<int> forumCacheStorageSize();
  Future<int> clearForumCache();
}

class FixtureForumRepository implements ForumRepository {
  FixtureForumRepository._({
    required List<TopicListItem> latestTopics,
    required List<TopicListItem> hotTopics,
    required this.users,
    required this.profile,
    required this.userSummary,
    required Map<int, ForumCategory> categories,
    required Map<int, TopicDetail> topicDetails,
  })  : _latestTopics = latestTopics,
        _hotTopics = hotTopics,
        _categories = categories,
        _topicDetails = topicDetails;

  static Future<FixtureForumRepository> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final site = await _loadJson(assets, 'assets/fixtures/api/site.json');
    final latest =
        await _loadJson(assets, 'assets/fixtures/api/latest/latest.json');
    final hot = await _loadJson(assets, 'assets/fixtures/api/hot/hot.json');
    final profile =
        await _loadJson(assets, 'assets/fixtures/api/user/user-profile.json');
    final summary =
        await _loadJson(assets, 'assets/fixtures/api/user/user-summary.json');

    final details = <int, TopicDetail>{};
    for (final path in const [
      'assets/fixtures/api/topic/topic-normal.json',
      'assets/fixtures/api/topic/topic-image.json',
      'assets/fixtures/api/topic/topic-long.json',
    ]) {
      final detail = TopicDetail.fromJson(await _loadJson(assets, path));
      details[detail.id] = detail;
    }

    final users = <int, DiscourseUser>{};
    users.addAll(_parseUsers(latest));
    users.addAll(_parseUsers(hot));

    final currentProfile = UserProfile.fromJson(profile);
    users[currentProfile.id] = currentProfile.user;

    return FixtureForumRepository._(
      latestTopics: _parseTopics(latest),
      hotTopics: _parseTopics(hot),
      users: users,
      profile: currentProfile,
      userSummary: UserSummary.fromJson(summary),
      categories: _parseCategories(site),
      topicDetails: details,
    );
  }

  final List<TopicListItem> _latestTopics;
  final List<TopicListItem> _hotTopics;
  final Map<int, ForumCategory> _categories;
  final Map<int, TopicDetail> _topicDetails;

  @override
  final Map<int, DiscourseUser> users;

  @override
  List<ForumCategory> get categories => _sortedCategories(_categories);

  @override
  final UserProfile profile;

  @override
  final UserSummary userSummary;

  @override
  ForumConnectionState get connectionState => ForumConnectionState.firstUse;

  @override
  bool get hasLocalAccount => false;

  @override
  bool get isCacheOnly => false;

  @override
  bool get isOnline => false;

  @override
  bool get hasCachedUserSummary => false;

  @override
  bool get hasCachedActivityCounts => false;

  @override
  bool get hasCachedPrivateMessages => false;

  @override
  int get unreadNotificationCount => 0;

  @override
  int get unreadPrivateMessageCount => 0;

  @override
  bool get canCreateTopic => false;

  @override
  Future<void> refreshSession() async {}

  @override
  void markConnectionUnavailable() {}

  @override
  void markAuthenticationRequired() {}

  @override
  ForumCategory? categoryById(int id) => _categories[id];

  @override
  bool get canLoadMoreLatest => false;

  @override
  bool get canLoadMoreHot => false;

  @override
  bool canLoadMoreFeed(TopicFeedQuery query) => false;

  @override
  Future<List<TopicListItem>> fetchTopicFeed(
    TopicFeedQuery query, {
    bool forceRefresh = false,
  }) async {
    if (query.categoryId != null) {
      return _latestTopics
          .where((topic) => topic.categoryId == query.categoryId)
          .toList();
    }
    return query.hot ? _hotTopics : _latestTopics;
  }

  @override
  Future<List<TopicListItem>> loadMoreTopicFeed(TopicFeedQuery query) {
    return fetchTopicFeed(query);
  }

  @override
  Future<List<TopicListItem>> fetchLatestTopics({
    bool forceRefresh = false,
  }) async {
    return _latestTopics;
  }

  @override
  Future<List<TopicListItem>> fetchHotTopics(
      {bool forceRefresh = false}) async {
    return _hotTopics;
  }

  @override
  Future<List<TopicListItem>> loadMoreLatestTopics() async {
    return _latestTopics;
  }

  @override
  Future<List<TopicListItem>> loadMoreHotTopics() async {
    return _hotTopics;
  }

  @override
  Future<TopicDetail?> fetchTopicDetail(
    int id, {
    bool forceRefresh = false,
    bool trackVisit = false,
  }) async {
    return _topicDetails[id];
  }

  @override
  TopicDetail? cachedTopicDetail(int id) => _topicDetails[id];

  @override
  Future<void> recordTopicTiming(
    int topicId, {
    required int postNumber,
    required int topicTimeMs,
  }) async {}

  @override
  Future<void> recordTopicTimings(
    int topicId, {
    required Map<int, int> postTimingsMs,
    required int topicTimeMs,
  }) async {}

  @override
  Future<TopicPreview> fetchTopicPreview(int id) async {
    final first = _topicDetails[id]?.firstPost;
    if (first == null) {
      return const TopicPreview(
        text: '暂无摘要，打开后可加载主题详情',
        images: [],
      );
    }
    return HtmlText.topicPreview(first.cooked);
  }

  @override
  Future<ForumSearchResult> searchForum(
    String query, {
    ForumSearchMode mode = ForumSearchMode.posts,
    ForumSearchSort sort = ForumSearchSort.relevance,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const ForumSearchResult(posts: [], topics: [], users: []);
    }
    if (mode == ForumSearchMode.users) {
      final matches = users.values
          .where((user) => user.username.contains(normalized))
          .map((user) => SearchUserResult(user: user))
          .toList(growable: false);
      return ForumSearchResult(
          posts: const [], topics: const [], users: matches);
    }
    final topics = _latestTopics
        .where((topic) => topic.title.contains(normalized))
        .toList(growable: false);
    return ForumSearchResult(posts: const [], topics: topics, users: const []);
  }

  @override
  Future<UserProfile> fetchUserProfile(
    String username, {
    bool forceRefresh = false,
  }) async {
    if (username == profile.username) {
      return profile;
    }
    final match = users.values.where((user) => user.username == username);
    if (match.isNotEmpty) {
      return UserProfile(user: match.first);
    }
    return UserProfile(
      user: DiscourseUser(
        id: 0,
        username: username,
        avatarTemplate: '',
      ),
    );
  }

  @override
  Future<UserProfile> fetchCurrentUserProfile({
    bool forceRefresh = false,
  }) {
    return fetchUserProfile(profile.username, forceRefresh: forceRefresh);
  }

  @override
  Future<UserSummary> fetchUserSummary(
    String username, {
    bool forceRefresh = false,
  }) async {
    return username == profile.username
        ? userSummary
        : const UserSummary(
            likesGiven: 0,
            likesReceived: 0,
            topicsEntered: 0,
            postsReadCount: 0,
            daysVisited: 0,
            topicCount: 0,
            postCount: 0,
            timeReadSeconds: 0,
          );
  }

  @override
  Future<ForumActivityCounts> fetchActivityCounts({
    bool forceRefresh = false,
  }) async {
    return ForumActivityCounts(
      topics: userSummary.topicCount,
      read: userSummary.topicsEntered,
      bookmarks: 0,
    );
  }

  @override
  Future<List<ForumActivityItem>> fetchUserActivity(
    ForumActivityKind kind, {
    bool forceRefresh = false,
  }) async {
    final topics = switch (kind) {
      ForumActivityKind.topics => _latestTopics
          .where((topic) => topic.originalPosterId == profile.id)
          .toList(),
      ForumActivityKind.read => _latestTopics,
      ForumActivityKind.bookmarks => const <TopicListItem>[],
    };
    return topics.map(ForumActivityItem.fromTopic).toList(growable: false);
  }

  @override
  Future<List<ForumActivityItem>> fetchTopicsCreatedBy(
    String username, {
    bool forceRefresh = false,
  }) async {
    final normalized = username.toLowerCase();
    final userIds = users.values
        .where((user) => user.username.toLowerCase() == normalized)
        .map((user) => user.id)
        .toSet();
    if (userIds.isEmpty) {
      return const [];
    }
    return _latestTopics
        .where((topic) => userIds.contains(topic.originalPosterId))
        .map(ForumActivityItem.fromTopic)
        .toList(growable: false);
  }

  @override
  Future<ForumBookmark?> findTopicBookmark(
    int topicId, {
    bool forceRefresh = false,
  }) async {
    return null;
  }

  @override
  Future<Post> createTopic(CreateTopicDraft draft) {
    throw const ForumAuthException('请先登录后再发帖');
  }

  @override
  Future<UploadedImage> uploadImage(PickedImage image) {
    throw const ForumAuthException('请先登录后再上传图片');
  }

  @override
  Future<ProfileImageUpload> uploadProfileImage(
    PickedImage image,
    ProfileImageUploadType type,
  ) {
    throw const ForumAuthException('请先登录后再上传图片');
  }

  @override
  Future<UserProfile> updateProfileSettings(ProfileSettingsDraft draft) {
    throw const ForumAuthException('请先登录后再修改资料');
  }

  @override
  Future<UserProfile> useSystemAvatar() {
    throw const ForumAuthException('请先登录后再修改头像');
  }

  @override
  Future<UserProfile> useCustomAvatar(int uploadId) {
    throw const ForumAuthException('请先登录后再修改头像');
  }

  @override
  Future<Post> createReply(ReplyDraft draft) {
    throw const ForumAuthException('请先登录后再评论');
  }

  @override
  Future<List<TopicListItem>> fetchPrivateMessages({
    bool forceRefresh = false,
  }) async {
    return const [];
  }

  @override
  Future<Post> createPrivateMessage(PrivateMessageDraft draft) {
    throw const ForumAuthException('请先登录后再发私信');
  }

  @override
  Future<List<ForumNotification>> fetchNotifications(
    NotificationFeedFilter filter, {
    bool forceRefresh = false,
  }) async {
    return const [];
  }

  @override
  Future<Post> likePost(int postId) {
    throw const ForumAuthException('请先登录后再点赞');
  }

  @override
  Future<Post> unlikePost(int postId) {
    throw const ForumAuthException('请先登录后再取消点赞');
  }

  @override
  Future<ForumPollVoteResult> votePoll({
    required int topicId,
    required int postId,
    required String pollName,
    required List<String> optionIds,
  }) {
    throw const ForumAuthException('请先登录后再投票');
  }

  @override
  Future<ForumPoll> togglePollStatus({
    required int topicId,
    required int postId,
    required String pollName,
    required String status,
  }) {
    throw const ForumAuthException('请先登录后再管理投票');
  }

  @override
  Future<Post> reportContent(ForumReportDraft draft) {
    throw const ForumAuthException('请先登录后再举报');
  }

  @override
  Future<ForumBookmark> bookmarkTopic(int topicId) {
    throw const ForumAuthException('请先登录后再收藏');
  }

  @override
  Future<void> unbookmarkTopic(int bookmarkId) {
    throw const ForumAuthException('请先登录后再取消收藏');
  }

  @override
  Future<void> deleteTopic(TopicListItem topic) {
    throw const ForumAuthException('请先登录后再删除');
  }

  @override
  Future<void> deletePost(Post post) {
    throw const ForumAuthException('请先登录后再删除');
  }

  @override
  Future<void> forgetPrivateMessage(int topicId) async {}

  @override
  Future<void> clearLoginCookies() async {}

  @override
  Future<void> clearLocalAccount() async {}

  @override
  Future<int> forumCacheStorageSize() async => 0;

  @override
  Future<int> clearForumCache() async => 0;

  static Future<JsonMap> _loadJson(AssetBundle bundle, String path) async {
    return jsonDecode(await bundle.loadString(path)) as JsonMap;
  }

  static Map<int, DiscourseUser> _parseUsers(JsonMap json) {
    final raw = json['users'];
    if (raw is! List) {
      return {};
    }
    return {
      for (final user in raw.whereType<JsonMap>().map(DiscourseUser.fromJson))
        user.id: user,
    };
  }

  static List<TopicListItem> _parseTopics(JsonMap json) {
    final list = json['topic_list'];
    final topics = list is JsonMap ? list['topics'] : null;
    if (topics is! List) {
      return const [];
    }
    return topics.whereType<JsonMap>().map(TopicListItem.fromJson).toList();
  }

  static Map<int, ForumCategory> _parseCategories(JsonMap json) {
    final list = json['category_list'];
    final categories =
        list is JsonMap ? list['categories'] : json['categories'];
    if (categories is! List) {
      return {};
    }
    return {
      for (final category
          in categories.whereType<JsonMap>().map(ForumCategory.fromJson))
        category.id: category,
    };
  }
}

class OnlineForumRepository implements ForumRepository {
  OnlineForumRepository._({
    required DiscourseApiClient apiClient,
    required ForumAuthService authService,
    required FixtureForumRepository fallback,
    required CurrentUserSession session,
    required UserSummary userSummary,
    required bool hasCachedUserSummary,
    required UserProfile profile,
    required Map<int, ForumCategory> categories,
    required ForumPersistentCache persistentCache,
    required ForumAccountSnapshotStore snapshotStore,
    required ForumConnectionState connectionState,
    DateTime? profileUpdatedAt,
    DateTime? summaryUpdatedAt,
    JsonMap? activityCountsJson,
    DateTime? activityUpdatedAt,
  })  : _apiClient = apiClient,
        _authService = authService,
        _fallback = fallback,
        _session = session,
        _profile = profile,
        _userSummary = userSummary,
        _hasCachedUserSummary = hasCachedUserSummary,
        _categories = categories,
        _persistentCache = persistentCache,
        _snapshotStore = snapshotStore,
        _connectionState = connectionState,
        _profileUpdatedAt = profileUpdatedAt,
        _summaryUpdatedAt = summaryUpdatedAt,
        _activityUpdatedAt = activityUpdatedAt,
        users = Map<int, DiscourseUser>.of(fallback.users) {
    users[session.user.id] = session.user;
  }

  static Future<OnlineForumRepository> connect({
    required FixtureForumRepository fallback,
    ForumAuthService? authService,
  }) async {
    final auth = authService ?? ForumAuthService();
    if (!await auth.hasForumCookies()) {
      throw const ForumAuthException();
    }
    final apiClient = DiscourseApiClient(authService: auth);
    final session = await _fetchSession(apiClient);
    await auth.persistLastCookieHeader();
    final persistentCache = await ForumPersistentCache.open(
      username: session.profile.username,
    );
    final snapshotStore = const ForumAccountSnapshotStore();
    final repository = OnlineForumRepository._(
      apiClient: apiClient,
      authService: auth,
      fallback: fallback,
      session: session,
      userSummary: _emptyUserSummary,
      hasCachedUserSummary: false,
      profile: session.profile,
      categories: Map<int, ForumCategory>.of(fallback._categories),
      persistentCache: persistentCache,
      snapshotStore: snapshotStore,
      connectionState: ForumConnectionState.online,
    );
    await repository._restorePersistentCache();
    await repository._saveAccountSnapshot();
    unawaited(repository._warmOptionalStartupData());
    return repository;
  }

  static Future<OnlineForumRepository?> restoreOffline({
    required FixtureForumRepository fallback,
    ForumAuthService? authService,
  }) async {
    final snapshot = await const ForumAccountSnapshotStore().load();
    if (snapshot == null || snapshot.session.username.isEmpty) {
      return null;
    }
    final auth = authService ?? ForumAuthService();
    final persistentCache = await ForumPersistentCache.open(
      username: snapshot.session.username,
    );
    final repository = OnlineForumRepository._(
      apiClient: DiscourseApiClient(authService: auth),
      authService: auth,
      fallback: fallback,
      session: snapshot.session,
      userSummary: snapshot.summary ?? _emptyUserSummary,
      hasCachedUserSummary: snapshot.summary != null,
      profile: snapshot.profile,
      categories: Map<int, ForumCategory>.of(fallback._categories),
      persistentCache: persistentCache,
      snapshotStore: const ForumAccountSnapshotStore(),
      connectionState: ForumConnectionState.cachedOffline,
      profileUpdatedAt: snapshot.profileUpdatedAt,
      summaryUpdatedAt: snapshot.summaryUpdatedAt,
      activityCountsJson: snapshot.activityCounts,
      activityUpdatedAt: snapshot.activityUpdatedAt,
    );
    if (snapshot.activityCounts != null) {
      repository._activityCounts = _activityCountsFromJson(
        snapshot.activityCounts!,
      );
    }
    await repository._restorePersistentCache();
    return repository;
  }

  final DiscourseApiClient _apiClient;
  final ForumAuthService _authService;
  final FixtureForumRepository _fallback;
  final ForumPersistentCache _persistentCache;
  final ForumAccountSnapshotStore _snapshotStore;
  CurrentUserSession _session;
  UserProfile _profile;
  UserSummary _userSummary;
  bool _hasCachedUserSummary;
  ForumConnectionState _connectionState;
  DateTime? _profileUpdatedAt;
  DateTime? _summaryUpdatedAt;
  DateTime? _activityUpdatedAt;
  int _cacheGeneration = 0;
  final Map<int, ForumCategory> _categories;
  final Map<int, TopicDetail> _topicDetails = {};
  final Map<int, Future<TopicDetail?>> _pendingTopicDetails = {};
  final Set<int> _staleTopicDetailIds = {};
  final Set<int> _trackedTopicVisits = {};
  final Map<String, UserProfile> _userProfiles = {};
  final Map<String, Future<UserProfile>> _pendingUserProfiles = {};
  final Map<String, UserSummary> _userSummaries = {};
  final Map<String, Future<UserSummary>> _pendingUserSummaries = {};
  final Map<String, List<TopicListItem>> _feedTopics = {};
  final Map<String, String?> _feedMorePaths = {};
  final Map<ForumActivityKind, List<ForumActivityItem>> _activityItems = {};
  final Map<String, List<ForumActivityItem>> _createdTopicItems = {};
  final Map<NotificationFeedFilter, List<ForumNotification>> _notifications =
      {};
  ForumActivityCounts? _activityCounts;
  Future<ForumActivityCounts>? _pendingActivityCounts;
  List<TopicListItem>? _privateMessages;

  @override
  final Map<int, DiscourseUser> users;

  @override
  List<ForumCategory> get categories => _sortedCategories(_categories);

  @override
  ForumConnectionState get connectionState => _connectionState;

  @override
  bool get hasLocalAccount => _connectionState != ForumConnectionState.firstUse;

  @override
  bool get isCacheOnly =>
      _connectionState == ForumConnectionState.cachedOffline ||
      _connectionState == ForumConnectionState.reauthenticationRequired;

  @override
  bool get isOnline => _connectionState == ForumConnectionState.online;

  @override
  bool get hasCachedUserSummary => _hasCachedUserSummary;

  @override
  bool get hasCachedActivityCounts => _activityCounts != null;

  @override
  bool get hasCachedPrivateMessages => _privateMessages != null;

  @override
  UserProfile get profile => _profile;

  @override
  UserSummary get userSummary => _userSummary;

  @override
  int get unreadNotificationCount => _session.notificationBadgeCount;

  @override
  int get unreadPrivateMessageCount => _session.privateMessageBadgeCount;

  @override
  bool get canCreateTopic => _session.canCreateTopic;

  @override
  Future<void> refreshSession() async {
    final session = await _fetchSession(_apiClient);
    _session = session;
    _connectionState = ForumConnectionState.online;
    users[session.user.id] = session.user;
    await _authService.persistLastCookieHeader();
    await _saveAccountSnapshot();
  }

  @override
  void markConnectionUnavailable() {
    if (_connectionState == ForumConnectionState.online) {
      _connectionState = ForumConnectionState.cachedOffline;
    }
  }

  @override
  void markAuthenticationRequired() {
    if (_connectionState != ForumConnectionState.firstUse) {
      _connectionState = ForumConnectionState.reauthenticationRequired;
    }
  }

  @override
  Future<void> clearLoginCookies() => _authService.clearCookies();

  @override
  Future<void> clearLocalAccount() async {
    _cacheGeneration++;
    final imageCache = await ForumImageCache.shared();
    await imageCache.deletePrivateNamespace(profile.username);
    await _snapshotStore.clear();
    await _persistentCache.clearPrivateAccountData();
    _connectionState = ForumConnectionState.firstUse;
    _topicDetails.removeWhere((_, detail) => detail.isPrivateMessage);
    _privateMessages = null;
  }

  @override
  Future<int> forumCacheStorageSize() async {
    final structured = await _persistentCache.storageSize();
    final images = await (await ForumImageCache.shared()).storageSize;
    return structured + images;
  }

  @override
  Future<int> clearForumCache() async {
    _cacheGeneration++;
    final before = await forumCacheStorageSize();
    await _persistentCache.clear();
    final imageCache = await ForumImageCache.shared();
    await imageCache.clearAll();
    _feedTopics.clear();
    _feedMorePaths.clear();
    _topicDetails.clear();
    _pendingTopicDetails.clear();
    _privateMessages = null;
    _userProfiles.clear();
    _userSummaries.clear();
    users
      ..clear()
      ..[profile.id] = profile.user;
    _activityItems.clear();
    _createdTopicItems.clear();
    _activityCounts = null;
    _hasCachedUserSummary = false;
    _profile = UserProfile(user: _session.user);
    _profileUpdatedAt = null;
    _summaryUpdatedAt = null;
    _activityUpdatedAt = null;
    await _saveAccountSnapshot();
    return before;
  }

  Future<void> _warmOptionalStartupData() async {
    try {
      final categories = await _fetchCategories(_apiClient, _fallback);
      _categories
        ..clear()
        ..addAll(categories);
    } on Object {
      // 分类数据不应影响登录态恢复；失败时保留本地兜底分类。
    }
    try {
      await fetchUserSummary(profile.username);
    } on Object {
      // 资料统计稍后进入个人页时仍会刷新。
    }
    try {
      await fetchCurrentUserProfile();
    } on Object {
      // session 中的简略资料足够让客户端先进入在线状态。
    }
  }

  Future<void> _saveAccountSnapshot() async {
    if (profile.username.isEmpty) {
      return;
    }
    final generation = _cacheGeneration;
    final snapshot = ForumAccountSnapshot(
      session: _session,
      profile: _profile,
      summary: _hasCachedUserSummary ? _userSummary : null,
      lastOnlineAt: DateTime.now(),
      profileUpdatedAt: _profileUpdatedAt,
      summaryUpdatedAt: _summaryUpdatedAt,
      activityCounts: _activityCounts?.toJson(),
      activityUpdatedAt: _activityUpdatedAt,
    );
    if (generation == _cacheGeneration) {
      await _snapshotStore.save(snapshot);
    }
  }

  Future<void> _restorePersistentCache() async {
    final feeds = await _persistentCache.loadTopicFeeds();
    for (final entry in feeds.entries) {
      final json = entry.value;
      _mergeUsers(json);
      _feedTopics[entry.key] = FixtureForumRepository._parseTopics(json);
      _feedMorePaths[entry.key] = _parseMoreTopicsPath(json);
    }

    final privateJson = _persistentCache.loadPrivateMessages();
    if (privateJson != null) {
      _mergeUsers(privateJson);
      _privateMessages = _parsePrivateMessages(privateJson);
    }

    final details = await _persistentCache.loadTopicDetails();
    for (final entry in details.entries) {
      try {
        final detail = TopicDetail.fromJson(entry.value);
        if (detail.id > 0) {
          _topicDetails[entry.key] = detail;
        }
      } on Object {
        // 单条缓存损坏不影响其它缓存恢复。
      }
    }
  }

  @override
  ForumCategory? categoryById(int id) {
    return _categories[id] ?? _fallback.categoryById(id);
  }

  @override
  bool get canLoadMoreLatest => canLoadMoreFeed(const TopicFeedQuery());

  @override
  bool get canLoadMoreHot => canLoadMoreFeed(const TopicFeedQuery(hot: true));

  @override
  bool canLoadMoreFeed(TopicFeedQuery query) =>
      _feedMorePaths[query.key] != null;

  @override
  Future<List<TopicListItem>> fetchTopicFeed(
    TopicFeedQuery query, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _feedTopics[query.key] != null) {
      return _feedTopics[query.key]!;
    }
    if (!isOnline) {
      if (forceRefresh) {
        throw const ForumOfflineCacheMissException();
      }
      return _feedTopics[query.key] ?? const [];
    }
    final json = await _apiClient.getJson(_feedPath(query));
    _mergeUsers(json);
    _feedMorePaths[query.key] = _parseMoreTopicsPath(json);
    final topics = FixtureForumRepository._parseTopics(json);
    _feedTopics[query.key] = topics;
    await _persistentCache.saveTopicFeed(query.key, json);
    return topics;
  }

  @override
  Future<List<TopicListItem>> loadMoreTopicFeed(TopicFeedQuery query) async {
    return _loadMoreTopics(
      currentTopics: _feedTopics[query.key] ?? await fetchTopicFeed(query),
      morePath: _feedMorePaths[query.key],
      setState: (topics, morePath) {
        _feedTopics[query.key] = topics;
        _feedMorePaths[query.key] = morePath;
      },
    );
  }

  @override
  Future<List<TopicListItem>> fetchLatestTopics({
    bool forceRefresh = false,
  }) =>
      fetchTopicFeed(const TopicFeedQuery(), forceRefresh: forceRefresh);

  @override
  Future<List<TopicListItem>> fetchHotTopics({bool forceRefresh = false}) =>
      fetchTopicFeed(
        const TopicFeedQuery(hot: true),
        forceRefresh: forceRefresh,
      );

  @override
  Future<List<TopicListItem>> loadMoreLatestTopics() =>
      loadMoreTopicFeed(const TopicFeedQuery());

  @override
  Future<List<TopicListItem>> loadMoreHotTopics() =>
      loadMoreTopicFeed(const TopicFeedQuery(hot: true));

  @override
  Future<TopicDetail?> fetchTopicDetail(
    int id, {
    bool forceRefresh = false,
    bool trackVisit = false,
  }) {
    if (!isOnline) {
      if (forceRefresh) {
        return Future.error(const ForumOfflineCacheMissException());
      }
      return Future.value(_topicDetails[id]);
    }
    if (!forceRefresh) {
      final cached = _topicDetails[id];
      if (cached != null && !_staleTopicDetailIds.contains(id)) {
        if (trackVisit) {
          _trackTopicVisit(id);
        }
        return Future.value(cached);
      }
      final pending = _pendingTopicDetails[id];
      if (pending != null) {
        if (trackVisit) {
          _trackTopicVisit(id);
        }
        return pending;
      }
    }

    final future = _fetchTopicDetail(id, trackVisit: trackVisit);
    _pendingTopicDetails[id] = future;
    return future.whenComplete(() => _pendingTopicDetails.remove(id));
  }

  @override
  TopicDetail? cachedTopicDetail(int id) => _topicDetails[id];

  @override
  Future<TopicPreview> fetchTopicPreview(int id) async {
    final detail = await fetchTopicDetail(id);
    final first = detail?.firstPost;
    if (first == null) {
      return const TopicPreview(text: '暂无摘要', images: []);
    }
    return HtmlText.topicPreview(first.cooked);
  }

  @override
  Future<void> recordTopicTiming(
    int topicId, {
    required int postNumber,
    required int topicTimeMs,
  }) async {
    await recordTopicTimings(
      topicId,
      postTimingsMs: {postNumber: topicTimeMs},
      topicTimeMs: topicTimeMs,
    );
  }

  @override
  Future<void> recordTopicTimings(
    int topicId, {
    required Map<int, int> postTimingsMs,
    required int topicTimeMs,
  }) async {
    final payload = PayloadFactory.topicTiming(
      topicId: topicId,
      postNumber: postTimingsMs.keys.isEmpty ? 1 : postTimingsMs.keys.first,
      topicTimeMs: topicTimeMs,
      postTimingsMs: postTimingsMs,
    );
    await _apiClient.postForm('/topics/timings', payload.body);
  }

  @override
  Future<ForumSearchResult> searchForum(
    String query, {
    ForumSearchMode mode = ForumSearchMode.posts,
    ForumSearchSort sort = ForumSearchSort.relevance,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const ForumSearchResult(posts: [], topics: [], users: []);
    }
    if (mode == ForumSearchMode.users) {
      final encoded = Uri.encodeQueryComponent(normalized);
      final json = await _apiClient.getJson(
        '/u/search/users?term=$encoded&limit=20',
      );
      final result = ForumSearchResult.fromJson(json);
      for (final user in result.users) {
        users[user.id] = user.user;
      }
      return result;
    }
    final suffix = sort.querySuffix;
    final searchText = suffix.isEmpty ? normalized : '$normalized $suffix';
    final encoded = Uri.encodeQueryComponent(searchText);
    final json = await _apiClient.getJson('/search?q=$encoded&page=1');
    _mergeUsers(json);
    return ForumSearchResult.fromJson(json);
  }

  @override
  Future<UserProfile> fetchUserProfile(
    String username, {
    bool forceRefresh = false,
  }) {
    final key = username.toLowerCase();
    final pending = _pendingUserProfiles[key];
    if (pending != null) {
      return pending;
    }
    final future = _fetchUserProfile(key, forceRefresh: forceRefresh);
    _pendingUserProfiles[key] = future;
    return future.whenComplete(() => _pendingUserProfiles.remove(key));
  }

  Future<UserProfile> _fetchUserProfile(
    String key, {
    required bool forceRefresh,
  }) async {
    if (key == profile.username.toLowerCase() && !forceRefresh) {
      final updatedAt = _profileUpdatedAt;
      if (_profileUpdatedAt != null &&
          DateTime.now().difference(updatedAt!) < const Duration(days: 7)) {
        return _profile;
      }
    }
    if (!forceRefresh && _userProfiles[key] != null) {
      return _userProfiles[key]!;
    }
    if (!isOnline) {
      if (forceRefresh) {
        throw const ForumOfflineCacheMissException();
      }
      if (key == profile.username.toLowerCase()) {
        return _profile;
      }
      throw const ForumOfflineCacheMissException();
    }
    final json =
        await _apiClient.getJson('/u/${Uri.encodeComponent(key)}.json');
    final fetchedProfile = UserProfile.fromJson(json);
    return _storeProfile(fetchedProfile);
  }

  @override
  Future<UserProfile> fetchCurrentUserProfile({
    bool forceRefresh = false,
  }) {
    return fetchUserProfile(profile.username, forceRefresh: forceRefresh);
  }

  @override
  Future<UserSummary> fetchUserSummary(
    String username, {
    bool forceRefresh = false,
  }) {
    final key = username.toLowerCase();
    final pending = _pendingUserSummaries[key];
    if (pending != null) {
      return pending;
    }
    final future = _fetchUserSummary(key, forceRefresh: forceRefresh);
    _pendingUserSummaries[key] = future;
    return future.whenComplete(() => _pendingUserSummaries.remove(key));
  }

  Future<UserSummary> _fetchUserSummary(
    String key, {
    required bool forceRefresh,
  }) async {
    if (key == profile.username.toLowerCase() && !forceRefresh) {
      final updatedAt = _summaryUpdatedAt;
      if (_hasCachedUserSummary &&
          updatedAt != null &&
          DateTime.now().difference(updatedAt) < const Duration(hours: 6)) {
        return _userSummary;
      }
    }
    if (!forceRefresh && _userSummaries[key] != null) {
      return _userSummaries[key]!;
    }
    if (!isOnline) {
      if (forceRefresh) {
        throw const ForumOfflineCacheMissException();
      }
      if (key == profile.username.toLowerCase() && _hasCachedUserSummary) {
        return _userSummary;
      }
      throw const ForumOfflineCacheMissException();
    }
    final json = await _apiClient.getJson(
      '/u/${Uri.encodeComponent(key)}/summary.json',
    );
    final summary = UserSummary.fromJson(json);
    _userSummaries[key] = summary;
    if (key == profile.username.toLowerCase()) {
      _userSummary = summary;
      _hasCachedUserSummary = true;
      _summaryUpdatedAt = DateTime.now();
      await _saveAccountSnapshot();
    }
    return summary;
  }

  @override
  Future<ForumActivityCounts> fetchActivityCounts({
    bool forceRefresh = false,
  }) {
    final pending = _pendingActivityCounts;
    if (pending != null) {
      return pending;
    }
    final future = _fetchActivityCounts(forceRefresh: forceRefresh);
    _pendingActivityCounts = future;
    return future.whenComplete(() => _pendingActivityCounts = null);
  }

  Future<ForumActivityCounts> _fetchActivityCounts({
    required bool forceRefresh,
  }) async {
    if (!forceRefresh && _activityCounts != null) {
      return _activityCounts!;
    }
    if (!isOnline) {
      if (forceRefresh) {
        throw const ForumOfflineCacheMissException();
      }
      if (_activityCounts != null) {
        return _activityCounts!;
      }
      throw const ForumOfflineCacheMissException();
    }
    final summary = await fetchUserSummary(
      profile.username,
      forceRefresh: forceRefresh,
    );
    final bookmarks = await fetchUserActivity(
      ForumActivityKind.bookmarks,
      forceRefresh: forceRefresh,
    );
    final result = ForumActivityCounts(
      topics: summary.topicCount,
      read: summary.topicsEntered,
      bookmarks: bookmarks.length,
    );
    _activityUpdatedAt = DateTime.now();
    _activityCounts = result;
    await _saveAccountSnapshot();
    return result;
  }

  @override
  Future<List<ForumActivityItem>> fetchUserActivity(
    ForumActivityKind kind, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _activityItems[kind] != null) {
      return _activityItems[kind]!;
    }
    if (!isOnline) {
      if (forceRefresh) {
        throw const ForumOfflineCacheMissException();
      }
      return _activityItems[kind] ?? const [];
    }
    final json = await _apiClient.getJson(_activityPath(kind));
    _mergeUsers(json);
    final items = _parseActivityItems(kind, json);
    return _activityItems[kind] = items;
  }

  @override
  Future<List<ForumActivityItem>> fetchTopicsCreatedBy(
    String username, {
    bool forceRefresh = false,
  }) async {
    final key = username.toLowerCase();
    if (!forceRefresh && _createdTopicItems[key] != null) {
      return _createdTopicItems[key]!;
    }
    if (!isOnline && forceRefresh) {
      throw const ForumOfflineCacheMissException();
    }
    final encoded = Uri.encodeComponent(key);
    final json = await _apiClient.getJson('/topics/created-by/$encoded.json');
    _mergeUsers(json);
    final items = _parseActivityItems(ForumActivityKind.topics, json);
    return _createdTopicItems[key] = items;
  }

  @override
  Future<ForumBookmark?> findTopicBookmark(
    int topicId, {
    bool forceRefresh = false,
  }) async {
    final bookmarks = await fetchUserActivity(
      ForumActivityKind.bookmarks,
      forceRefresh: forceRefresh,
    );
    for (final item in bookmarks) {
      final bookmarkId = item.bookmarkId;
      if (item.topicId == topicId && bookmarkId != null && bookmarkId > 0) {
        return ForumBookmark(id: bookmarkId, topicId: topicId);
      }
    }
    return null;
  }

  @override
  Future<Post> createTopic(CreateTopicDraft draft) async {
    final payload = PayloadFactory.createTopic(draft);
    final json =
        await _apiClient.postForm(ForumConstants.postsPath, payload.body);
    final postJson = json['post'];
    if (postJson is! JsonMap) {
      throw const ForumApiException('主题已提交，但返回内容无法解析');
    }
    final post = Post.fromJson(postJson);
    _topicDetails.remove(post.topicId);
    _staleTopicDetailIds.remove(post.topicId);
    await _persistentCache.removeTopicDetail(post.topicId);
    _feedTopics.clear();
    _feedMorePaths.clear();
    _activityItems.remove(ForumActivityKind.topics);
    _createdTopicItems.clear();
    _activityCounts = null;
    return post;
  }

  @override
  Future<UploadedImage> uploadImage(PickedImage image) async {
    final clientId = _uploadClientId();
    final json = await _apiClient.postMultipart(
      path: '/uploads.json?client_id=$clientId',
      fields: {
        'client_id': clientId,
        'upload_type': 'composer',
        'pasted': 'undefined',
        'name': image.filename,
        'type': image.mimeType,
        'sha1_checksum': Sha1Hash.hex(image.bytes),
      },
      fileField: 'file',
      fileBytes: image.bytes,
      filename: image.filename,
    );
    return UploadedImage(
      url: stringValue(json['url']),
      shortUrl: stringValue(json['short_url']),
      filename: stringValue(json['original_filename'], image.filename),
      width: intValue(json['width']),
      height: intValue(json['height']),
      thumbnailWidth: intValue(json['thumbnail_width']),
      thumbnailHeight: intValue(json['thumbnail_height']),
    );
  }

  @override
  Future<ProfileImageUpload> uploadProfileImage(
    PickedImage image,
    ProfileImageUploadType type,
  ) async {
    final clientId = _uploadClientId();
    final fields = <String, String>{
      'client_id': clientId,
      'upload_type': switch (type) {
        ProfileImageUploadType.avatar => 'avatar',
        ProfileImageUploadType.profileBackground => 'profile_background',
      },
      'pasted': 'undefined',
      'name': image.filename,
      'type': image.mimeType,
      'sha1_checksum': Sha1Hash.hex(image.bytes),
    };
    if (type == ProfileImageUploadType.avatar) {
      fields['user_id'] = '${profile.id}';
    }
    final json = await _apiClient.postMultipart(
      path: '/uploads.json?client_id=$clientId',
      fields: fields,
      fileField: 'file',
      fileBytes: image.bytes,
      filename: image.filename,
    );
    return ProfileImageUpload.fromJson(json);
  }

  @override
  Future<UserProfile> updateProfileSettings(ProfileSettingsDraft draft) async {
    final payload = PayloadFactory.updateProfileSettings(
      profile.username,
      draft,
    );
    final json = await _apiClient.putForm(
      '/u/${profile.username.toLowerCase()}.json',
      payload.body,
    );
    return _profileFromMutationResponse(json);
  }

  @override
  Future<UserProfile> useSystemAvatar() async {
    final payload = PayloadFactory.pickSystemAvatar(profile.username);
    await _apiClient.putForm(
      '/u/${profile.username.toLowerCase()}/preferences/avatar/pick',
      payload.body,
    );
    return fetchCurrentUserProfile(forceRefresh: true);
  }

  @override
  Future<UserProfile> useCustomAvatar(int uploadId) async {
    final payload = PayloadFactory.pickCustomAvatar(profile.username, uploadId);
    await _apiClient.putForm(
      '/u/${profile.username.toLowerCase()}/preferences/avatar/pick',
      payload.body,
    );
    return fetchCurrentUserProfile(forceRefresh: true);
  }

  @override
  Future<Post> createReply(ReplyDraft draft) async {
    final payload = PayloadFactory.createReply(draft);
    final json =
        await _apiClient.postForm(ForumConstants.postsPath, payload.body);
    final postJson = json['post'];
    if (postJson is! JsonMap) {
      throw const ForumApiException('评论已提交，但返回内容无法解析');
    }
    final post = Post.fromJson(postJson);
    final cached = _topicDetails[draft.topicId];
    if (cached == null) {
      _topicDetails.remove(draft.topicId);
      _staleTopicDetailIds.remove(draft.topicId);
    } else {
      _topicDetails[draft.topicId] = cached.mergedWithPosts([post]);
      _staleTopicDetailIds.remove(draft.topicId);
    }
    if (cached?.isPrivateMessage != true) {
      await _persistentCache.removeTopicDetail(draft.topicId);
    }
    _privateMessages = null;
    return post;
  }

  @override
  Future<List<TopicListItem>> fetchPrivateMessages({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _privateMessages != null) {
      return _privateMessages!;
    }
    final cachedJson = _persistentCache.loadPrivateMessages();
    if (!forceRefresh && cachedJson != null) {
      _mergeUsers(cachedJson);
      return _privateMessages = _parsePrivateMessages(cachedJson);
    }
    if (!isOnline) {
      if (forceRefresh) {
        throw const ForumOfflineCacheMissException();
      }
      return _privateMessages ?? const [];
    }
    final username = profile.username.toLowerCase();
    final responses = await Future.wait([
      _apiClient.getJson('/topics/private-messages/$username.json'),
      _apiClient.getJson('/topics/private-messages-sent/$username.json'),
    ]);
    final combinedJson = _mergePrivateMessageJsons([
      if (cachedJson != null) cachedJson,
      ...responses,
    ]);
    _mergeUsers(combinedJson);
    final messages = _parsePrivateMessages(combinedJson);
    await _persistentCache.savePrivateMessages(combinedJson);
    if (forceRefresh) {
      for (final message in messages) {
        _pendingTopicDetails.remove(message.id);
        if (_shouldInvalidatePrivateMessageDetail(message)) {
          _staleTopicDetailIds.add(message.id);
        }
      }
    }
    return _privateMessages = messages;
  }

  List<TopicListItem> _parsePrivateMessages(JsonMap json) {
    final messages = FixtureForumRepository._parseTopics(json).toList()
      ..sort((a, b) => _topicActivityTime(b).compareTo(_topicActivityTime(a)));
    return messages;
  }

  JsonMap _mergePrivateMessageJsons(Iterable<JsonMap> jsons) {
    final topicsById = <int, JsonMap>{};
    final usersById = <int, JsonMap>{};
    for (final json in jsons) {
      final usersJson = json['users'];
      if (usersJson is List) {
        for (final user in usersJson.whereType<JsonMap>()) {
          final id = intValue(user['id']);
          if (id > 0) {
            usersById[id] = user;
          }
        }
      }
      final topicList = json['topic_list'];
      final topicsJson = topicList is JsonMap ? topicList['topics'] : null;
      if (topicsJson is! List) {
        continue;
      }
      for (final topic in topicsJson.whereType<JsonMap>()) {
        final id = intValue(topic['id']);
        if (id <= 0) {
          continue;
        }
        final existing = topicsById[id];
        if (existing == null ||
            _topicJsonActivityTime(topic).isAfter(
              _topicJsonActivityTime(existing),
            )) {
          topicsById[id] = topic;
        }
      }
    }
    final topics = topicsById.values.toList()
      ..sort(
        (a, b) => _topicJsonActivityTime(b).compareTo(
          _topicJsonActivityTime(a),
        ),
      );
    return {
      'topic_list': {'topics': topics},
      'users': usersById.values.toList(),
    };
  }

  DateTime _topicJsonActivityTime(JsonMap topic) {
    return dateValue(topic['last_posted_at']) ??
        dateValue(topic['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime _topicActivityTime(TopicListItem topic) {
    return topic.lastPostedAt ??
        topic.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Future<Post> createPrivateMessage(PrivateMessageDraft draft) async {
    final payload = PayloadFactory.createPrivateMessage(draft);
    final json =
        await _apiClient.postForm(ForumConstants.postsPath, payload.body);
    final postJson = json['post'];
    if (postJson is! JsonMap) {
      throw const ForumApiException('私信已提交，但返回内容无法解析');
    }
    _privateMessages = null;
    return Post.fromJson(postJson);
  }

  @override
  Future<List<ForumNotification>> fetchNotifications(
    NotificationFeedFilter filter, {
    bool forceRefresh = false,
  }) async {
    if (!isOnline) {
      if (forceRefresh) {
        throw const ForumOfflineCacheMissException();
      }
      return _notifications[filter] ?? const [];
    }
    if (filter == NotificationFeedFilter.all) {
      if (!forceRefresh && _notifications[filter] != null) {
        return _notifications[filter]!;
      }
      final lists = await Future.wait([
        fetchNotifications(
          NotificationFeedFilter.replies,
          forceRefresh: forceRefresh,
        ),
        fetchNotifications(
          NotificationFeedFilter.likes,
          forceRefresh: forceRefresh,
        ),
        fetchNotifications(
          NotificationFeedFilter.mentions,
          forceRefresh: forceRefresh,
        ),
      ]);
      final seen = <String>{};
      final merged = [
        for (final list in lists)
          for (final item in list)
            if (seen.add(
              _notificationMergeKey(item),
            ))
              item,
      ];
      merged.sort((a, b) {
        final aTime = a.createdAt;
        final bTime = b.createdAt;
        if (aTime == null && bTime == null) {
          return b.id.compareTo(a.id);
        }
        if (aTime == null) {
          return 1;
        }
        if (bTime == null) {
          return -1;
        }
        return bTime.compareTo(aTime);
      });
      return _notifications[filter] = merged;
    }
    if (!forceRefresh && _notifications[filter] != null) {
      return _notifications[filter]!;
    }
    final json = await _apiClient.getJson(_notificationPath(filter));
    final items = _parseNotifications(json, filter);
    _notifications[filter] = items;
    return items;
  }

  @override
  Future<Post> likePost(int postId) async {
    final payload = PayloadFactory.likePost(postId);
    final json = await _apiClient.postForm(
      ForumConstants.postActionsPath,
      payload.body,
    );
    final post = Post.fromJson(json);
    _topicDetails.remove(post.topicId);
    _staleTopicDetailIds.remove(post.topicId);
    await _persistentCache.removeTopicDetail(post.topicId);
    return post;
  }

  @override
  Future<Post> unlikePost(int postId) async {
    final payload = PayloadFactory.unlikePost(postId);
    final json = await _apiClient.deleteForm(
      '/post_actions/$postId',
      payload.body,
    );
    final post = Post.fromJson(json);
    _topicDetails.remove(post.topicId);
    _staleTopicDetailIds.remove(post.topicId);
    await _persistentCache.removeTopicDetail(post.topicId);
    return post;
  }

  @override
  Future<ForumPollVoteResult> votePoll({
    required int topicId,
    required int postId,
    required String pollName,
    required List<String> optionIds,
  }) async {
    final payload = PayloadFactory.votePoll(
      postId: postId,
      pollName: pollName,
      optionIds: optionIds,
    );
    final json = await _apiClient.putForm('/polls/vote', payload.body);
    _topicDetails.remove(topicId);
    _staleTopicDetailIds.remove(topicId);
    _pendingTopicDetails.remove(topicId);
    await _persistentCache.removeTopicDetail(topicId);
    return ForumPollVoteResult.fromJson(json);
  }

  @override
  Future<ForumPoll> togglePollStatus({
    required int topicId,
    required int postId,
    required String pollName,
    required String status,
  }) async {
    final payload = PayloadFactory.togglePollStatus(
      postId: postId,
      pollName: pollName,
      status: status,
    );
    final json = await _apiClient.putForm(
      '/polls/toggle_status',
      payload.body,
    );
    _topicDetails.remove(topicId);
    _staleTopicDetailIds.remove(topicId);
    _pendingTopicDetails.remove(topicId);
    await _persistentCache.removeTopicDetail(topicId);
    final pollJson = json['poll'];
    return pollJson is JsonMap
        ? ForumPoll.fromJson(pollJson)
        : ForumPoll.fromJson(const <String, dynamic>{});
  }

  @override
  Future<Post> reportContent(ForumReportDraft draft) async {
    final payload = PayloadFactory.reportContent(draft);
    final json = await _apiClient.postForm(
      ForumConstants.postActionsPath,
      payload.body,
    );
    final post = Post.fromJson(json);
    final topicId = post.topicId > 0
        ? post.topicId
        : draft.flagTopic
            ? draft.id
            : 0;
    if (topicId > 0) {
      _topicDetails.remove(topicId);
      _staleTopicDetailIds.remove(topicId);
      _pendingTopicDetails.remove(topicId);
      await _persistentCache.removeTopicDetail(topicId);
    }
    return post;
  }

  @override
  Future<ForumBookmark> bookmarkTopic(int topicId) async {
    final body = Uri(
      queryParameters: {
        'reminder_at': '',
        'auto_delete_preference': '3',
        'bookmarkable_id': '$topicId',
        'bookmarkable_type': 'Topic',
      },
    ).query;
    final json = await _apiClient.postForm('/bookmarks.json', body);
    final bookmark = ForumBookmark(
      id: intValue(json['id']),
      topicId: topicId,
    );
    _activityItems.remove(ForumActivityKind.bookmarks);
    _activityCounts = null;
    return bookmark;
  }

  @override
  Future<void> unbookmarkTopic(int bookmarkId) async {
    await _apiClient.deleteForm('/bookmarks/$bookmarkId.json', '');
    _activityItems.remove(ForumActivityKind.bookmarks);
    _activityCounts = null;
  }

  @override
  Future<void> deleteTopic(TopicListItem topic) async {
    final payload = PayloadFactory.deleteTopic(topic);
    await _apiClient.deleteForm('/t/${topic.id}', payload.body);
    _topicDetails.remove(topic.id);
    _staleTopicDetailIds.remove(topic.id);
    _pendingTopicDetails.remove(topic.id);
    await _persistentCache.removeTopicDetail(topic.id);
    for (final key in _feedTopics.keys.toList()) {
      _feedTopics[key] =
          _feedTopics[key]!.where((item) => item.id != topic.id).toList();
    }
    _activityItems.remove(ForumActivityKind.topics);
    _createdTopicItems.clear();
    _activityCounts = null;
  }

  @override
  Future<void> deletePost(Post post) async {
    final payload = PayloadFactory.deletePost(post);
    await _apiClient.deleteForm(
      '${ForumConstants.postsPath}/${post.id}',
      payload.body,
    );
    _topicDetails.remove(post.topicId);
    _staleTopicDetailIds.remove(post.topicId);
    await _persistentCache.removeTopicDetail(post.topicId);
  }

  @override
  Future<void> forgetPrivateMessage(int topicId) async {
    _topicDetails.remove(topicId);
    _pendingTopicDetails.remove(topicId);
    _staleTopicDetailIds.remove(topicId);
    _privateMessages =
        _privateMessages?.where((message) => message.id != topicId).toList();
    await _persistentCache.removePrivateMessageTopic(topicId);
  }

  Future<TopicDetail?> _fetchTopicDetail(
    int id, {
    bool trackVisit = false,
  }) async {
    if (trackVisit) {
      _trackedTopicVisits.add(id);
    }
    final JsonMap json;
    try {
      json = trackVisit
          ? await _apiClient.getTrackedTopicJson(
              _topicVisitPath(id),
              topicId: id,
            )
          : await _apiClient.getJson('/t/topic/$id.json');
    } on Object {
      if (trackVisit) {
        _trackedTopicVisits.remove(id);
      }
      rethrow;
    }
    final snapshot = await _hydrateTopicSnapshot(json);
    final detail = snapshot.detail;
    _topicDetails[id] = detail;
    _staleTopicDetailIds.remove(id);
    await _persistentCache.saveTopicDetail(
      id,
      snapshot.json,
      privateMessage: detail.isPrivateMessage,
    );
    return detail;
  }

  void _trackTopicVisit(int id) {
    if (_trackedTopicVisits.contains(id)) {
      return;
    }
    _trackedTopicVisits.add(id);
    unawaited(
      _apiClient
          .getTrackedTopicJson(_topicVisitPath(id), topicId: id)
          .catchError((Object error) {
        _trackedTopicVisits.remove(id);
        return <String, dynamic>{};
      }),
    );
  }

  String _topicVisitPath(int id) {
    return '/t/$id/1.json?track_visit=true&forceLoad=true';
  }

  Future<_HydratedTopicSnapshot> _hydrateTopicSnapshot(JsonMap json) async {
    final detail = TopicDetail.fromJson(json);
    final loadedPostIds = detail.posts.map((post) => post.id).toSet();
    final missingIds = detail.postStreamIds
        .where((id) => !loadedPostIds.contains(id))
        .toList(growable: false);
    if (missingIds.isEmpty) {
      return _HydratedTopicSnapshot(detail: detail, json: json);
    }
    try {
      final postJsons = await _fetchPostJsonsByIds(detail, missingIds);
      if (postJsons.isEmpty) {
        return _HydratedTopicSnapshot(detail: detail, json: json);
      }
      final posts = postJsons.map(Post.fromJson);
      final hydrated = detail.mergedWithPosts(posts);
      return _HydratedTopicSnapshot(
        detail: hydrated,
        json: _mergePostJsonsIntoTopicJson(json, postJsons),
      );
    } on ForumApiException {
      return _HydratedTopicSnapshot(detail: detail, json: json);
    }
  }

  Future<List<JsonMap>> _fetchPostJsonsByIds(
    TopicDetail detail,
    List<int> postIds,
  ) async {
    final posts = <JsonMap>[];
    for (var start = 0; start < postIds.length; start += 20) {
      final end = start + 20 > postIds.length ? postIds.length : start + 20;
      final batch = postIds.sublist(start, end);
      final json = await _getPostBatch(detail, batch);
      final stream = json['post_stream'];
      final postsJson = stream is JsonMap ? stream['posts'] : json['posts'];
      if (postsJson is List) {
        posts.addAll(postsJson.whereType<JsonMap>());
      }
    }
    return posts;
  }

  JsonMap _mergePostJsonsIntoTopicJson(
    JsonMap json,
    Iterable<JsonMap> incomingPosts,
  ) {
    final stream = json['post_stream'];
    if (stream is! JsonMap) {
      return json;
    }
    final byId = <int, JsonMap>{};
    final postsJson = stream['posts'];
    if (postsJson is List) {
      for (final post in postsJson.whereType<JsonMap>()) {
        final id = intValue(post['id']);
        if (id > 0) {
          byId[id] = post;
        }
      }
    }
    for (final post in incomingPosts) {
      final id = intValue(post['id']);
      if (id > 0) {
        byId[id] = post;
      }
    }
    final posts = byId.values.toList()
      ..sort((a, b) => intValue(a['post_number']).compareTo(
            intValue(b['post_number']),
          ));
    final streamIdsJson = stream['stream'];
    final streamIds = streamIdsJson is List
        ? streamIdsJson.map(intValue).where((id) => id > 0).toList()
        : <int>[];
    for (final post in posts) {
      final id = intValue(post['id']);
      if (id > 0 && !streamIds.contains(id)) {
        streamIds.add(id);
      }
    }
    return {
      ...json,
      'post_stream': {
        ...stream,
        'posts': posts,
        'stream': streamIds,
      },
    };
  }

  Future<JsonMap> _getPostBatch(TopicDetail detail, List<int> postIds) async {
    final query = postIds.map((id) => 'post_ids%5B%5D=$id').join('&');
    final slug = detail.slug.isEmpty ? 'topic' : detail.slug;
    try {
      return await _apiClient.getJson(
        '/t/${Uri.encodeComponent(slug)}/${detail.id}/posts.json?$query',
      );
    } on ForumApiException {
      return _apiClient.getJson('/t/${detail.id}/posts.json?$query');
    }
  }

  bool _shouldInvalidatePrivateMessageDetail(TopicListItem message) {
    final detail = _topicDetails[message.id];
    if (detail == null) {
      return false;
    }
    final topicTime = message.lastPostedAt ?? message.createdAt;
    final detailTime = _latestPostTime(detail);
    if (topicTime == null || detailTime == null) {
      return true;
    }
    return topicTime.difference(detailTime) > const Duration(seconds: 1);
  }

  DateTime? _latestPostTime(TopicDetail detail) {
    DateTime? latest;
    for (final post in detail.posts) {
      final createdAt = post.createdAt;
      if (createdAt == null) {
        continue;
      }
      if (latest == null || createdAt.isAfter(latest)) {
        latest = createdAt;
      }
    }
    return latest;
  }

  void _mergeUsers(JsonMap json) {
    users.addAll(FixtureForumRepository._parseUsers(json));
  }

  UserProfile _storeProfile(UserProfile profile) {
    users[profile.id] = profile.user;
    final key = profile.username.toLowerCase();
    _userProfiles[key] = profile;
    if (key == _session.username.toLowerCase()) {
      _profile = profile;
      _profileUpdatedAt = DateTime.now();
      unawaited(_saveAccountSnapshot());
    }
    return profile;
  }

  UserProfile _profileFromMutationResponse(JsonMap json) {
    final user = json['user'];
    if (user is! JsonMap) {
      throw const ForumApiException('资料已提交，但返回内容无法解析');
    }
    return _storeProfile(UserProfile.fromJson({'user': user}));
  }

  Future<List<TopicListItem>> _loadMoreTopics({
    required List<TopicListItem> currentTopics,
    required String? morePath,
    required void Function(List<TopicListItem> topics, String? morePath)
        setState,
  }) async {
    if (morePath == null) {
      return currentTopics;
    }
    final json = await _apiClient.getJson(_jsonListPath(morePath));
    _mergeUsers(json);
    final nextTopics = FixtureForumRepository._parseTopics(json);
    final seenIds = currentTopics.map((topic) => topic.id).toSet();
    final merged = [
      ...currentTopics,
      ...nextTopics.where((topic) => seenIds.add(topic.id)),
    ];
    setState(merged, _parseMoreTopicsPath(json));
    return merged;
  }

  String _feedPath(TopicFeedQuery query) {
    final categoryId = query.categoryId;
    if (categoryId == null) {
      return query.hot ? '/hot.json' : '/latest.json';
    }
    final slug = _categories[categoryId]?.routeSlug ?? '$categoryId-category';
    final mode = query.hot ? 'hot' : 'latest';
    final filter = query.hot ? 'hot' : 'default';
    return '/c/$slug/$categoryId/l/$mode.json?filter=$filter';
  }

  String _activityPath(ForumActivityKind kind) {
    final username = profile.username;
    final lower = username.toLowerCase();
    return switch (kind) {
      ForumActivityKind.topics => '/topics/created-by/$lower.json',
      ForumActivityKind.read => '/read.json',
      ForumActivityKind.bookmarks =>
        '/u/${Uri.encodeComponent(username)}/bookmarks.json?q=&acting_username=',
    };
  }

  List<ForumActivityItem> _parseActivityItems(
    ForumActivityKind kind,
    JsonMap json,
  ) {
    if (kind == ForumActivityKind.bookmarks) {
      final list = json['user_bookmark_list'];
      final bookmarks = list is JsonMap ? list['bookmarks'] : null;
      if (bookmarks is! List) {
        return const [];
      }
      return bookmarks
          .whereType<JsonMap>()
          .map(ForumActivityItem.fromBookmark)
          .where((item) => item.topicId > 0)
          .toList(growable: false);
    }
    return FixtureForumRepository._parseTopics(json)
        .map(ForumActivityItem.fromTopic)
        .toList(growable: false);
  }

  String _notificationPath(NotificationFeedFilter filter) {
    final username = profile.username;
    final lower = username.toLowerCase();
    return switch (filter) {
      NotificationFeedFilter.all =>
        '/notifications?username=$username&filter=all&limit=60',
      NotificationFeedFilter.replies =>
        '/user_actions.json?offset=0&username=$lower&filter=6,9',
      NotificationFeedFilter.likes =>
        '/user_actions.json?offset=0&username=$lower&filter=2',
      NotificationFeedFilter.mentions =>
        '/user_actions.json?offset=0&username=$lower&filter=7',
    };
  }

  List<ForumNotification> _parseNotifications(
    JsonMap json,
    NotificationFeedFilter filter,
  ) {
    final notificationsJson = json['notifications'];
    if (notificationsJson is List) {
      return notificationsJson
          .whereType<JsonMap>()
          .where(ForumNotification.isSupportedNotificationJson)
          .map(ForumNotification.fromNotificationJson)
          .where((notification) => notification.isClientVisible)
          .toList();
    }
    final actionsJson = json['user_actions'];
    if (actionsJson is List) {
      return actionsJson
          .whereType<JsonMap>()
          .map((action) => ForumNotification.fromUserActionJson(
                action,
                _notificationKind(filter),
              ))
          .where((notification) => notification.isClientVisible)
          .toList();
    }
    return const [];
  }

  String _notificationMergeKey(ForumNotification item) {
    final createdAt = item.createdAt?.millisecondsSinceEpoch ?? 0;
    return [
      item.kind,
      item.topicId ?? 0,
      item.postNumber ?? 0,
      item.id,
      createdAt,
      item.title,
      item.message,
    ].join(':');
  }

  String _notificationKind(NotificationFeedFilter filter) {
    return switch (filter) {
      NotificationFeedFilter.all => '通知',
      NotificationFeedFilter.replies => '回复',
      NotificationFeedFilter.likes => '赞',
      NotificationFeedFilter.mentions => '提及',
    };
  }

  String _uploadClientId() {
    final seed = '${profile.username}:${DateTime.now().microsecondsSinceEpoch}';
    return Sha1Hash.hex(Uint8List.fromList(utf8.encode(seed)));
  }

  static String? _parseMoreTopicsPath(JsonMap json) {
    final list = json['topic_list'];
    if (list is! JsonMap) {
      return null;
    }
    final more = stringValue(list['more_topics_url']);
    return more.isEmpty ? null : more;
  }

  static String _jsonListPath(String path) {
    final uri = Uri.parse(path);
    if (uri.path.endsWith('.json')) {
      return path;
    }
    return uri.replace(path: '${uri.path}.json').toString();
  }

  static Future<CurrentUserSession> _fetchSession(
    DiscourseApiClient apiClient,
  ) async {
    final json = await apiClient.getJson('/session/current.json');
    final currentUser = json['current_user'];
    if (currentUser is! JsonMap) {
      throw const ForumAuthException();
    }
    return CurrentUserSession.fromJson(currentUser);
  }

  static Future<Map<int, ForumCategory>> _fetchCategories(
    DiscourseApiClient apiClient,
    FixtureForumRepository fallback,
  ) async {
    try {
      final json = await apiClient.getJson('/categories.json');
      final categories = FixtureForumRepository._parseCategories(json);
      if (categories.isNotEmpty) {
        return categories;
      }
    } on ForumApiException {
      try {
        final json = await apiClient.getJson('/site.json');
        final categories = FixtureForumRepository._parseCategories(json);
        if (categories.isNotEmpty) {
          return categories;
        }
      } on ForumApiException {
        return fallback._categories;
      }
    }
    return fallback._categories;
  }
}

class _HydratedTopicSnapshot {
  const _HydratedTopicSnapshot({
    required this.detail,
    required this.json,
  });

  final TopicDetail detail;
  final JsonMap json;
}

ForumActivityCounts? _activityCountsFromJson(JsonMap json) {
  try {
    return ForumActivityCounts.fromJson(json);
  } on Object {
    return null;
  }
}

List<ForumCategory> _sortedCategories(Map<int, ForumCategory> categories) {
  final list = categories.values.toList();
  list.sort((a, b) {
    final byPosition = a.position.compareTo(b.position);
    return byPosition == 0 ? a.id.compareTo(b.id) : byPosition;
  });
  return list;
}

class ForumRepositoryFactory {
  const ForumRepositoryFactory._();

  static const _startupOnlineTimeout = Duration(seconds: 5);
  static const _requiredOnlineTimeout = Duration(seconds: 10);

  static Future<ForumRepository> load() async {
    await _configureForumAccessMode();
    final fixture = await FixtureForumRepository.load();
    final offline =
        await OnlineForumRepository.restoreOffline(fallback: fixture);
    if (offline != null) {
      return offline;
    }
    try {
      return await OnlineForumRepository.connect(
        fallback: fixture,
      ).timeout(_startupOnlineTimeout);
    } on Object {
      return fixture;
    }
  }

  static Future<ForumRepository> loadOnline() async {
    await _configureForumAccessMode();
    final fixture = await FixtureForumRepository.load();
    return OnlineForumRepository.connect(
      fallback: fixture,
    ).timeout(
      _requiredOnlineTimeout,
      onTimeout: () {
        throw const ForumConnectionUnavailableException(
          '论坛连接超时，请检查网络或开启 WebVPN 代理',
        );
      },
    );
  }

  static Future<void> _configureForumAccessMode() async {
    final settings = await ClientSettingsService().loadNetworkSettings();
    ForumUrlResolver.configure(
      useWebVpn: settings.autoUseWebVpnProxy,
    );
  }
}
