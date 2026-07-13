import 'common.dart';
import 'post.dart';
import '../services/emoji_text.dart';

class TopicDetail {
  const TopicDetail({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.postsCount,
    required this.highestPostNumber,
    required this.canCreatePost,
    required this.posts,
    this.postStreamIds = const [],
    this.archetype = 'regular',
    this.slug = 'topic',
  });

  final int id;
  final String title;
  final int categoryId;
  final int postsCount;
  final int highestPostNumber;
  final bool canCreatePost;
  final List<Post> posts;
  final List<int> postStreamIds;
  final String archetype;
  final String slug;

  bool get isPrivateMessage => archetype == 'private_message';

  factory TopicDetail.fromJson(JsonMap json) {
    final stream = json['post_stream'];
    final postsJson = stream is JsonMap ? stream['posts'] : null;
    final streamJson = stream is JsonMap ? stream['stream'] : null;
    final details = json['details'];
    return TopicDetail(
      id: intValue(json['id']),
      title: EmojiText.render(stringValue(json['title'])),
      categoryId: intValue(json['category_id']),
      postsCount: intValue(json['posts_count']),
      highestPostNumber: intValue(json['highest_post_number']),
      archetype: stringValue(json['archetype'], 'regular'),
      slug: stringValue(json['slug'], 'topic'),
      canCreatePost:
          details is JsonMap ? boolValue(details['can_create_post']) : false,
      posts: postsJson is List
          ? postsJson.whereType<JsonMap>().map(Post.fromJson).toList()
          : const [],
      postStreamIds: streamJson is List
          ? streamJson.map(intValue).where((id) => id > 0).toList()
          : const [],
    );
  }

  Post? get firstPost => posts.isEmpty ? null : posts.first;

  TopicDetail copyWith({
    int? postsCount,
    int? highestPostNumber,
    List<Post>? posts,
    List<int>? postStreamIds,
  }) {
    return TopicDetail(
      id: id,
      title: title,
      categoryId: categoryId,
      postsCount: postsCount ?? this.postsCount,
      highestPostNumber: highestPostNumber ?? this.highestPostNumber,
      canCreatePost: canCreatePost,
      posts: posts ?? this.posts,
      postStreamIds: postStreamIds ?? this.postStreamIds,
      archetype: archetype,
      slug: slug,
    );
  }

  TopicDetail mergedWithPosts(Iterable<Post> incomingPosts) {
    final byId = <int, Post>{
      for (final post in posts) post.id: post,
    };
    for (final post in incomingPosts) {
      if (post.id > 0) {
        byId[post.id] = post;
      }
    }
    final mergedPosts = byId.values.toList()
      ..sort((a, b) => a.postNumber.compareTo(b.postNumber));
    final mergedStreamIds = [
      ...postStreamIds,
      for (final post in mergedPosts)
        if (!postStreamIds.contains(post.id)) post.id,
    ];
    final highest = mergedPosts.fold<int>(
      highestPostNumber,
      (value, post) => post.postNumber > value ? post.postNumber : value,
    );
    final count = [postsCount, mergedPosts.length, highest].reduce(
      (value, element) => value > element ? value : element,
    );
    return copyWith(
      posts: mergedPosts,
      postStreamIds: mergedStreamIds,
      postsCount: count,
      highestPostNumber: highest,
    );
  }
}
