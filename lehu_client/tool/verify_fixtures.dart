import 'dart:convert';
import 'dart:io';

import 'package:shuyo/data/models/category.dart';
import 'package:shuyo/data/models/common.dart';
import 'package:shuyo/data/models/topic.dart';
import 'package:shuyo/data/models/topic_detail.dart';
import 'package:shuyo/data/services/html_text.dart';
import 'package:shuyo/data/services/payload_factory.dart';

void main() {
  final latest = _fixture('assets/fixtures/api/latest/latest.json');
  final hot = _fixture('assets/fixtures/api/hot/hot.json');
  final site = _fixture('assets/fixtures/api/site.json');
  final imageTopic = TopicDetail.fromJson(
      _fixture('assets/fixtures/api/topic/topic-image.json'));
  final longTopic = TopicDetail.fromJson(
      _fixture('assets/fixtures/api/topic/topic-long.json'));

  final latestTopics = _topics(latest);
  final hotTopics = _topics(hot);
  final categories = (site['categories'] as List)
      .whereType<JsonMap>()
      .map(ForumCategory.fromJson)
      .toList();

  _expect(latestTopics.isNotEmpty, 'latest topics should not be empty');
  _expect(hotTopics.isNotEmpty, 'hot topics should not be empty');
  _expect(
      categories
          .any((category) => category.id == latestTopics.first.categoryId),
      'first latest topic should have a category');
  _expect(imageTopic.posts.isNotEmpty, 'image topic should contain posts');
  _expect(longTopic.posts.length >= 20, 'long topic should contain many posts');
  _expect(HtmlText.preview(imageTopic.firstPost!.cooked).isNotEmpty,
      'preview should not be empty');

  final reply = PayloadFactory.createReply(
    const ReplyDraft(
      topicId: 478,
      categoryId: 4,
      raw: 'test test',
      replyToPostNumber: 3,
    ),
  );
  final like = PayloadFactory.likePost(654);

  _expect(reply.body.contains('reply_to_post_number=3'),
      'reply payload should target a post');
  _expect(PayloadFactory.decodeForm(reply.body)['raw'] == 'test test',
      'reply raw should decode');
  _expect(like.body == 'id=654&post_action_type_id=2&flag_topic=false',
      'like payload should match capture');

  stdout.writeln(
      'Fixtures verified: ${latestTopics.length} latest, ${hotTopics.length} hot, '
      '${categories.length} categories.');
}

List<TopicListItem> _topics(JsonMap json) {
  final list = json['topic_list'] as JsonMap;
  return (list['topics'] as List)
      .whereType<JsonMap>()
      .map(TopicListItem.fromJson)
      .toList();
}

JsonMap _fixture(String path) {
  return jsonDecode(File(path).readAsStringSync()) as JsonMap;
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
