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
import '../models/forum_search.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../models/topic_detail.dart';
import '../models/user_profile.dart';
import '../services/discourse_api_client.dart';
import '../services/client_settings_service.dart';
import '../services/forum_auth_service.dart';
import '../services/html_text.dart';
import '../services/payload_factory.dart';
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

abstract class ForumRepository {
  bool get isOnline;
  Map<int, DiscourseUser> get users;
  List<ForumCategory> get categories;
  UserProfile get profile;
  UserSummary get userSummary;
  int get unreadNotificationCount;
  int get unreadPrivateMessageCount;
  bool get canCreateTopic;
  Future<void> refreshSession();

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
  Future<void> recordTopicTiming(
    int topicId, {
    required int postNumber,
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
  Future<ForumBookmark> bookmarkTopic(int topicId);
  Future<void> unbookmarkTopic(int bookmarkId);
  Future<void> deleteTopic(TopicListItem topic);
  Future<void> deletePost(Post post);
  Future<void> clearLoginCookies();
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
  bool get isOnline => false;

  @override
  int get unreadNotificationCount => 0;

  @override
  int get unreadPrivateMessageCount => 0;

  @override
  bool get canCreateTopic => false;

  @override
  Future<void> refreshSession() async {}

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
  Future<void> recordTopicTiming(
    int topicId, {
    required int postNumber,
    required int topicTimeMs,
  }) async {}

  @override
  Future<TopicPreview> fetchTopicPreview(int id) async {
    final first = _topicDetails[id]?.firstPost;
    if (first == null) {
      return const TopicPreview(
        text: '暂无摘要，打开后可加载主题详情',
        imageUrls: [],
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
  Future<void> clearLoginCookies() async {}

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
    required Map<int, ForumCategory> categories,
  })  : _apiClient = apiClient,
        _authService = authService,
        _fallback = fallback,
        _session = session,
        _profile = session.profile,
        _userSummary = userSummary,
        _categories = categories,
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
    final categories = await _fetchCategories(apiClient, fallback);
    final summary = await _fetchSummary(apiClient, fallback, session.username);
    final repository = OnlineForumRepository._(
      apiClient: apiClient,
      authService: auth,
      fallback: fallback,
      session: session,
      userSummary: summary,
      categories: categories,
    );
    try {
      await repository.fetchCurrentUserProfile(forceRefresh: true);
    } on ForumApiException {
      // 简略 session 资料足够启动应用，完整资料可稍后进入页面时再刷新。
    }
    await repository.fetchLatestTopics();
    return repository;
  }

  final DiscourseApiClient _apiClient;
  final ForumAuthService _authService;
  final FixtureForumRepository _fallback;
  CurrentUserSession _session;
  UserProfile _profile;
  UserSummary _userSummary;
  final Map<int, ForumCategory> _categories;
  final Map<int, TopicDetail> _topicDetails = {};
  final Map<int, Future<TopicDetail?>> _pendingTopicDetails = {};
  final Set<int> _trackedTopicVisits = {};
  final Set<int> _trackedTopicTimings = {};
  final Map<String, UserProfile> _userProfiles = {};
  final Map<String, UserSummary> _userSummaries = {};
  final Map<String, List<TopicListItem>> _feedTopics = {};
  final Map<String, String?> _feedMorePaths = {};
  final Map<ForumActivityKind, List<ForumActivityItem>> _activityItems = {};
  final Map<String, List<ForumActivityItem>> _createdTopicItems = {};
  final Map<NotificationFeedFilter, List<ForumNotification>> _notifications =
      {};
  ForumActivityCounts? _activityCounts;
  List<TopicListItem>? _privateMessages;

  @override
  final Map<int, DiscourseUser> users;

  @override
  List<ForumCategory> get categories => _sortedCategories(_categories);

  @override
  bool get isOnline => true;

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
    users[session.user.id] = session.user;
  }

  @override
  Future<void> clearLoginCookies() => _authService.clearCookies();

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
    final json = await _apiClient.getJson(_feedPath(query));
    _mergeUsers(json);
    _feedMorePaths[query.key] = _parseMoreTopicsPath(json);
    return _feedTopics[query.key] = FixtureForumRepository._parseTopics(json);
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
    if (!forceRefresh) {
      final cached = _topicDetails[id];
      if (cached != null) {
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
  Future<TopicPreview> fetchTopicPreview(int id) async {
    final detail = await fetchTopicDetail(id);
    final first = detail?.firstPost;
    if (first == null) {
      return const TopicPreview(text: '暂无摘要', imageUrls: []);
    }
    return HtmlText.topicPreview(first.cooked);
  }

  @override
  Future<void> recordTopicTiming(
    int topicId, {
    required int postNumber,
    required int topicTimeMs,
  }) async {
    if (_trackedTopicTimings.contains(topicId)) {
      return;
    }
    _trackedTopicTimings.add(topicId);
    final payload = PayloadFactory.topicTiming(
      topicId: topicId,
      postNumber: postNumber,
      topicTimeMs: topicTimeMs,
    );
    try {
      await _apiClient.postForm('/topics/timings', payload.body);
    } on Object {
      _trackedTopicTimings.remove(topicId);
      rethrow;
    }
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
  }) async {
    final key = username.toLowerCase();
    if (!forceRefresh && _userProfiles[key] != null) {
      return _userProfiles[key]!;
    }
    final json =
        await _apiClient.getJson('/u/${Uri.encodeComponent(key)}.json');
    final profile = UserProfile.fromJson(json);
    return _storeProfile(profile);
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
    final key = username.toLowerCase();
    if (!forceRefresh && _userSummaries[key] != null) {
      return _userSummaries[key]!;
    }
    final json = await _apiClient.getJson(
      '/u/${Uri.encodeComponent(key)}/summary.json',
    );
    final summary = UserSummary.fromJson(json);
    _userSummaries[key] = summary;
    if (key == profile.username.toLowerCase()) {
      _userSummary = summary;
    }
    return summary;
  }

  @override
  Future<ForumActivityCounts> fetchActivityCounts({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _activityCounts != null) {
      return _activityCounts!;
    }
    final summary = await fetchUserSummary(
      profile.username,
      forceRefresh: forceRefresh,
    );
    final activities = await Future.wait([
      fetchUserActivity(ForumActivityKind.topics, forceRefresh: forceRefresh),
      fetchUserActivity(ForumActivityKind.read, forceRefresh: forceRefresh),
      fetchUserActivity(
        ForumActivityKind.bookmarks,
        forceRefresh: forceRefresh,
      ),
    ]);
    final topics = activities[0];
    final read = activities[1];
    final bookmarks = activities[2];
    return _activityCounts = ForumActivityCounts(
      topics: _largerCount(summary.topicCount, topics.length),
      read: _largerCount(summary.topicsEntered, read.length),
      bookmarks: bookmarks.length,
    );
  }

  int _largerCount(int left, int right) => left > right ? left : right;

  @override
  Future<List<ForumActivityItem>> fetchUserActivity(
    ForumActivityKind kind, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _activityItems[kind] != null) {
      return _activityItems[kind]!;
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
    } else {
      _topicDetails[draft.topicId] = cached.mergedWithPosts([post]);
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
    final username = profile.username.toLowerCase();
    final responses = await Future.wait([
      _apiClient.getJson('/topics/private-messages/$username.json'),
      _apiClient.getJson('/topics/private-messages-sent/$username.json'),
    ]);
    final messagesById = <int, TopicListItem>{};
    for (final json in responses) {
      _mergeUsers(json);
      for (final message in FixtureForumRepository._parseTopics(json)) {
        final existing = messagesById[message.id];
        messagesById[message.id] = existing == null
            ? message
            : _newerPrivateMessageTopic(existing, message);
      }
    }
    final messages = messagesById.values.toList()
      ..sort((a, b) => _topicActivityTime(b).compareTo(_topicActivityTime(a)));
    if (forceRefresh) {
      for (final message in messages) {
        _pendingTopicDetails.remove(message.id);
        if (_shouldInvalidatePrivateMessageDetail(message)) {
          _topicDetails.remove(message.id);
        }
      }
    }
    return _privateMessages = messages;
  }

  TopicListItem _newerPrivateMessageTopic(
    TopicListItem current,
    TopicListItem next,
  ) {
    final currentTime = _topicActivityTime(current);
    final nextTime = _topicActivityTime(next);
    if (nextTime.isAfter(currentTime)) {
      return next;
    }
    return current;
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
    _pendingTopicDetails.remove(topic.id);
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
      json = await _apiClient.getJson(
        trackVisit ? _topicVisitPath(id) : '/t/topic/$id.json',
      );
    } on Object {
      if (trackVisit) {
        _trackedTopicVisits.remove(id);
      }
      rethrow;
    }
    final detail = await _hydrateMissingPosts(TopicDetail.fromJson(json));
    _topicDetails[id] = detail;
    return detail;
  }

  void _trackTopicVisit(int id) {
    if (_trackedTopicVisits.contains(id)) {
      return;
    }
    _trackedTopicVisits.add(id);
    unawaited(
      _apiClient.getJson(_topicVisitPath(id)).catchError((Object error) {
        _trackedTopicVisits.remove(id);
        return <String, dynamic>{};
      }),
    );
  }

  String _topicVisitPath(int id) {
    return '/t/$id/1.json?track_visit=true&forceLoad=true';
  }

  Future<TopicDetail> _hydrateMissingPosts(TopicDetail detail) async {
    final loadedPostIds = detail.posts.map((post) => post.id).toSet();
    final missingIds = detail.postStreamIds
        .where((id) => !loadedPostIds.contains(id))
        .toList(growable: false);
    if (missingIds.isEmpty) {
      return detail;
    }
    try {
      final posts = await _fetchPostsByIds(detail, missingIds);
      return posts.isEmpty ? detail : detail.mergedWithPosts(posts);
    } on ForumApiException {
      return detail;
    }
  }

  Future<List<Post>> _fetchPostsByIds(
    TopicDetail detail,
    List<int> postIds,
  ) async {
    final posts = <Post>[];
    for (var start = 0; start < postIds.length; start += 20) {
      final end = start + 20 > postIds.length ? postIds.length : start + 20;
      final batch = postIds.sublist(start, end);
      final json = await _getPostBatch(detail, batch);
      final stream = json['post_stream'];
      final postsJson = stream is JsonMap ? stream['posts'] : json['posts'];
      if (postsJson is List) {
        posts.addAll(postsJson.whereType<JsonMap>().map(Post.fromJson));
      }
    }
    return posts;
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
          .map(ForumNotification.fromNotificationJson)
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

  static Future<UserSummary> _fetchSummary(
    DiscourseApiClient apiClient,
    FixtureForumRepository fallback,
    String username,
  ) async {
    try {
      final json =
          await apiClient.getJson('/u/${username.toLowerCase()}/summary.json');
      return UserSummary.fromJson(json);
    } on ForumApiException {
      return fallback.userSummary;
    }
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

  static Future<ForumRepository> load() async {
    await _configureForumAccessMode();
    final fixture = await FixtureForumRepository.load();
    try {
      return await OnlineForumRepository.connect(fallback: fixture);
    } on Object {
      return fixture;
    }
  }

  static Future<ForumRepository> loadOnline() async {
    await _configureForumAccessMode();
    final fixture = await FixtureForumRepository.load();
    return OnlineForumRepository.connect(fallback: fixture);
  }

  static Future<void> _configureForumAccessMode() async {
    final settings = await ClientSettingsService().loadNetworkSettings();
    ForumUrlResolver.configure(
      useWebVpn: settings.autoUseWebVpnProxy,
    );
  }
}
