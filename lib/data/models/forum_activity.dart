import 'common.dart';
import 'topic.dart';
import '../services/emoji_text.dart';
import '../services/html_text.dart';

enum ForumActivityKind {
  topics,
  read,
  bookmarks;

  String get title {
    return switch (this) {
      ForumActivityKind.topics => '话题',
      ForumActivityKind.read => '浏览',
      ForumActivityKind.bookmarks => '收藏',
    };
  }

  String get emptyTitle {
    return switch (this) {
      ForumActivityKind.topics => '还没有发布话题',
      ForumActivityKind.read => '还没有浏览记录',
      ForumActivityKind.bookmarks => '还没有收藏',
    };
  }
}

class ForumActivityCounts {
  const ForumActivityCounts({
    required this.topics,
    required this.read,
    required this.bookmarks,
  });

  final int topics;
  final int read;
  final int bookmarks;

  int valueFor(ForumActivityKind kind) {
    return switch (kind) {
      ForumActivityKind.topics => topics,
      ForumActivityKind.read => read,
      ForumActivityKind.bookmarks => bookmarks,
    };
  }
}

class ForumActivityItem {
  const ForumActivityItem({
    required this.topicId,
    required this.title,
    required this.categoryId,
    required this.views,
    required this.replyCount,
    required this.postsCount,
    required this.highestPostNumber,
    required this.showTopicStats,
    this.excerpt = '',
    this.bookmarkId,
    this.linkedPostNumber,
    this.archetype = 'regular',
    this.createdAt,
    this.lastPostedAt,
  });

  final int topicId;
  final String title;
  final int categoryId;
  final int views;
  final int replyCount;
  final int postsCount;
  final int highestPostNumber;
  final bool showTopicStats;
  final String excerpt;
  final int? bookmarkId;
  final int? linkedPostNumber;
  final String archetype;
  final DateTime? createdAt;
  final DateTime? lastPostedAt;

  factory ForumActivityItem.fromTopic(TopicListItem topic) {
    return ForumActivityItem(
      topicId: topic.id,
      title: topic.title,
      categoryId: topic.categoryId,
      views: topic.views,
      replyCount: topic.replyCount,
      postsCount: topic.postsCount,
      highestPostNumber: topic.highestPostNumber,
      showTopicStats: true,
      archetype: topic.archetype,
      createdAt: topic.createdAt,
      lastPostedAt: topic.lastPostedAt,
    );
  }

  factory ForumActivityItem.fromBookmark(JsonMap json) {
    final bookmarkableType = stringValue(json['bookmarkable_type']);
    final bookmarkableId = intValue(json['bookmarkable_id']);
    final rawExcerpt = stringValue(json['excerpt']);
    final topicId = intValue(
      json['topic_id'],
      bookmarkableType == 'Topic' ? bookmarkableId : 0,
    );
    final postsCount = intValue(json['posts_count'], 1);
    return ForumActivityItem(
      topicId: topicId,
      title: EmojiText.render(stringValue(json['title'], '未命名话题')),
      categoryId: intValue(json['category_id']),
      views: 0,
      replyCount: postsCount > 0 ? postsCount - 1 : 0,
      postsCount: postsCount,
      highestPostNumber: intValue(json['highest_post_number'], 1),
      showTopicStats: false,
      excerpt: rawExcerpt.isEmpty ? '' : HtmlText.preview(rawExcerpt),
      bookmarkId: intValue(json['id']),
      linkedPostNumber: intValue(json['linked_post_number']),
      archetype: stringValue(json['archetype'], 'regular'),
      createdAt: dateValue(json['created_at']),
      lastPostedAt: dateValue(json['bumped_at']),
    );
  }

  TopicListItem toTopicListItem() {
    return TopicListItem(
      id: topicId,
      title: title,
      postsCount: postsCount,
      replyCount: replyCount,
      highestPostNumber: highestPostNumber,
      views: views,
      likeCount: 0,
      categoryId: categoryId,
      archetype: archetype,
      createdAt: createdAt,
      lastPostedAt: lastPostedAt,
      posters: const [],
    );
  }
}

class ForumBookmark {
  const ForumBookmark({
    required this.id,
    required this.topicId,
  });

  final int id;
  final int topicId;
}
