import 'common.dart';
import 'topic.dart';

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

class ForumSearchResult {
  const ForumSearchResult({
    required this.posts,
    required this.topics,
  });

  final List<SearchPostResult> posts;
  final List<TopicListItem> topics;

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
    );
  }
}
