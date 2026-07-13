import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lehu_client/data/models/category.dart';
import 'package:lehu_client/data/models/common.dart';
import 'package:lehu_client/data/models/post.dart';
import 'package:lehu_client/data/models/topic.dart';
import 'package:lehu_client/data/models/topic_detail.dart';
import 'package:lehu_client/data/services/html_text.dart';
import 'package:lehu_client/data/services/payload_factory.dart';
import 'package:lehu_client/features/topic/threaded_posts.dart';
import 'package:lehu_client/shared/time_format.dart';

void main() {
  test('parses latest topics and categories', () {
    final latest = _fixture('assets/fixtures/api/latest/latest.json');
    final site = _fixture('assets/fixtures/api/site.json');

    final topics = ((latest['topic_list'] as JsonMap)['topics'] as List)
        .whereType<JsonMap>()
        .map(TopicListItem.fromJson)
        .toList();
    final categories = (site['categories'] as List)
        .whereType<JsonMap>()
        .map(ForumCategory.fromJson)
        .toList();

    expect(topics, isNotEmpty);
    expect(categories.any((category) => category.id == topics.first.categoryId),
        isTrue);
  });

  test('parses topic detail and builds plain text preview', () {
    final topic = TopicDetail.fromJson(
        _fixture('assets/fixtures/api/topic/topic-image.json'));
    final preview = HtmlText.topicPreview(topic.firstPost!.cooked);

    expect(topic.id, 662);
    expect(topic.posts, isNotEmpty);
    expect(HtmlText.preview(topic.firstPost!.cooked), isNotEmpty);
    expect(preview.imageUrls, isNotEmpty);
    expect(preview.text, isEmpty);
    expect(preview.text, isNot(contains('1920')));
    expect(preview.text, isNot(contains('KB')));
  });

  test('builds reply and like payloads', () {
    final reply = PayloadFactory.createReply(
      const ReplyDraft(
        topicId: 478,
        categoryId: 4,
        raw: 'test test',
        replyToPostNumber: 3,
      ),
    );
    final like = PayloadFactory.likePost(654);

    expect(reply.method, 'POST');
    expect(reply.body, contains('reply_to_post_number=3'));
    expect(PayloadFactory.decodeForm(reply.body)['raw'], 'test test');
    expect(like.body, 'id=654&post_action_type_id=2&flag_topic=false');
  });

  test('builds delete payload from post id and post number context', () {
    final post = _post(id: 998, topicId: 94, postNumber: 10);
    final payload = PayloadFactory.deletePost(post);

    expect(payload.method, 'DELETE');
    expect(payload.url, endsWith('/posts/998'));
    expect(
      PayloadFactory.decodeForm(payload.body)['context'],
      '/t/topic/94/10',
    );
  });

  test('parses post ownership and delete capability', () {
    final post = Post.fromJson({
      'id': 998,
      'topic_id': 94,
      'username': 'me',
      'avatar_template': '/letter_avatar_proxy/v4/letter/m/{size}.png',
      'cooked': '<p>test</p>',
      'post_number': 10,
      'post_url': '/t/topic/94/10',
      'can_delete': true,
      'yours': true,
      'deleted_at': '2026-07-09T08:00:00.000Z',
      'actions_summary': [],
    });

    expect(post.canDelete, isTrue);
    expect(post.yours, isTrue);
    expect(post.isDeleted, isTrue);
  });

  test('groups replies into a single nested level', () {
    final threads = buildThreadedPosts([
      _post(postNumber: 1),
      _post(postNumber: 2),
      _post(postNumber: 3, replyToPostNumber: 2),
      _post(postNumber: 4, replyToPostNumber: 3),
      _post(postNumber: 5),
    ]);

    expect(threads.map((thread) => thread.post.postNumber), [1, 2, 5]);
    expect(
      threads[1].replies.map((post) => post.postNumber),
      [3, 4],
    );
  });

  test('formats forum times without labels', () {
    final now = DateTime(2026, 7, 9, 18, 48);

    expect(
      TimeFormat.compact(
        now.subtract(const Duration(seconds: 20)),
        now: now,
      ),
      '刚刚',
    );
    expect(
      TimeFormat.compact(
        now.subtract(const Duration(minutes: 12)),
        now: now,
      ),
      '12分钟前',
    );
    expect(TimeFormat.compact(DateTime(2026, 7, 9, 14, 5), now: now), '14:05');
    expect(
      TimeFormat.compact(DateTime(2026, 1, 2, 3, 4), now: now),
      '1/2 03:04',
    );
    expect(
      TimeFormat.compact(DateTime(2025, 12, 31, 23, 59), now: now),
      '2025/12/31 23:59',
    );
  });
}

JsonMap _fixture(String path) {
  return jsonDecode(File(path).readAsStringSync()) as JsonMap;
}

Post _post({
  int? id,
  int topicId = 1,
  required int postNumber,
  int? replyToPostNumber,
}) {
  return Post(
    id: id ?? postNumber,
    topicId: topicId,
    username: 'user$postNumber',
    avatarTemplate: '/letter_avatar_proxy/v4/letter/u/{size}.png',
    cooked: '<p>post $postNumber</p>',
    postNumber: postNumber,
    postUrl: '/t/topic/$topicId/$postNumber',
    replyToPostNumber: replyToPostNumber,
    actions: const [],
  );
}
