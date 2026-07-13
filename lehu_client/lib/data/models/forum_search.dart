import 'common.dart';
import 'discourse_user.dart';
import 'topic.dart';

enum ForumSearchMode { posts, users }

enum ForumSearchSort { relevance, latest, likes, views }

extension ForumSearchSortLabel on ForumSearchSort {
  String get label {
    return switch (this) {
      ForumSearchSort.relevance => '相关性',
      ForumSearchSort.latest => '最新',
      ForumSearchSort.likes => '赞最多',
      ForumSearchSort.views => '浏览最多',
    };
  }

  String get querySuffix {
    return switch (this) {
      ForumSearchSort.relevance => '',
      ForumSearchSort.latest => 'order:latest',
      ForumSearchSort.likes => 'order:likes',
      ForumSearchSort.views => 'order:views',
    };
  }
}

class SearchPostResult {
  const SearchPostResult({
    required this.id,
    required this.topicId,
    required this.postNumber,
    required this.username,
    required this.avatarTemplate,
    required this.blurb,
    required this.likeCount,
    this.createdAt,
  });

  final int id;
  final int topicId;
  final int postNumber;
  final String username;
  final String avatarTemplate;
  final String blurb;
  final int likeCount;
  final DateTime? createdAt;

  factory SearchPostResult.fromJson(JsonMap json) {
    return SearchPostResult(
      id: intValue(json['id']),
      topicId: intValue(json['topic_id']),
      postNumber: intValue(json['post_number']),
      username: stringValue(json['username']),
      avatarTemplate: stringValue(json['avatar_template']),
      blurb: stringValue(json['blurb']),
      likeCount: intValue(json['like_count']),
      createdAt: dateValue(json['created_at']),
    );
  }
}

class SearchUserResult {
  const SearchUserResult({required this.user});

  final DiscourseUser user;

  int get id => user.id;
  String get username => user.username;
  String avatarUrl({int size = 96}) => user.avatarUrl(size: size);

  factory SearchUserResult.fromJson(JsonMap json) {
    return SearchUserResult(user: DiscourseUser.fromJson(json));
  }
}

class ForumSearchResult {
  const ForumSearchResult({
    required this.posts,
    required this.topics,
    this.users = const [],
  });

  final List<SearchPostResult> posts;
  final List<TopicListItem> topics;
  final List<SearchUserResult> users;

  TopicListItem? topicForPost(SearchPostResult post) {
    for (final topic in topics) {
      if (topic.id == post.topicId) {
        return topic;
      }
    }
    return null;
  }

  factory ForumSearchResult.fromJson(JsonMap json) {
    final postsJson = json['posts'];
    final topicsJson = json['topics'];
    final usersJson = json['users'];
    return ForumSearchResult(
      posts: postsJson is List
          ? postsJson
              .whereType<JsonMap>()
              .map(SearchPostResult.fromJson)
              .toList()
          : const [],
      topics: topicsJson is List
          ? topicsJson.whereType<JsonMap>().map(TopicListItem.fromJson).toList()
          : const [],
      users: usersJson is List
          ? usersJson
              .whereType<JsonMap>()
              .map(SearchUserResult.fromJson)
              .toList()
          : const [],
    );
  }
}
