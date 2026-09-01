import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/category.dart';
import '../models/common.dart';
import '../models/composer.dart';
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
import '../repositories/forum_repository.dart';
import '../services/discourse_api_client.dart';
import '../services/html_text.dart';
import '../services/payload_factory.dart';

/// Mutable, completely offline forum repository used by the App Store demo.
class DemoForumRepository implements ForumRepository {
  DemoForumRepository._({
    required this.users,
    required this.profile,
    required this.userSummary,
    required Map<int, ForumCategory> categories,
    required List<TopicListItem> topics,
    required List<TopicListItem> privateMessages,
    required Map<int, TopicDetail> details,
    required List<ForumNotification> notifications,
  })  : _categories = categories,
        _topics = topics,
        _privateMessages = privateMessages,
        _details = details,
        _notifications = notifications;

  static Future<DemoForumRepository> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final site = await _json(assets, 'assets/demo/forum/site.json');
    final latest = await _json(assets, 'assets/demo/forum/latest.json');
    final profileJson =
        await _json(assets, 'assets/demo/forum/admin-profile.json');
    final privateJson =
        await _json(assets, 'assets/demo/forum/private-messages.json');
    final notificationJson =
        await _json(assets, 'assets/demo/forum/notifications.json');

    final details = <int, TopicDetail>{};
    for (final id in [9001, 9002, 9003, 9004, 9101, 9102, 9103, 9104]) {
      final detail = TopicDetail.fromJson(
        await _json(assets,
            'assets/demo/forum/${id >= 9100 ? 'private-message-' : 'topic-'}$id.json'),
      );
      details[detail.id] = _demoDetail(detail);
    }
    final users = _parseUsers(latest);
    users.addAll(_parseUsers(privateJson));
    final currentProfile = UserProfile.fromJson(profileJson);
    users[currentProfile.id] = currentProfile.user;
    final notifications =
        (notificationJson['notifications'] as List? ?? const [])
            .whereType<JsonMap>()
            .where(ForumNotification.isSupportedNotificationJson)
            .map(ForumNotification.fromNotificationJson)
            .toList(growable: true);
    return DemoForumRepository._(
      users: users,
      profile: currentProfile,
      userSummary: const UserSummary(
        likesGiven: 12,
        likesReceived: 28,
        topicsEntered: 18,
        postsReadCount: 96,
        daysVisited: 6,
        topicCount: 2,
        postCount: 6,
        timeReadSeconds: 3600,
      ),
      categories: _parseCategories(site),
      topics: _parseTopics(latest),
      privateMessages: _parseTopics(privateJson),
      details: details,
      notifications: notifications,
    );
  }

  @override
  final Map<int, DiscourseUser> users;
  @override
  final UserProfile profile;
  @override
  final UserSummary userSummary;
  final Map<int, ForumCategory> _categories;
  final List<TopicListItem> _topics;
  final List<TopicListItem> _privateMessages;
  final Map<int, TopicDetail> _details;
  final List<ForumNotification> _notifications;
  final Set<int> _bookmarkedTopicIds = {};
  final Set<int> _likedPostIds = {};
  int _nextTopicId = 9800;
  int _nextPostId = 19800;

  @override
  ForumConnectionState get connectionState => ForumConnectionState.online;

  @override
  bool get hasLocalAccount => true;

  @override
  bool get isCacheOnly => false;

  @override
  bool get isOnline => true;

  @override
  List<ForumCategory> get categories => _sortedCategories(_categories);

  @override
  bool get hasCachedUserSummary => true;

  @override
  bool get hasCachedActivityCounts => true;

  @override
  bool get hasCachedPrivateMessages => true;

  @override
  int get unreadNotificationCount =>
      _notifications.where((item) => !item.read).length;

  @override
  int get unreadPrivateMessageCount => _privateMessages.length > 1 ? 2 : 0;

  @override
  bool get canCreateTopic => true;

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
  Future<List<TopicListItem>> fetchTopicFeed(TopicFeedQuery query,
      {bool forceRefresh = false}) async {
    Iterable<TopicListItem> result = query.hot
        ? (_topics.toList()..sort((a, b) => b.likeCount.compareTo(a.likeCount)))
        : _topics;
    if (query.categoryId != null) {
      result = result.where((topic) => topic.categoryId == query.categoryId);
    }
    return result.toList(growable: false);
  }

  @override
  Future<List<TopicListItem>> loadMoreTopicFeed(TopicFeedQuery query) =>
      fetchTopicFeed(query);

  @override
  Future<List<TopicListItem>> fetchLatestTopics({bool forceRefresh = false}) =>
      fetchTopicFeed(const TopicFeedQuery());

  @override
  Future<List<TopicListItem>> fetchHotTopics({bool forceRefresh = false}) =>
      fetchTopicFeed(const TopicFeedQuery(hot: true));

  @override
  Future<List<TopicListItem>> loadMoreLatestTopics() => fetchLatestTopics();

  @override
  Future<List<TopicListItem>> loadMoreHotTopics() => fetchHotTopics();

  @override
  Future<TopicDetail?> fetchTopicDetail(int id,
          {bool forceRefresh = false, bool trackVisit = false}) async =>
      _details[id];

  @override
  TopicDetail? cachedTopicDetail(int id) => _details[id];

  @override
  Future<void> recordTopicTiming(int topicId,
      {required int postNumber, required int topicTimeMs}) async {}

  @override
  Future<void> recordTopicTimings(int topicId,
      {required Map<int, int> postTimingsMs, required int topicTimeMs}) async {}

  @override
  Future<TopicPreview> fetchTopicPreview(int id) async {
    final post = _details[id]?.firstPost;
    return post == null
        ? const TopicPreview(text: '暂无摘要', images: [])
        : HtmlText.topicPreview(post.cooked);
  }

  @override
  Future<ForumSearchResult> searchForum(String query,
      {ForumSearchMode mode = ForumSearchMode.posts,
      ForumSearchSort sort = ForumSearchSort.relevance}) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const ForumSearchResult(posts: [], topics: [], users: []);
    }
    if (mode == ForumSearchMode.users) {
      return ForumSearchResult(
        posts: const [],
        topics: const [],
        users: users.values
            .where((user) => user.username.toLowerCase().contains(normalized))
            .map((user) => SearchUserResult(user: user))
            .toList(growable: false),
      );
    }
    final topics = _topics
        .where((topic) => topic.title.toLowerCase().contains(normalized))
        .toList(growable: false);
    return ForumSearchResult(posts: const [], topics: topics, users: const []);
  }

  @override
  Future<UserProfile> fetchUserProfile(String username,
      {bool forceRefresh = false}) async {
    final user = users.values
        .where((item) => item.username.toLowerCase() == username.toLowerCase())
        .firstOrNull;
    return user == null
        ? UserProfile(
            user: DiscourseUser(id: 0, username: username, avatarTemplate: ''))
        : UserProfile(user: user);
  }

  @override
  Future<UserProfile> fetchCurrentUserProfile(
          {bool forceRefresh = false}) async =>
      profile;

  @override
  Future<UserSummary> fetchUserSummary(String username,
          {bool forceRefresh = false}) async =>
      username.toLowerCase() == profile.username.toLowerCase()
          ? userSummary
          : const UserSummary(
              likesGiven: 0,
              likesReceived: 0,
              topicsEntered: 0,
              postsReadCount: 0,
              daysVisited: 0,
              topicCount: 0,
              postCount: 0,
              timeReadSeconds: 0);

  @override
  Future<ForumActivityCounts> fetchActivityCounts(
          {bool forceRefresh = false}) async =>
      ForumActivityCounts(
          topics: _topics
              .where((item) => item.originalPosterId == profile.id)
              .length,
          read: _topics.length,
          bookmarks: _bookmarkedTopicIds.length);

  @override
  Future<List<ForumActivityItem>> fetchUserActivity(ForumActivityKind kind,
      {bool forceRefresh = false}) async {
    final topics = switch (kind) {
      ForumActivityKind.topics =>
        _topics.where((item) => item.originalPosterId == profile.id),
      ForumActivityKind.read => _topics,
      ForumActivityKind.bookmarks =>
        _topics.where((item) => _bookmarkedTopicIds.contains(item.id)),
    };
    return topics.map(ForumActivityItem.fromTopic).toList(growable: false);
  }

  @override
  Future<List<ForumActivityItem>> fetchTopicsCreatedBy(String username,
          {bool forceRefresh = false}) async =>
      (await fetchUserActivity(ForumActivityKind.topics))
          .where((item) =>
              username.toLowerCase() == profile.username.toLowerCase())
          .toList(growable: false);

  @override
  Future<ForumBookmark?> findTopicBookmark(int topicId,
          {bool forceRefresh = false}) async =>
      _bookmarkedTopicIds.contains(topicId)
          ? ForumBookmark(id: topicId, topicId: topicId)
          : null;

  @override
  Future<Post> createTopic(CreateTopicDraft draft) async {
    final now = DateTime.now();
    final topicId = _nextTopicId++;
    final post =
        _post(topicId: topicId, postNumber: 1, raw: draft.raw, now: now);
    _details[topicId] = TopicDetail(
        id: topicId,
        title: draft.title,
        categoryId: draft.categoryId,
        postsCount: 1,
        highestPostNumber: 1,
        canCreatePost: true,
        canDelete: true,
        posts: [post],
        postStreamIds: [post.id]);
    _topics.insert(
        0,
        TopicListItem(
            id: topicId,
            title: draft.title,
            postsCount: 1,
            replyCount: 0,
            highestPostNumber: 1,
            views: 0,
            likeCount: 0,
            categoryId: draft.categoryId,
            posters: [TopicPoster(userId: profile.id, description: '原始发帖人')],
            createdAt: now,
            lastPostedAt: now));
    return post;
  }

  @override
  Future<UploadedImage> uploadImage(PickedImage image) =>
      _unsupported('演示模式不支持上传图片');

  @override
  Future<ProfileImageUpload> uploadProfileImage(
          PickedImage image, ProfileImageUploadType type) =>
      _unsupported('演示模式不支持上传图片');

  @override
  Future<UserProfile> updateProfileSettings(ProfileSettingsDraft draft) async =>
      profile;

  @override
  Future<UserProfile> useSystemAvatar() async => profile;

  @override
  Future<UserProfile> useCustomAvatar(int uploadId) async => profile;

  @override
  Future<Post> createReply(ReplyDraft draft) async {
    final detail = _details[draft.topicId];
    if (detail == null) throw const ForumApiException('主题不存在');
    final now = DateTime.now();
    final post = _post(
        topicId: draft.topicId,
        postNumber: detail.highestPostNumber + 1,
        raw: draft.raw,
        now: now,
        replyToPostNumber: draft.replyToPostNumber);
    _details[draft.topicId] =
        detail.mergedWithPosts([post]).copyWith(canDelete: detail.canDelete);
    _updateTopic(draft.topicId,
        postsCount: detail.postsCount + 1,
        highestPostNumber: post.postNumber,
        lastPostedAt: now);
    return post;
  }

  @override
  Future<List<TopicListItem>> fetchPrivateMessages(
          {bool forceRefresh = false}) async =>
      List.unmodifiable(_privateMessages);

  @override
  Future<Post> createPrivateMessage(PrivateMessageDraft draft) async {
    final now = DateTime.now();
    final topicId = _nextTopicId++;
    final post =
        _post(topicId: topicId, postNumber: 1, raw: draft.raw, now: now);
    _details[topicId] = TopicDetail(
        id: topicId,
        title: draft.title,
        categoryId: 0,
        postsCount: 1,
        highestPostNumber: 1,
        canCreatePost: true,
        canDelete: true,
        archetype: 'private_message',
        posts: [post],
        postStreamIds: [post.id]);
    _privateMessages.insert(
        0,
        TopicListItem(
            id: topicId,
            title: draft.title,
            postsCount: 1,
            replyCount: 0,
            highestPostNumber: 1,
            views: 0,
            likeCount: 0,
            categoryId: 0,
            archetype: 'private_message',
            posters: [TopicPoster(userId: profile.id, description: '收件人')],
            createdAt: now,
            lastPostedAt: now));
    return post;
  }

  @override
  Future<List<ForumNotification>> fetchNotifications(
      NotificationFeedFilter filter,
      {bool forceRefresh = false}) async {
    if (filter == NotificationFeedFilter.all) {
      return List.unmodifiable(_notifications);
    }
    final kind = switch (filter) {
      NotificationFeedFilter.replies => '回复',
      NotificationFeedFilter.likes => '赞',
      NotificationFeedFilter.mentions => '提及',
      NotificationFeedFilter.all => ''
    };
    return _notifications
        .where((item) => item.kind == kind)
        .toList(growable: false);
  }

  @override
  Future<Post> likePost(int postId) async {
    if (!_likedPostIds.add(postId)) {
      return _setLike(postId, true, adjustCount: false) ??
          _post(topicId: 0, postNumber: 0, raw: '', now: DateTime.now());
    }
    return _setLike(postId, true) ??
        _post(topicId: 0, postNumber: 0, raw: '', now: DateTime.now());
  }

  @override
  Future<Post> unlikePost(int postId) async {
    if (!_likedPostIds.remove(postId)) {
      return _setLike(postId, false, adjustCount: false) ??
          _post(topicId: 0, postNumber: 0, raw: '', now: DateTime.now());
    }
    return _setLike(postId, false) ??
        _post(topicId: 0, postNumber: 0, raw: '', now: DateTime.now());
  }

  @override
  Future<ForumPollVoteResult> votePoll(
          {required int topicId,
          required int postId,
          required String pollName,
          required List<String> optionIds}) =>
      _unsupported('演示模式暂不支持投票');

  @override
  Future<ForumPoll> togglePollStatus(
          {required int topicId,
          required int postId,
          required String pollName,
          required String status}) =>
      _unsupported('演示模式暂不支持投票管理');

  @override
  Future<Post> reportContent(ForumReportDraft draft) =>
      _unsupported('演示模式暂不支持举报');

  @override
  Future<ForumBookmark> bookmarkTopic(int topicId) async {
    _bookmarkedTopicIds.add(topicId);
    return ForumBookmark(id: topicId, topicId: topicId);
  }

  @override
  Future<void> unbookmarkTopic(int bookmarkId) async =>
      _bookmarkedTopicIds.remove(bookmarkId);

  @override
  Future<void> deleteTopic(TopicListItem topic) async {
    _topics.removeWhere((item) => item.id == topic.id);
    _privateMessages.removeWhere((item) => item.id == topic.id);
    _details.remove(topic.id);
  }

  @override
  Future<void> deletePost(Post post) async {
    final detail = _details[post.topicId];
    if (detail == null) {
      return;
    }
    final posts = detail.posts
        .where((item) => item.id != post.id)
        .toList(growable: false);
    final streamIds = detail.postStreamIds
        .where((id) => id != post.id)
        .toList(growable: false);
    final highest = posts.isEmpty
        ? 0
        : posts.map((item) => item.postNumber).reduce(
              (a, b) => a > b ? a : b,
            );
    _details[post.topicId] = detail.copyWith(
      posts: posts,
      postStreamIds: streamIds,
      postsCount: posts.length,
      highestPostNumber: highest,
    );
    if (!detail.isPrivateMessage && posts.isNotEmpty) {
      _updateTopic(
        post.topicId,
        postsCount: posts.length,
        highestPostNumber: highest,
        lastPostedAt: posts.last.createdAt ?? DateTime.now(),
      );
    }
  }

  @override
  Future<void> forgetPrivateMessage(int topicId) async =>
      _privateMessages.removeWhere((item) => item.id == topicId);

  @override
  Future<void> clearLoginCookies() async {}

  @override
  Future<void> clearLocalAccount() async {}

  @override
  Future<int> forumCacheStorageSize() async => 0;

  @override
  Future<int> clearForumCache() async => 0;

  Post? _setLike(int postId, bool liked, {bool adjustCount = true}) {
    for (final entry in _details.entries) {
      final index = entry.value.posts.indexWhere((post) => post.id == postId);
      if (index < 0) continue;
      final old = entry.value.posts[index];
      final actions = old.actions.where((action) => action.id != 2).toList();
      final count = adjustCount
          ? (liked
              ? old.likeCount + 1
              : (old.likeCount > 0 ? old.likeCount - 1 : 0))
          : old.likeCount;
      actions.add(PostActionSummary(
          id: 2, count: count, acted: liked, canAct: !liked, canUndo: liked));
      final updated = Post(
          id: old.id,
          topicId: old.topicId,
          username: old.username,
          avatarTemplate: old.avatarTemplate,
          cooked: old.cooked,
          postNumber: old.postNumber,
          postUrl: old.postUrl,
          createdAt: old.createdAt,
          replyToPostNumber: old.replyToPostNumber,
          canDelete: old.canDelete,
          yours: old.yours,
          deletedAt: old.deletedAt,
          actions: actions,
          polls: old.polls);
      final posts = entry.value.posts.toList()..[index] = updated;
      final detail = entry.value;
      _details[entry.key] = TopicDetail(
          id: detail.id,
          title: detail.title,
          categoryId: detail.categoryId,
          postsCount: detail.postsCount,
          highestPostNumber: detail.highestPostNumber,
          canCreatePost: detail.canCreatePost,
          canDelete: detail.canDelete,
          posts: posts,
          postStreamIds: detail.postStreamIds,
          archetype: detail.archetype,
          slug: detail.slug);
      return updated;
    }
    return null;
  }

  Post _post(
      {required int topicId,
      required int postNumber,
      required String raw,
      required DateTime now,
      int? replyToPostNumber}) {
    final text = HtmlText.toPlainText(raw).trim();
    final cooked =
        '<p>${const HtmlEscape().convert(text.isEmpty ? '演示内容' : text).replaceAll('\n', '<br>')}</p>';
    return Post(
        id: _nextPostId++,
        topicId: topicId,
        username: profile.username,
        avatarTemplate: profile.user.avatarTemplate,
        cooked: cooked,
        postNumber: postNumber,
        postUrl: '/t/$topicId/$postNumber',
        createdAt: now,
        replyToPostNumber: replyToPostNumber,
        canDelete: true,
        yours: true,
        actions: const []);
  }

  void _updateTopic(int id,
      {required int postsCount,
      required int highestPostNumber,
      required DateTime lastPostedAt}) {
    for (var i = 0; i < _topics.length; i++) {
      final item = _topics[i];
      if (item.id != id) continue;
      _topics[i] = TopicListItem(
          id: item.id,
          title: item.title,
          postsCount: postsCount,
          replyCount: postsCount - 1,
          highestPostNumber: highestPostNumber,
          views: item.views,
          likeCount: item.likeCount,
          categoryId: item.categoryId,
          posters: item.posters,
          participants: item.participants,
          archetype: item.archetype,
          createdAt: item.createdAt,
          lastPostedAt: lastPostedAt);
    }
  }

  static TopicDetail _demoDetail(TopicDetail detail) {
    final posts = detail.posts
        .map((post) => Post(
            id: post.id,
            topicId: post.topicId,
            username: post.username,
            avatarTemplate: post.avatarTemplate,
            cooked: post.cooked,
            postNumber: post.postNumber,
            postUrl: post.postUrl,
            createdAt: post.createdAt,
            replyToPostNumber: post.replyToPostNumber,
            canDelete: post.yours,
            yours: post.yours,
            deletedAt: post.deletedAt,
            actions: post.actions,
            polls: post.polls))
        .toList(growable: false);
    return TopicDetail(
        id: detail.id,
        title: detail.title,
        categoryId: detail.categoryId,
        postsCount: detail.postsCount,
        highestPostNumber: detail.highestPostNumber,
        canCreatePost: true,
        canDelete: true,
        posts: posts,
        postStreamIds: detail.postStreamIds,
        archetype: detail.archetype,
        slug: detail.slug);
  }

  static Future<JsonMap> _json(AssetBundle bundle, String path) async =>
      jsonDecode(await bundle.loadString(path)) as JsonMap;

  static Map<int, DiscourseUser> _parseUsers(JsonMap json) {
    final raw = json['users'];
    if (raw is! List) return {};
    return {
      for (final user in raw.whereType<JsonMap>().map(DiscourseUser.fromJson))
        user.id: user
    };
  }

  static List<TopicListItem> _parseTopics(JsonMap json) {
    final list = json['topic_list'];
    final topics = list is JsonMap ? list['topics'] : null;
    if (topics is! List) return [];
    return topics
        .whereType<JsonMap>()
        .map(TopicListItem.fromJson)
        .toList(growable: true);
  }

  static Map<int, ForumCategory> _parseCategories(JsonMap json) {
    final list = json['category_list'];
    final categories =
        list is JsonMap ? list['categories'] : json['categories'];
    if (categories is! List) return {};
    return {
      for (final item
          in categories.whereType<JsonMap>().map(ForumCategory.fromJson))
        item.id: item
    };
  }

  static List<ForumCategory> _sortedCategories(Map<int, ForumCategory> values) {
    final list = values.values.toList()
      ..sort((a, b) => a.position == b.position
          ? a.id.compareTo(b.id)
          : a.position.compareTo(b.position));
    return list;
  }

  Future<T> _unsupported<T>(String message) =>
      Future<T>.error(ForumApiException(message));
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
