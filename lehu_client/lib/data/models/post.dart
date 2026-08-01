import '../../core/forum_url_resolver.dart';
import 'common.dart';
import 'forum_poll.dart';

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
  static const reportActionIds = {3, 4, 7, 8, 10};

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
    this.polls = const [],
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
  final List<ForumPoll> polls;

  factory Post.fromJson(JsonMap json) {
    final actionsJson = json['actions_summary'];
    final pollsVotes = _pollsVotes(json['polls_votes']);
    final pollsJson = json['polls'];
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
      polls: pollsJson is List
          ? pollsJson
              .whereType<JsonMap>()
              .map((poll) => ForumPoll.fromJson(
                    poll,
                    ownVotes: pollsVotes[stringValue(poll['name'])] ?? const [],
                  ))
              .toList()
          : const [],
    );
  }

  static Map<String, List<String>> _pollsVotes(Object? value) {
    if (value is! JsonMap) {
      return const {};
    }
    return {
      for (final entry in value.entries)
        entry.key: entry.value is List
            ? (entry.value as List)
                .map((item) => item.toString())
                .toList(growable: false)
            : const <String>[],
    };
  }

  String avatarUrl({int size = 96}) {
    final resolved = avatarTemplate.replaceAll('{size}', '$size');
    return ForumUrlResolver.resolve(resolved);
  }

  int get likeCount {
    return actions
        .where((action) => action.id == 2)
        .fold(0, (sum, action) => sum + action.count);
  }

  bool get liked {
    return actions.any((action) => action.id == 2 && action.acted);
  }

  bool get reported {
    return actions.any(
      (action) => reportActionIds.contains(action.id) && action.acted,
    );
  }

  bool get isDeleted => deletedAt != null;
}
