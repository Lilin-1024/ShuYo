import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/forum_constants.dart';
import '../models/category.dart';
import '../models/common.dart';
import '../models/composer.dart';
import '../models/current_user.dart';
import '../models/discourse_user.dart';
import '../models/forum_notification.dart';
import '../models/forum_search.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../models/topic_detail.dart';
import '../models/user_profile.dart';
import '../services/discourse_api_client.dart';
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
  bool get canCreateTopic;

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
  Future<UserSummary> fetchUserSummary(
    String username, {
    bool forceRefresh = false,
  });
  Future<TopicDetail?> fetchTopicDetail(
    int id, {
    bool forceRefresh = false,
  });
  Future<TopicPreview> fetchTopicPreview(int id);
  Future<Post> createTopic(CreateTopicDraft draft);
  Future<UploadedImage> uploadImage(PickedImage image);
  Future<Post> createReply(ReplyDraft draft);
  Future<List<TopicListItem>> fetchPrivateMessages({bool forceRefresh = false});
  Future<Post> createPrivateMessage(PrivateMessageDraft draft);
  Future<List<ForumNotification>> fetchNotifications(
    NotificationFeedFilter filter, {
    bool forceRefresh = false,
  });
  Future<Post> likePost(int postId);
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
  bool get canCreateTopic => false;

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
  }) async {
    return _topicDetails[id];
  }

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
  Future<Post> createTopic(CreateTopicDraft draft) {
    throw const ForumAuthException('请先登录后再发帖');
  }

  @override
  Future<UploadedImage> uploadImage(PickedImage image) {
    throw const ForumAuthException('请先登录后再上传图片');
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
    await repository.fetchLatestTopics();
    return repository;
  }

  final DiscourseApiClient _apiClient;
  final ForumAuthService _authService;
  final FixtureForumRepository _fallback;
  final CurrentUserSession _session;
  final UserSummary _userSummary;
  final Map<int, ForumCategory> _categories;
  final Map<int, TopicDetail> _topicDetails = {};
  final Map<int, Future<TopicDetail?>> _pendingTopicDetails = {};
  final Map<String, UserProfile> _userProfiles = {};
  final Map<String, UserSummary> _userSummaries = {};
  final Map<String, List<TopicListItem>> _feedTopics = {};
  final Map<String, String?> _feedMorePaths = {};
  final Map<NotificationFeedFilter, List<ForumNotification>> _notifications =
      {};
  List<TopicListItem>? _privateMessages;

  @override
  final Map<int, DiscourseUser> users;

  @override
  List<ForumCategory> get categories => _sortedCategories(_categories);

  @override
  bool get isOnline => true;

  @override
  UserProfile get profile => _session.profile;

  @override
  UserSummary get userSummary => _userSummary;

  @override
  int get unreadNotificationCount => _session.notificationBadgeCount;

  @override
  bool get canCreateTopic => _session.canCreateTopic;

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
  }) {
    if (!forceRefresh) {
      final cached = _topicDetails[id];
      if (cached != null) {
        return Future.value(cached);
      }
      final pending = _pendingTopicDetails[id];
      if (pending != null) {
        return pending;
      }
    }

    final future = _fetchTopicDetail(id);
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
    users[profile.id] = profile.user;
    return _userProfiles[key] = profile;
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
    return _userSummaries[key] = UserSummary.fromJson(json);
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
  Future<Post> createReply(ReplyDraft draft) async {
    final payload = PayloadFactory.createReply(draft);
    final json =
        await _apiClient.postForm(ForumConstants.postsPath, payload.body);
    final postJson = json['post'];
    if (postJson is! JsonMap) {
      throw const ForumApiException('评论已提交，但返回内容无法解析');
    }
    _topicDetails.remove(draft.topicId);
    _privateMessages = null;
    return Post.fromJson(postJson);
  }

  @override
  Future<List<TopicListItem>> fetchPrivateMessages({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _privateMessages != null) {
      return _privateMessages!;
    }
    final path =
        '/topics/private-messages/${profile.username.toLowerCase()}.json';
    final json = await _apiClient.getJson(path);
    _mergeUsers(json);
    return _privateMessages = FixtureForumRepository._parseTopics(json);
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
  Future<void> deletePost(Post post) async {
    final payload = PayloadFactory.deletePost(post);
    await _apiClient.deleteForm(
      '${ForumConstants.postsPath}/${post.id}',
      payload.body,
    );
    _topicDetails.remove(post.topicId);
  }

  Future<TopicDetail?> _fetchTopicDetail(int id) async {
    final json = await _apiClient.getJson('/t/topic/$id.json');
    final detail = TopicDetail.fromJson(json);
    _topicDetails[id] = detail;
    return detail;
  }

  void _mergeUsers(JsonMap json) {
    users.addAll(FixtureForumRepository._parseUsers(json));
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
    final fixture = await FixtureForumRepository.load();
    try {
      return await OnlineForumRepository.connect(fallback: fixture);
    } on Object {
      return fixture;
    }
  }

  static Future<ForumRepository> loadOnline() async {
    final fixture = await FixtureForumRepository.load();
    return OnlineForumRepository.connect(fallback: fixture);
  }
}
