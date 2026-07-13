import 'common.dart';
import 'post.dart';

class TopicDetail {
  const TopicDetail({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.postsCount,
    required this.highestPostNumber,
    required this.canCreatePost,
    required this.posts,
    this.archetype = 'regular',
  });

  final int id;
  final String title;
  final int categoryId;
  final int postsCount;
  final int highestPostNumber;
  final bool canCreatePost;
  final List<Post> posts;
  final String archetype;

  bool get isPrivateMessage => archetype == 'private_message';

  factory TopicDetail.fromJson(JsonMap json) {
    final stream = json['post_stream'];
    final postsJson = stream is JsonMap ? stream['posts'] : null;
    final details = json['details'];
    return TopicDetail(
      id: intValue(json['id']),
      title: stringValue(json['title']),
      categoryId: intValue(json['category_id']),
      postsCount: intValue(json['posts_count']),
      highestPostNumber: intValue(json['highest_post_number']),
      archetype: stringValue(json['archetype'], 'regular'),
      canCreatePost:
          details is JsonMap ? boolValue(details['can_create_post']) : false,
      posts: postsJson is List
          ? postsJson.whereType<JsonMap>().map(Post.fromJson).toList()
          : const [],
    );
  }

  Post? get firstPost => posts.isEmpty ? null : posts.first;
}
