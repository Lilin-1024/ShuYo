import 'common.dart';
import '../services/emoji_text.dart';
import '../services/html_text.dart';

enum NotificationFeedFilter { all, replies, likes, mentions }

class ForumNotification {
  const ForumNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.kind,
    required this.read,
    this.categoryId = 0,
    this.topicId,
    this.postNumber,
    this.createdAt,
  });

  final int id;
  final String title;
  final String message;
  final String kind;
  final bool read;
  final int categoryId;
  final int? topicId;
  final int? postNumber;
  final DateTime? createdAt;

  bool get canOpenTopic => topicId != null && topicId! > 0;

  bool get isClientVisible {
    return canOpenTopic && _clientVisibleKinds.contains(kind);
  }

  static bool isSupportedNotificationJson(JsonMap json) {
    final type = intValue(json['notification_type']);
    return _clientVisibleNotificationTypes.contains(type);
  }

  factory ForumNotification.fromNotificationJson(JsonMap json) {
    final data = json['data'];
    final map = data is JsonMap ? data : const <String, dynamic>{};
    final type = intValue(json['notification_type']);
    final actor = stringValue(
      map['display_username'] ?? map['username'] ?? map['original_username'],
    );
    final title = stringValue(
      json['fancy_title'] ?? map['topic_title'] ?? map['badge_name'],
      '通知',
    );
    return ForumNotification(
      id: intValue(json['id']),
      title: EmojiText.render(title),
      message: EmojiText.render(_messageForNotification(type, actor, map)),
      kind: _kindForNotification(type),
      read: boolValue(json['read']),
      categoryId: intValue(json['category_id'] ?? map['category_id']),
      topicId: _nullableInt(json['topic_id']),
      postNumber: _nullableInt(json['post_number']),
      createdAt: dateValue(json['created_at']),
    );
  }

  factory ForumNotification.fromUserActionJson(JsonMap json, String kind) {
    final excerpt = HtmlText.toPlainText(stringValue(json['excerpt']));
    final topicTitle = stringValue(json['title'], '通知');
    final actor = stringValue(json['acting_username']);
    final isLike = kind == '赞';
    final title = isLike && actor.isNotEmpty ? actor : topicTitle;
    final message = isLike
        ? (excerpt.isEmpty ? '点赞了你的内容' : excerpt)
        : (excerpt.isEmpty ? kind : excerpt);
    return ForumNotification(
      id: intValue(json['id'] ?? json['post_id']),
      title: EmojiText.render(title),
      message: message,
      kind: kind,
      read: true,
      categoryId: intValue(json['category_id']),
      topicId: _nullableInt(json['topic_id']),
      postNumber: _nullableInt(json['post_number']),
      createdAt: dateValue(json['created_at']),
    );
  }

  static String _messageForNotification(
    int type,
    String actor,
    JsonMap data,
  ) {
    if (type == 12) {
      return '获得徽章 ${stringValue(data['badge_name'], '新徽章')}';
    }
    if (actor.isEmpty) {
      return _kindForNotification(type);
    }
    return '$actor · ${_kindForNotification(type)}';
  }

  static String _kindForNotification(int type) {
    return switch (type) {
      1 => '提及',
      2 => '回复',
      5 => '赞',
      6 => '回复',
      9 => '引用',
      12 => '徽章',
      _ => '通知',
    };
  }

  static const _clientVisibleNotificationTypes = <int>{1, 2, 5, 6, 9};
  static const _clientVisibleKinds = <String>{'提及', '回复', '赞', '引用'};

  static int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    final parsed = intValue(value);
    return parsed == 0 ? null : parsed;
  }
}
