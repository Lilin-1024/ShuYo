import '../../core/forum_constants.dart';
import 'common.dart';

class PostActionSummary {
  const PostActionSummary({
    required this.id,
    this.count = 0,
    this.acted = false,
    this.canAct = false,
    this.canUndo = false,
  });

  final int id;
  final int count;
  final bool acted;
  final bool canAct;
  final bool canUndo;

  factory PostActionSummary.fromJson(JsonMap json) {
    return PostActionSummary(
      id: intValue(json['id']),
      count: intValue(json['count']),
      acted: boolValue(json['acted']),
      canAct: boolValue(json['can_act']),
      canUndo: boolValue(json['can_undo']),
    );
  }
}

class Post {
  const Post({
    required this.id,
    required this.topicId,
    required this.username,
    required this.avatarTemplate,
    required this.cooked,
    required this.postNumber,
    required this.postUrl,
    required this.actions,
    this.createdAt,
    this.replyToPostNumber,
    this.canDelete = false,
    this.yours = false,
    this.deletedAt,
  });

  final int id;
  final int topicId;
  final String username;
  final String avatarTemplate;
  final String cooked;
  final int postNumber;
  final String postUrl;
  final DateTime? createdAt;
  final int? replyToPostNumber;
  final bool canDelete;
  final bool yours;
  final DateTime? deletedAt;
  final List<PostActionSummary> actions;

  factory Post.fromJson(JsonMap json) {
    final actionsJson = json['actions_summary'];
    return Post(
      id: intValue(json['id']),
      topicId: intValue(json['topic_id']),
      username: stringValue(json['username']),
      avatarTemplate: stringValue(json['avatar_template']),
      cooked: stringValue(json['cooked']),
      postNumber: intValue(json['post_number']),
      postUrl: stringValue(json['post_url']),
      createdAt: dateValue(json['created_at']),
      replyToPostNumber: json['reply_to_post_number'] == null
          ? null
          : intValue(json['reply_to_post_number']),
      canDelete: boolValue(json['can_delete']),
      yours: boolValue(json['yours']),
      deletedAt: dateValue(json['deleted_at']),
      actions: actionsJson is List
          ? actionsJson
              .whereType<JsonMap>()
              .map(PostActionSummary.fromJson)
              .toList()
          : const [],
    );
  }

  String avatarUrl({int size = 96}) {
    final resolved = avatarTemplate.replaceAll('{size}', '$size');
    if (resolved.startsWith('http')) {
      return resolved;
    }
    return '${ForumConstants.baseUrl}$resolved';
  }

  int get likeCount {
    return actions
        .where((action) => action.id == 2)
        .fold(0, (sum, action) => sum + action.count);
  }

  bool get liked {
    return actions.any((action) => action.id == 2 && action.acted);
  }

  bool get isDeleted => deletedAt != null;
}
