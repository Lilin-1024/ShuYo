import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/forum_constants.dart';
import '../models/category.dart';
import '../models/common.dart';
import '../models/current_user.dart';
import '../models/discourse_user.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../models/topic_detail.dart';
import '../models/user_profile.dart';
import '../services/discourse_api_client.dart';
import '../services/forum_auth_service.dart';
import '../services/html_text.dart';
import '../services/payload_factory.dart';

abstract class ForumRepository {
  bool get isOnline;
  Map<int, DiscourseUser> get users;
  UserProfile get profile;
  UserSummary get userSummary;
  int get unreadNotificationCount;

  ForumCategory? categoryById(int id);
  bool get canLoadMoreLatest;
  bool get canLoadMoreHot;
  Future<List<TopicListItem>> fetchLatestTopics({bool forceRefresh = false});
  Future<List<TopicListItem>> fetchHotTopics({bool forceRefresh = false});
  Future<List<TopicListItem>> loadMoreLatestTopics();
  Future<List<TopicListItem>> loadMoreHotTopics();
  Future<TopicDetail?> fetchTopicDetail(
    int id, {
    bool forceRefresh = false,
  });
  Future<TopicPreview> fetchTopicPreview(int id);
  Future<Post> createReply(ReplyDraft draft);
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
  final UserProfile profile;

  @override
  final UserSummary userSummary;

  @override
  bool get isOnline => false;

  @override
  int get unreadNotificationCount => 0;

  @override
  ForumCategory? categoryById(int id) => _categories[id];

  @override
  bool get canLoadMoreLatest => false;

  @override
  bool get canLoadMoreHot => false;

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
  Future<Post> createReply(ReplyDraft draft) {
    throw const ForumAuthException('请先登录后再评论');
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
    final categories = json['categories'];
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
  List<TopicListItem>? _latestTopics;
  List<TopicListItem>? _hotTopics;
  String? _latestMorePath;
  String? _hotMorePath;

  @override
  final Map<int, DiscourseUser> users;

  @override
  bool get isOnline => true;

  @override
  UserProfile get profile => _session.profile;

  @override
  UserSummary get userSummary => _userSummary;

  @override
  int get unreadNotificationCount => _session.notificationBadgeCount;

  @override
  Future<void> clearLoginCookies() => _authService.clearCookies();

  @override
  ForumCategory? categoryById(int id) {
    return _categories[id] ?? _fallback.categoryById(id);
  }

  @override
  bool get canLoadMoreLatest => _latestMorePath != null;

  @override
  bool get canLoadMoreHot => _hotMorePath != null;

  @override
  Future<List<TopicListItem>> fetchLatestTopics({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _latestTopics != null) {
      return _latestTopics!;
    }
    final json = await _apiClient.getJson('/latest.json');
    _mergeUsers(json);
    _latestMorePath = _parseMoreTopicsPath(json);
    return _latestTopics = FixtureForumRepository._parseTopics(json);
  }

  @override
  Future<List<TopicListItem>> fetchHotTopics(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _hotTopics != null) {
      return _hotTopics!;
    }
    final json = await _apiClient.getJson('/hot.json');
    _mergeUsers(json);
    _hotMorePath = _parseMoreTopicsPath(json);
    return _hotTopics = FixtureForumRepository._parseTopics(json);
  }

  @override
  Future<List<TopicListItem>> loadMoreLatestTopics() async {
    return _loadMoreTopics(
      currentTopics: _latestTopics ?? await fetchLatestTopics(),
      morePath: _latestMorePath,
      setState: (topics, morePath) {
        _latestTopics = topics;
        _latestMorePath = morePath;
      },
    );
  }

  @override
  Future<List<TopicListItem>> loadMoreHotTopics() async {
    return _loadMoreTopics(
      currentTopics: _hotTopics ?? await fetchHotTopics(),
      morePath: _hotMorePath,
      setState: (topics, morePath) {
        _hotTopics = topics;
        _hotMorePath = morePath;
      },
    );
  }

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
  Future<Post> createReply(ReplyDraft draft) async {
    final payload = PayloadFactory.createReply(draft);
    final json =
        await _apiClient.postForm(ForumConstants.postsPath, payload.body);
    final postJson = json['post'];
    if (postJson is! JsonMap) {
      throw const ForumApiException('评论已提交，但返回内容无法解析');
    }
    _topicDetails.remove(draft.topicId);
    return Post.fromJson(postJson);
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
      final json = await apiClient.getJson('/site.json');
      final categories = FixtureForumRepository._parseCategories(json);
      if (categories.isNotEmpty) {
        return categories;
      }
    } on ForumApiException {
      return fallback._categories;
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
