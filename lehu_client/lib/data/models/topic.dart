import 'common.dart';
import '../services/emoji_text.dart';

class TopicPoster {
  const TopicPoster({required this.userId, required this.description});

  final int userId;
  final String description;

  factory TopicPoster.fromJson(JsonMap json) {
    return TopicPoster(
      userId: intValue(json['user_id']),
      description: stringValue(json['description']),
    );
  }
}

class TopicListItem {
  const TopicListItem({
    required this.id,
    required this.title,
    required this.postsCount,
    required this.replyCount,
    required this.highestPostNumber,
    required this.views,
    required this.likeCount,
    required this.categoryId,
    required this.posters,
    this.participants = const [],
    this.imageUrl,
    this.archetype = 'regular',
    this.allowedUserCount = 0,
    this.createdAt,
    this.lastPostedAt,
  });

  final int id;
  final String title;
  final int postsCount;
  final int replyCount;
  final int highestPostNumber;
  final int views;
  final int likeCount;
  final int categoryId;
  final String? imageUrl;
  final String archetype;
  final int allowedUserCount;
  final DateTime? createdAt;
  final DateTime? lastPostedAt;
  final List<TopicPoster> posters;
  final List<TopicPoster> participants;

  int? get originalPosterId => posters.isEmpty ? null : posters.first.userId;
  bool get isPrivateMessage => archetype == 'private_message';

  factory TopicListItem.fromJson(JsonMap json) {
    final postersJson = json['posters'];
    final participantsJson = json['participants'];
    final postsCount = intValue(json['posts_count']);
    return TopicListItem(
      id: intValue(json['id']),
      title: EmojiText.render(stringValue(json['title'])),
      postsCount: postsCount,
      replyCount: postsCount > 0 ? postsCount - 1 : 0,
      highestPostNumber: intValue(json['highest_post_number']),
      views: intValue(json['views']),
      likeCount: intValue(json['like_count']),
      categoryId: intValue(json['category_id']),
      imageUrl: json['image_url'] as String?,
      archetype: stringValue(json['archetype'], 'regular'),
      allowedUserCount: intValue(json['allowed_user_count']),
      createdAt: dateValue(json['created_at']),
      lastPostedAt: dateValue(json['last_posted_at']),
      posters: postersJson is List
          ? postersJson.whereType<JsonMap>().map(TopicPoster.fromJson).toList()
          : const [],
      participants: participantsJson is List
          ? participantsJson
              .whereType<JsonMap>()
              .map(TopicPoster.fromJson)
              .toList()
          : const [],
    );
  }
}
