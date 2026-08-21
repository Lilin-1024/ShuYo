import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/models/academic_schedule.dart';
import 'package:shuyo/data/models/category.dart';
import 'package:shuyo/data/models/common.dart';
import 'package:shuyo/data/models/composer.dart';
import 'package:shuyo/data/models/forum_notification.dart';
import 'package:shuyo/data/models/forum_report.dart';
import 'package:shuyo/data/models/post.dart';
import 'package:shuyo/data/models/topic.dart';
import 'package:shuyo/data/models/topic_detail.dart';
import 'package:shuyo/data/models/user_profile.dart';
import 'package:shuyo/data/repositories/academic_schedule_repository.dart';
import 'package:shuyo/data/repositories/classroom_repository.dart';
import 'package:shuyo/data/services/announcement_api_client.dart';
import 'package:shuyo/data/services/classroom_api_client.dart';
import 'package:shuyo/data/services/course_rating_api_client.dart';
import 'package:shuyo/data/services/emoji_text.dart';
import 'package:shuyo/data/services/academic_schedule_widget_service.dart';
import 'package:shuyo/data/services/forum_draft_store.dart';
import 'package:shuyo/data/services/forum_persistent_cache.dart';
import 'package:shuyo/data/services/forum_read_position_store.dart';
import 'package:shuyo/data/services/forum_title_rules.dart';
import 'package:shuyo/data/services/html_text.dart';
import 'package:shuyo/data/services/payload_factory.dart';
import 'package:shuyo/data/services/sha1_hash.dart';
import 'package:shuyo/features/topic/threaded_posts.dart';
import 'package:shuyo/shared/time_format.dart';
import 'package:shuyo/shared/widgets/advanced_markdown_editor.dart';
import 'package:shuyo/shared/widgets/composer_attachments.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    expect(topic.postStreamIds, contains(topic.firstPost!.id));
    expect(HtmlText.preview(topic.firstPost!.cooked), isNotEmpty);
    expect(preview.imageUrls, isNotEmpty);
    expect(preview.images.first.width, greaterThan(0));
    expect(preview.images.first.height, greaterThan(0));
    expect(preview.images.first.aspectRatio, greaterThan(0));
    expect(preview.text, isEmpty);
    expect(preview.text, isNot(contains('1920')));
    expect(preview.text, isNot(contains('KB')));
  });

  test('renders discourse emoji aliases in cooked content', () {
    const cooked = '<p>:face_savouring_food: :raised_back_of_hand:</p>'
        '<p><img src="/images/emoji/twitter/heart.png" '
        'alt=":red_heart:" width="20" height="20"></p>';

    expect(
      HtmlText.toPlainText(cooked),
      contains('\u{1F60B} \u{1F91A}'),
    );
    expect(HtmlText.toPlainText(cooked), contains('\u{2764}\u{FE0F}'));
    expect(EmojiText.render(':face_savoring_food:'), '\u{1F60B}');
  });

  test('renders generated unicode emoji shortcodes', () {
    final rendered = EmojiText.render(
      ':melting_face: :flag_china: :cn: :person_medium_dark_skin_tone: '
      ':south_korea: :wave:t2:',
    );

    expect(rendered, contains('\u{1FAE0}'));
    expect(rendered, contains('\u{1F1E8}\u{1F1F3}'));
    expect(rendered, contains('\u{1F9D1}\u{1F3FE}'));
    expect(rendered, contains('\u{1F1F0}\u{1F1F7}'));
    expect(rendered, contains('\u{1F44B}\u{1F3FB}'));
    expect(EmojiText.render(':unknown_forum_emoji:'), ':unknown_forum_emoji:');
  });

  test('keeps code shortcodes literal while rendering surrounding emoji', () {
    const cooked = '<p><code>:south_korea:</code> :south_korea:</p>'
        '<pre>:south_korea:</pre>';
    final segments = HtmlText.parseSegments(cooked);

    expect(segments.first.runs.first.code, isTrue);
    expect(segments.first.runs.first.text, ':south_korea:');
    expect(segments.first.textValue, contains('\u{1F1F0}\u{1F1F7}'));
    expect(segments.last.textBlockKind, CookedTextBlockKind.codeBlock);
    expect(segments.last.textValue, ':south_korea:');
  });

  test('preserves server emoji images as inline cooked text runs', () {
    const cooked = '<p>before '
        '<img class="emoji" src="/images/emoji/twitter/south_korea.png" '
        'alt=":south_korea:" width="20" height="20"> after '
        '<img class="emoji" src="/uploads/default/custom-campus.png" '
        'alt=":custom_campus:" width="20" height="20"></p>';
    final segment = HtmlText.parseSegments(cooked).single;
    final emojiRuns = segment.runs.where((run) => run.isInlineEmoji).toList();

    expect(emojiRuns, hasLength(2));
    expect(emojiRuns.first.text, '\u{1F1F0}\u{1F1F7}');
    expect(emojiRuns.first.inlineEmojiUrl, contains('/images/emoji/'));
    expect(emojiRuns.last.text, ':custom_campus:');
    expect(emojiRuns.last.inlineEmojiUrl, contains('/uploads/default/'));
    expect(HtmlText.images(cooked), isEmpty);
  });

  test('sanitizes emoji from forum titles', () {
    const title = '标题\u{1F604}:thinking:\u{2764}\u{FE0F}'
        '1\u{FE0F}\u{20E3}ok';
    expect(ForumTitleRules.sanitize(title), '标题ok');
    expect(ForumTitleRules.containsDisallowedEmoji(title), isTrue);
    expect(ForumTitleRules.sanitize('标题123ok'), '标题123ok');
    expect(ForumTitleRules.containsDisallowedEmoji('标题123ok'), isFalse);
    expect(
      ForumTitleRules.sanitize('标题 :not_an_emoji: ok'),
      '标题 :not_an_emoji: ok',
    );

    const valueText = 'ab\u{1F604}cd';
    final value = TextEditingValue(
      text: valueText,
      selection: TextSelection.collapsed(offset: valueText.indexOf('c')),
    );
    final sanitized = ForumTitleRules.sanitizeEditingValue(value);
    expect(sanitized.text, 'abcd');
    expect(sanitized.selection.baseOffset, 2);
  });

  test('parses onebox and internal quote cooked segments', () {
    const oneboxCooked = '''
<aside class="onebox allowlistedgeneric" data-onebox-src="https://www.bilibili.com/video/BV1tA4y1f7bQ/">
  <header class="source">
    <img src="https://bbs.shu.edu.cn/uploads/default/original/1X/site.png" class="site-icon" width="32" height="32">
    <a href="https://www.bilibili.com/video/BV1tA4y1f7bQ/">哔哩哔哩</a>
  </header>
  <article class="onebox-body">
    <div class="aspect-image"><img src="https://bbs.shu.edu.cn/uploads/default/optimized/1X/thumb.jpeg" class="thumbnail" width="690" height="431"></div>
    <h3><a href="https://www.bilibili.com/video/BV1tA4y1f7bQ/">视频标题</a></h3>
    <p>这是一段很长的视频简介。</p>
  </article>
</aside>
''';
    final oneboxSegments = HtmlText.parseSegments(oneboxCooked);
    final onebox = oneboxSegments.single;
    expect(onebox.kind, CookedSegmentKind.onebox);
    expect(onebox.link?.title, '视频标题');
    expect(onebox.link?.source, '哔哩哔哩');
    expect(onebox.link?.excerpt, '这是一段很长的视频简介。');
    expect(onebox.link?.thumbnailUrl, contains('thumb.jpeg'));

    const quoteCooked = '''
<aside class="quote" data-post="1" data-topic="875">
  <div class="title">
    <a href="https://bbs.shu.edu.cn/t/topic/875/">内部帖子标题</a>
  </div>
  <blockquote>内部帖子摘要内容</blockquote>
</aside>
''';
    final quote = HtmlText.parseSegments(quoteCooked).single;
    expect(quote.kind, CookedSegmentKind.quote);
    expect(quote.link?.topicId, 875);
    expect(quote.link?.postNumber, 1);
    expect(quote.link?.title, '内部帖子标题');
    expect(quote.link?.excerpt, '内部帖子摘要内容');
    expect(
      HtmlText.internalTopicIdFromUrl('https://bbs.shu.edu.cn/t/topic/875/2'),
      875,
    );

    const mentionCooked =
        '<p><a class="mention" href="/u/Lilin">@Lilin</a> 你好</p>';
    expect(HtmlText.prefersPlainPrivateMessageText(mentionCooked), isTrue);
    expect(
      HtmlText.prefersPlainPrivateMessageText('<p>mail@example.com</p>'),
      isFalse,
    );
    expect(
      HtmlText.prefersPlainPrivateMessageText(
        '<p><a class="mention" href="/u/%E4%B8%8A%E5%A4%A7%E8%AE%BA%E5%9D%9B">@上大论坛</a> 你好</p>',
      ),
      isTrue,
    );
    expect(
      HtmlText.prefersPlainPrivateMessageText(
        '<p>嗨！请说 <code>@上大论坛 显示帮助</code>。</p>',
      ),
      isTrue,
    );
    expect(
      HtmlText.prefersPlainPrivateMessageText(
        '<p>说明</p><blockquote><p>很长的帮助内容</p></blockquote>',
      ),
      isTrue,
    );
    final mention = HtmlText.parseSegments(mentionCooked).first;
    expect(mention.kind, CookedSegmentKind.text);
    expect(mention.textValue, '@Lilin 你好');
    final mentionLink = mention.runs.first.link;
    expect(mentionLink?.isInternalUser, isTrue);
    expect(mentionLink?.userUsername, 'Lilin');
    expect(
      HtmlText.internalUsernameFromUrl(
        'https://bbs.shu.edu.cn/u/%E4%B8%8A%E5%A4%A7%E8%AE%BA%E5%9D%9B',
      ),
      '上大论坛',
    );

    const inlineLinkCooked =
        '<p>请看 <a href="https://example.com/a">这个链接</a> 好吗</p>';
    expect(HtmlText.prefersPlainPrivateMessageText(inlineLinkCooked), isFalse);
    final inlineLink = HtmlText.parseSegments(inlineLinkCooked).single;
    expect(inlineLink.kind, CookedSegmentKind.text);
    expect(inlineLink.textValue, '请看 这个链接 好吗');
    expect(
      inlineLink.runs.any(
        (run) => run.text == '这个链接' && run.link?.url == 'https://example.com/a',
      ),
      isTrue,
    );
  });

  test('parses discourse polls from cooked html and post json', () {
    const cooked = '''
<div class="poll" data-poll-charttype="bar" data-poll-max="2" data-poll-min="1" data-poll-name="poll2" data-poll-public="false" data-poll-results="always" data-poll-status="open" data-poll-type="multiple">
<div class="poll-container">
<ul>
<li data-poll-option-id="a">A</li>
<li data-poll-option-id="b">B</li>
</ul>
</div>
</div>
''';
    final segment = HtmlText.parseSegments(cooked).single;
    expect(segment.kind, CookedSegmentKind.poll);
    expect(segment.poll?.name, 'poll2');
    expect(segment.poll?.isMultiple, isTrue);
    expect(segment.poll?.effectiveMax, 2);
    expect(segment.poll?.options.map((option) => option.id), ['a', 'b']);

    final post = Post.fromJson({
      'id': 10,
      'topic_id': 20,
      'username': 'Lilin',
      'cooked': cooked,
      'post_number': 1,
      'post_url': '/t/topic/20/1',
      'polls': [
        {
          'id': 4,
          'name': 'poll2',
          'type': 'multiple',
          'status': 'open',
          'results': 'always',
          'min': 1,
          'max': 2,
          'options': [
            {'id': 'a', 'html': 'A', 'votes': 1},
            {'id': 'b', 'html': 'B', 'votes': 0},
          ],
          'voters': 1,
          'chart_type': 'bar',
        }
      ],
      'polls_votes': {
        'poll2': ['a'],
      },
    });
    expect(post.polls.single.name, 'poll2');
    expect(post.polls.single.ownVotes, ['a']);
    expect(post.polls.single.options.first.votes, 1);
  });

  test('builds structured topic previews for polls and cards', () {
    const pollCooked = '''
<p>帮忙投一下</p>
<div class="poll" data-poll-charttype="bar" data-poll-max="1" data-poll-min="1" data-poll-name="poll" data-poll-public="true" data-poll-results="always" data-poll-status="open" data-poll-title="你喜欢下雨天吗？" data-poll-type="regular">
<div class="poll-container">
<ul>
<li data-poll-option-id="a">喜欢</li>
<li data-poll-option-id="b">不喜欢</li>
</ul>
</div>
<p>0 投票人</p>
</div>
''';
    final pollPreview = HtmlText.topicPreview(pollCooked);

    expect(pollPreview.text, '帮忙投一下 [投票] 你喜欢下雨天吗？');
    expect(pollPreview.text, isNot(contains('喜欢 不喜欢')));
    expect(pollPreview.text, isNot(contains('投票人')));

    const oneboxCooked = '''
<aside class="onebox allowlistedgeneric" data-onebox-src="https://example.com/a">
<article class="onebox-body">
<h3><a href="https://example.com/a">链接标题</a></h3>
<p>预览正文</p>
</article>
</aside>
''';
    expect(HtmlText.topicPreview(oneboxCooked).text, '[链接] 链接标题');
  });

  test('parses discourse formatted cooked text segments', () {
    const cooked = '''
<h1>一级标题</h1>
<p><strong>粗体</strong> <em>斜体</em> <strong><em>粗斜体</em></strong> <del>删除线</del> <code>print()</code></p>
<blockquote><p>引用内容</p></blockquote>
<ul><li>无序一</li><li><strong>无序二</strong></li></ul>
<ol><li>有序一</li><li>有序二</li></ol>
<pre><code>final x = 1;
  print(x);
</code></pre>
''';

    final segments = HtmlText.parseSegments(cooked);
    final heading = segments[0];
    final paragraph = segments[1];
    final quote = segments[2];
    final unordered = segments[3];
    final ordered = segments[5];
    final codeBlock = segments.last;

    expect(heading.textBlockKind, CookedTextBlockKind.heading);
    expect(heading.headingLevel, 1);
    expect(heading.textValue, '一级标题');
    expect(paragraph.textValue, contains('粗体 斜体 粗斜体 删除线 print()'));
    expect(paragraph.runs.any((run) => run.text == '粗体' && run.bold), isTrue);
    expect(
      paragraph.runs.any((run) => run.text == '斜体' && run.italic),
      isTrue,
    );
    expect(
      paragraph.runs.any((run) => run.text == '粗斜体' && run.bold && run.italic),
      isTrue,
    );
    expect(
      paragraph.runs.any((run) => run.text == '删除线' && run.strikethrough),
      isTrue,
    );
    expect(
      paragraph.runs.any((run) => run.text == 'print()' && run.code),
      isTrue,
    );
    expect(quote.textBlockKind, CookedTextBlockKind.blockquote);
    expect(quote.textValue, '引用内容');
    expect(unordered.textBlockKind, CookedTextBlockKind.listItem);
    expect(unordered.listIndex, 0);
    expect(ordered.textBlockKind, CookedTextBlockKind.listItem);
    expect(ordered.listIndex, 1);
    expect(codeBlock.textBlockKind, CookedTextBlockKind.codeBlock);
    expect(codeBlock.textValue, contains('final x = 1'));
    expect(codeBlock.textValue, contains('  print(x);'));
  });

  test('keeps discourse lightbox images as image segments', () {
    const cooked = '''
<p>小木曾雪菜镇楼喵</p>
<p><div class="lightbox-wrapper">
  <a class="lightbox" href="https://bbs.shu.edu.cn/uploads/default/original/1X/original.jpeg" title="photo.jpg">
    <img src="https://bbs.shu.edu.cn/uploads/default/optimized/1X/photo_2_500x500.jpeg" alt="photo.jpg" width="500" height="500">
    <div class="meta"><span class="filename">photo.jpg</span></div>
  </a>
</div></p>
''';

    final segments = HtmlText.parseSegments(cooked);

    expect(segments.where((segment) => segment.isImage), hasLength(1));
    expect(segments.where((segment) => segment.isLink), isEmpty);
    final image = segments.singleWhere((segment) => segment.isImage);
    expect(image.value, contains('photo_2_500x500.jpeg'));
    expect(image.resolvedImageFullUrl, contains('original.jpeg'));
    expect(image.imageWidth, 500);
    expect(image.imageHeight, 500);
  });

  test('merges topic posts by id and keeps post-number order', () {
    final topic = TopicDetail(
      id: 1,
      title: 'topic',
      categoryId: 1,
      postsCount: 2,
      highestPostNumber: 2,
      canCreatePost: true,
      canDelete: false,
      posts: [
        _post(id: 10, postNumber: 1),
      ],
      postStreamIds: const [10, 11],
    );

    final merged = topic.mergedWithPosts([
      _post(id: 11, postNumber: 2),
      _post(id: 10, postNumber: 1),
    ]);

    expect(merged.posts.map((post) => post.id), [10, 11]);
    expect(merged.postStreamIds, [10, 11]);
    expect(merged.highestPostNumber, 2);
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

    final timing = PayloadFactory.topicTiming(
      topicId: 875,
      postNumber: 1,
      topicTimeMs: 35921,
      postTimingsMs: const {1: 2914, 2: 1001, 17: 32001},
    );
    final timingFields = PayloadFactory.decodeForm(timing.body);
    expect(timing.url, endsWith('/topics/timings'));
    expect(timingFields['topic_id'], '875');
    expect(timingFields['topic_time'], '35921');
    expect(timingFields['timings[1]'], '2914');
    expect(timingFields['timings[2]'], '1001');
    expect(timingFields['timings[17]'], '32001');
  });

  test('builds poll vote and status payloads', () {
    final vote = PayloadFactory.votePoll(
      postId: 1263,
      pollName: 'poll',
      optionIds: const ['a', 'b'],
    );
    final toggle = PayloadFactory.togglePollStatus(
      postId: 1263,
      pollName: 'poll',
      status: 'closed',
    );

    expect(vote.method, 'PUT');
    expect(vote.url, endsWith('/polls/vote'));
    expect(PayloadFactory.decodeForm(vote.body)['post_id'], '1263');
    expect(PayloadFactory.decodeForm(vote.body)['poll_name'], 'poll');
    expect(
      RegExp('options%5B%5D=').allMatches(vote.body),
      hasLength(2),
    );
    expect(vote.body, contains('options%5B%5D=a'));
    expect(vote.body, contains('options%5B%5D=b'));

    expect(toggle.method, 'PUT');
    expect(toggle.url, endsWith('/polls/toggle_status'));
    expect(
      PayloadFactory.decodeForm(toggle.body),
      containsPair('status', 'closed'),
    );
  });

  test('builds forum report payloads', () {
    final postReport = PayloadFactory.reportContent(
      const ForumReportDraft(
        id: 1222,
        reason: ForumReportReason.other,
        message: '该链接指向的目标无效',
        flagTopic: false,
      ),
    );
    final topicReport = PayloadFactory.reportContent(
      const ForumReportDraft(
        id: 824,
        reason: ForumReportReason.spam,
        flagTopic: true,
      ),
    );

    final postFields = PayloadFactory.decodeForm(postReport.body);
    expect(postReport.method, 'POST');
    expect(postFields['id'], '1222');
    expect(postFields['post_action_type_id'], '7');
    expect(postFields['message'], '该链接指向的目标无效');
    expect(postFields['flag_topic'], 'false');
    expect(topicReport.body, 'id=824&post_action_type_id=8&flag_topic=true');
  });

  test('builds topic and private message payloads', () {
    const image = UploadedImage(
      url: 'https://bbs.shu.edu.cn/uploads/default/original/1X/a.jpeg',
      shortUrl: 'upload://a.jpeg',
      filename: 'a.jpeg',
      width: 1460,
      height: 1002,
      thumbnailWidth: 690,
      thumbnailHeight: 473,
    );
    final topic = PayloadFactory.createTopic(
      const CreateTopicDraft(
        title: '这是一个测试标题',
        raw: '这是一个测试内容',
        categoryId: 9,
        draftKey: 'new_topic_1',
        images: [image],
      ),
    );
    final message = PayloadFactory.createPrivateMessage(
      const PrivateMessageDraft(
        title: '这是一条私信',
        raw: '这是一条发给自己的私信',
        recipients: 'Lilin',
        draftKey: 'new_private_message_1',
      ),
    );

    final topicFields = PayloadFactory.decodeForm(topic.body);
    expect(topicFields['archetype'], 'regular');
    expect(topicFields['category'], '9');
    expect(topicFields['image_sizes[${image.url}][width]'], '1460');
    expect(image.markdown, '![a.jpeg|690x473](upload://a.jpeg)');

    final messageFields = PayloadFactory.decodeForm(message.body);
    expect(messageFields['archetype'], 'private_message');
    expect(messageFields['target_recipients'], 'Lilin');
    expect(messageFields['category'], '');
  });

  test('composes advanced markdown without duplicating inserted images', () {
    const image = UploadedImage(
      url: 'https://bbs.shu.edu.cn/uploads/default/original/1X/a.jpeg',
      shortUrl: 'upload://a.jpeg',
      filename: 'a.jpeg',
      width: 1460,
      height: 1002,
      thumbnailWidth: 690,
      thumbnailHeight: 473,
    );
    final raw = '正文\n${image.markdown}';

    expect(composeRawWithImages(raw, const [image]), raw);
    expect(composeRawWithImages('正文', const [image]), contains(image.markdown));
  });

  test('builds local advanced markdown preview cooked html', () {
    const image = UploadedImage(
      url: 'https://bbs.shu.edu.cn/uploads/default/original/1X/a.jpeg',
      shortUrl: 'upload://a.jpeg',
      filename: 'a.jpeg',
      width: 1460,
      height: 1002,
      thumbnailWidth: 690,
      thumbnailHeight: 473,
    );
    final cooked = MarkdownEditing.previewCooked(
      '# 标题\n**粗体**\n- A\n${image.markdown}',
      const [image],
    );
    final segments = HtmlText.parseSegments(cooked);

    expect(segments.first.textBlockKind, CookedTextBlockKind.heading);
    expect(segments.any((segment) => segment.isImage), isTrue);
    expect(
      segments.any(
        (segment) => segment.runs.any((run) => run.text == '粗体' && run.bold),
      ),
      isTrue,
    );
    expect(
      segments.any(
          (segment) => segment.textBlockKind == CookedTextBlockKind.listItem),
      isTrue,
    );
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

  test('parses notifications and computes sha1', () {
    final notification = ForumNotification.fromNotificationJson({
      'id': 1,
      'notification_type': 6,
      'read': false,
      'created_at': '2026-07-13T06:39:02.810Z',
      'post_number': 6,
      'topic_id': 811,
      'fancy_title': '欢迎！',
      'data': {
        'display_username': '上大论坛',
        'topic_title': '欢迎！',
      },
    });

    expect(notification.kind, '回复');
    expect(notification.canOpenTopic, isTrue);
    expect(notification.isClientVisible, isTrue);

    final badgeNotificationJson = <String, dynamic>{
      'id': 1924,
      'user_id': 669,
      'notification_type': 12,
      'read': true,
      'high_priority': false,
      'created_at': '2026-07-27T09:18:44.898Z',
      'post_number': null,
      'topic_id': null,
      'slug': null,
      'data': {
        'badge_id': 15,
        'badge_name': '首次引用',
        'badge_slug': '-',
        'badge_title': false,
        'username': 'Lilin',
      },
    };
    final badgeNotification = ForumNotification.fromNotificationJson(
      badgeNotificationJson,
    );

    expect(
      ForumNotification.isSupportedNotificationJson(badgeNotificationJson),
      isFalse,
    );
    expect(badgeNotification.kind, '徽章');
    expect(badgeNotification.canOpenTopic, isFalse);
    expect(badgeNotification.isClientVisible, isFalse);

    final likeNotification = ForumNotification.fromUserActionJson(
      {
        'post_id': 1064,
        'acting_username': 'Yuyuko',
        'acting_avatar_template':
            '/letter_avatar_proxy/v4/letter/y/5f9b8f/{size}.png',
        'excerpt': '被点赞的内容',
        'title': '测试帖',
        'topic_id': 832,
        'post_number': 1,
        'category_id': 9,
        'created_at': '2026-07-20T06:43:26.400Z',
      },
      '赞',
    );
    expect(likeNotification.title, 'Yuyuko');
    expect(likeNotification.topicTitle, '测试帖');
    expect(likeNotification.actorUsername, 'Yuyuko');
    expect(likeNotification.actorAvatarUrl(size: 64), contains('/64'));
    expect(Sha1Hash.hex(Uint8List.fromList(utf8.encode('abc'))),
        'a9993e364706816aba3e25717850c26c9cd0d89d');
  });

  test('saves and loads local forum composer drafts', () async {
    SharedPreferences.setMockInitialValues({});
    final key = ForumDraftStore.topicReplyKey(
      username: 'Lilin',
      topicId: 824,
      replyToPostNumber: 6,
    );
    final draft = ForumComposerDraft(
      raw: '继续回复',
      replyToPostNumber: 6,
      images: const [
        UploadedImage(
          url: 'https://bbs.shu.edu.cn/uploads/image.jpeg',
          shortUrl: '/uploads/image.jpeg',
          filename: 'image.jpeg',
          width: 640,
          height: 480,
          thumbnailWidth: 320,
          thumbnailHeight: 240,
        ),
      ],
    );

    await ForumDraftStore.save(key, draft);
    final loaded = await ForumDraftStore.load(key);

    expect(loaded, isNotNull);
    expect(loaded!.raw, '继续回复');
    expect(loaded.replyToPostNumber, 6);
    expect(loaded.images.single.shortUrl, '/uploads/image.jpeg');

    await ForumDraftStore.remove(key);
    expect(await ForumDraftStore.load(key), isNull);
  });

  test('expires stale forum composer drafts and keeps only recent 50',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final staleKey = ForumDraftStore.newTopicKey('Lilin');
    await prefs.setString(
      staleKey,
      jsonEncode(
        ForumComposerDraft(
          raw: '过期草稿',
          updatedAt: now.subtract(const Duration(days: 16)),
        ).toJson(),
      ),
    );
    for (var index = 0; index < 55; index++) {
      final key = ForumDraftStore.topicReplyKey(
        username: 'Lilin',
        topicId: 1000 + index,
        replyToPostNumber: index + 1,
      );
      await prefs.setString(
        key,
        jsonEncode(
          ForumComposerDraft(
            raw: '草稿 $index',
            updatedAt: now.subtract(Duration(minutes: index)),
          ).toJson(),
        ),
      );
    }

    await ForumDraftStore.cleanup();

    expect(await ForumDraftStore.load(staleKey), isNull);
    final remainingKeys = prefs
        .getKeys()
        .where((key) => key.startsWith('forum.composerDraft.v1'))
        .toList();
    expect(remainingKeys.length, 50);
  });

  test('persists forum cache with topic limits and private deletions',
      () async {
    SharedPreferences.setMockInitialValues({});
    final cache = await ForumPersistentCache.open(username: 'Lilin');

    await cache.saveTopicFeed('all:latest', {
      'topic_list': {'topics': []},
      'users': [],
    });
    expect((await cache.loadTopicFeeds()).keys, contains('all:latest'));

    for (var id = 1; id <= 55; id += 1) {
      await cache.saveTopicDetail(
        id,
        {
          'id': id,
          'title': 'topic $id',
          'category_id': 1,
          'posts_count': 1,
          'highest_post_number': 1,
          'details': {'can_create_post': true, 'can_delete': false},
          'post_stream': {
            'posts': [
              {
                'id': id * 10,
                'topic_id': id,
                'username': 'user',
                'avatar_template': '/avatar/{size}.png',
                'cooked': '<p>cached</p>',
                'post_number': 1,
                'post_url': '/t/topic/$id/1',
              }
            ],
            'stream': [id * 10],
          },
        },
        privateMessage: false,
      );
    }
    final details = await cache.loadTopicDetails();
    expect(details, hasLength(50));
    expect(details.containsKey(1), isFalse);
    expect(details.containsKey(55), isTrue);

    await cache.savePrivateMessages({
      'topic_list': {
        'topics': [
          {'id': 101, 'title': 'keep'},
          {'id': 102, 'title': 'delete'},
        ],
      },
      'users': [],
    });
    await cache.removePrivateMessageTopic(102);
    final privateMessages = cache.loadPrivateMessages();
    final topicList = privateMessages?['topic_list'] as JsonMap;
    final topics = topicList['topics'] as List;
    expect(topics.whereType<JsonMap>().map((topic) => topic['id']), [101]);
  });

  test('saves and cleans forum read positions', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final key = ForumReadPositionStore.topicKey(
      username: 'Lilin',
      topicId: 824,
    );

    await ForumReadPositionStore.save(
      key,
      320.5,
      anchorPostNumber: 6,
      anchorDelta: 28.5,
      bottomDistance: 140,
    );
    final loaded = await ForumReadPositionStore.load(key);
    expect(loaded, isNotNull);
    expect(loaded!.offset, 320.5);
    expect(loaded.anchorPostNumber, 6);
    expect(loaded.anchorDelta, 28.5);
    expect(loaded.bottomDistance, 140);

    const legacyV1Key = 'forum.readPosition.v1.topic.lilin.823';
    const legacyV2Key = 'forum.readPosition.v2.topic.lilin.822';
    const legacyV3Key = 'forum.readPosition.v3.topic.lilin.821';
    for (final legacyKey in [legacyV1Key, legacyV2Key, legacyV3Key]) {
      await prefs.setString(
        legacyKey,
        jsonEncode({
          'offset': 260,
          'updated_at': DateTime.now().toIso8601String(),
        }),
      );
    }
    await ForumReadPositionStore.cleanup();
    expect(prefs.getString(legacyV1Key), isNull);
    expect(prefs.getString(legacyV2Key), isNull);
    expect(prefs.getString(legacyV3Key), isNull);

    await prefs.setString(
      key,
      jsonEncode({
        'offset': 280,
        'updated_at': DateTime.now().toIso8601String(),
      }),
    );
    expect((await ForumReadPositionStore.load(key))?.offset, 320.5);

    final staleKey = ForumReadPositionStore.topicKey(
      username: 'Lilin',
      topicId: 825,
    );
    await prefs.setString(
      staleKey,
      jsonEncode(
        ForumReadPosition(
          offset: 120,
          updatedAt: DateTime(2000),
        ).toJson(),
      ),
    );
    await ForumReadPositionStore.cleanup();
    expect(await ForumReadPositionStore.load(staleKey), isNull);

    final now = DateTime.now();
    for (var index = 0; index < 305; index++) {
      final key = ForumReadPositionStore.topicKey(
        username: 'Lilin',
        topicId: 1000 + index,
      );
      await prefs.setString(
        key,
        jsonEncode(
          ForumReadPosition(
            offset: index.toDouble(),
            updatedAt: now.subtract(Duration(minutes: index)),
          ).toJson(),
        ),
      );
    }

    await ForumReadPositionStore.cleanup();

    final remainingKeys = prefs
        .getKeys()
        .where((key) => key.startsWith('forum.readPosition.v4'))
        .toList();
    expect(remainingKeys.length, 300);
  });

  test('renders extended discourse emoji shortcodes', () {
    final rendered = EmojiText.render(
      ':game_die: :left_speech_bubble: :crystal_ball:',
    );

    expect(rendered, contains('\u{1F3B2}'));
    expect(rendered, contains('\u{1F5E8}\u{FE0F}'));
    expect(rendered, contains('\u{1F52E}'));
    expect(EmojiText.entriesForShortcodes(['game_die']), isNotEmpty);
  });

  test('parses school announcement list and detail html', () {
    final items = AnnouncementApiClient.parseAnnouncementList(
      '''
      <div class="ej_main"><div class="list"><ul>
        <li><a href="info/1051/397875.htm">
          <p class="bt">关于2025-2026学年暑假工作安排的通知</p>
          <p class="zy">校内各单位：经学校研究决定...</p>
          <p class="sj">2026.06.30</p>
        </a></li>
      </ul></div></div>
      ''',
      baseUrl: 'https://www.shu.edu.cn/tzgg.htm',
    );

    expect(items.single.title, contains('暑假工作安排'));
    expect(items.single.url, 'https://www.shu.edu.cn/info/1051/397875.htm');
    expect(items.single.publishedAt, DateTime(2026, 6, 30));

    final detail = AnnouncementApiClient.parseAnnouncementDetail(
      '''
      <div class="nry">
        <h1 align="center">关于宝山校区校内通行温馨提醒</h1>
        <div class="xx">
          <span>发布时间：2026-05-29</span>
          <span>投稿：钟艺玲</span>
          <span>部门：对外联络处</span>
        </div>
        <div class="con"><div class="v_news_content">
          <p>广大师生：</p>
          <p class="vsbcontent_img">
            <img src="/__local/image.jpg" alt="route.jpg">
          </p>
          <p>请注意安全。</p>
        </div></div>
      </div>
      ''',
      url: 'https://www.shu.edu.cn/info/1051/395885.htm',
    );

    expect(detail.department, '对外联络处');
    expect(detail.blocks.map((block) => block.value), contains('广大师生：'));
    expect(
      detail.blocks.map((block) => block.value),
      contains('https://www.shu.edu.cn/__local/image.jpg'),
    );
  });

  test('parses classroom options and detects available rooms', () {
    final options = ClassroomApiClient.parseSearchOptions(
      {
        'code': 200,
        'data': {
          'buildList': [
            {
              'id': 303,
              'name': 'A楼',
              'parentNodeId': 3,
              'fullName': '上海大学/宝山校区/A楼',
              'roomCode': 'AL',
            },
          ],
        },
      },
      {
        'code': 200,
        'data': {
          'curSection': 5,
          'section': [
            {'sectionIndex': 5, 'startTime': '13:00', 'endTime': '13:45'},
            {'sectionIndex': 6, 'startTime': '13:55', 'endTime': '14:40'},
          ],
        },
      },
    );

    expect(options.buildings.single.campusName, '宝山');
    expect(options.sections.map((section) => section.index), [5, 6]);
    final range = ClassroomRepository().defaultRangeFor(options);
    expect(range.label, '5-6节');

    final schedule = ClassroomApiClient.parseBuildingSchedule(
      {
        'code': 200,
        'data': {
          'floorList': [
            {
              'id': 304,
              'name': '一层',
              'children': [
                {
                  'id': 362,
                  'name': 'A101',
                  'fullName': '上海大学/宝山校区/A楼/一层/A101',
                  'roomCourseList': [],
                },
                {
                  'id': 353,
                  'name': 'A104',
                  'fullName': '上海大学/宝山校区/A楼/一层/A104',
                  'roomCourseList': [
                    {
                      'courseName': '日语语言认知实习',
                      'teacherName': '叶老师',
                      'startSection': 5,
                      'endSection': 8,
                    },
                  ],
                },
              ],
            },
          ],
        },
      },
      building: options.buildings.single,
    );

    final rooms = schedule.floors.single.rooms;
    expect(rooms.first.isFreeFor(5, 6), isTrue);
    expect(rooms.last.isFreeFor(5, 6), isFalse);
    expect(rooms.last.coursesFor(5, 6).single.courseName, contains('日语'));
  });

  test('parses course rating search and detail json', () {
    final search = CourseRatingApiClient.parseSearchResult({
      'query': '微积分',
      'courses': [
        {
          'CourseCode': 'GBK0101005',
          'CourseCodes': ['GBK0101005'],
          'ID': 17,
          'Name': '微积分',
          'Count': 3,
        },
      ],
      'teachers': [
        {'ID': 207, 'Name': '丁洋'},
      ],
    });

    expect(search.courses.single.displayCode, 'GBK0101005');
    expect(search.courses.single.lookupForRatings, 'GBK0101005');
    expect(search.teachers.single.name, '丁洋');

    final detail = CourseRatingApiClient.parseRatingDetail({
      'average': 10,
      'course': {
        'CourseCodes': ['GBK0101005'],
        'ID': 17,
        'Name': '微积分',
      },
      'teacher_id': 207,
      'teacher_name': '丁洋',
      'page': 1,
      'per_page': 10,
      'total': 1,
      'radar': {
        'categories': ['教师给分情况'],
        'values': [1],
      },
      'ratings': [
        {
          'ID': 1631,
          'Score': 10,
          'Content': '课挺好的，给分也不赖',
          'CreatedAt': 1783639234,
          'Upvotes': 0,
          'user': {'id': 8, 'username': '蓝河ovo'},
          'tags': [
            {
              'id': 1,
              'prefix': '给分',
              'name': '高于预期',
              'category': '教师给分情况',
              'weight': 3,
            },
          ],
        },
      ],
    });

    expect(detail.course.name, '微积分');
    expect(detail.teacher.name, '丁洋');
    expect(detail.average, 10);
    expect(detail.ratings.single.tags.single.displayText, '给分：高于预期');
    expect(detail.ratings.single.createdAt, isA<DateTime>());
  });

  test('parses editable profile fields and builds settings payloads', () {
    final profile = UserProfile.fromJson({
      'user': {
        'id': 669,
        'username': 'Lilin',
        'avatar_template': '/user_avatar/bbs.shu.edu.cn/lilin/{size}/95_2.png',
        'bio_raw': "Here's an introduction!",
        'bio_excerpt': 'Here’s an introduction!',
        'profile_background_upload_url': '/uploads/default/original/bg.jpeg',
        'card_background_upload_url': '/uploads/default/original/card.jpeg',
        'system_avatar_template':
            '/letter_avatar_proxy/v4/letter/l/ea666f/{size}.png',
        'custom_avatar_upload_id': 95,
        'can_edit': true,
        'can_upload_profile_header': true,
        'user_option': {
          'hide_profile': true,
          'timezone': 'Asia/Shanghai',
          'default_calendar': 'none_selected',
        },
      },
    });

    expect(profile.bioRaw, "Here's an introduction!");
    expect(profile.hideProfile, isTrue);
    expect(profile.profileBackgroundUrl(), endsWith('/bg.jpeg'));
    expect(profile.customAvatarUploadId, 95);

    final settingsPayload = PayloadFactory.updateProfileSettings(
      profile.username,
      ProfileSettingsDraft.fromProfile(profile),
    );
    final fields = PayloadFactory.decodeForm(settingsPayload.body);
    expect(settingsPayload.method, 'PUT');
    expect(fields['hide_profile'], 'true');
    expect(fields['profile_background_upload_url'],
        '/uploads/default/original/bg.jpeg');
    expect(fields['card_background_upload_url'],
        '/uploads/default/original/card.jpeg');

    final systemAvatar = PayloadFactory.pickSystemAvatar(profile.username);
    expect(PayloadFactory.decodeForm(systemAvatar.body)['type'], 'system');
    expect(PayloadFactory.decodeForm(systemAvatar.body)['upload_id'], '');

    final customAvatar = PayloadFactory.pickCustomAvatar(profile.username, 95);
    expect(PayloadFactory.decodeForm(customAvatar.body)['type'], 'custom');
    expect(PayloadFactory.decodeForm(customAvatar.body)['upload_id'], '95');
  });

  test('parses academic schedule bitmasks and untimed courses', () {
    final schedule = AcademicScheduleParser.parse({
      'xsxx': {
        'XNM': '2025',
        'XQM': '16',
        'XNMC': '2025-2026',
        'XQMMC': '春',
      },
      'kbList': [
        {
          'jxb_id': 'course-1',
          'kcmc': '形势与政策',
          'xm': '老师',
          'xqj': '2',
          'jcs': '5-6',
          'oldjc': '48',
          'zcd': '3周,7周,11周,15周',
          'oldzc': '17476',
          'cdmc': 'EJ106',
        },
      ],
      'sjkList': [
        {
          'kcmc': '编程实训',
          'jsxm': '魏晓',
          'qsjsz': '1-4周',
          'qtkcgs': '编程实训魏晓(共4周)/1-4周',
        },
      ],
    });

    expect(schedule.maxWeek, 15);
    expect(schedule.sessions.single.sections, [5, 6]);
    expect(schedule.sessions.single.weeks, [3, 7, 11, 15]);
    expect(schedule.untimedCourses.single.weeks, [1, 2, 3, 4]);
  });

  test('builds academic schedule widget snapshot', () {
    final schedule = AcademicScheduleParser.parse(
      {
        'xsxx': {
          'XNM': '2025',
          'XQM': '16',
          'XNMC': '2025-2026',
          'XQMMC': '春',
        },
        'kbList': [
          {
            'jxb_id': 'course-1',
            'kcmc': '形势与政策',
            'xm': '老师',
            'xqj': '2',
            'jcs': '5-6',
            'oldjc': '48',
            'zcd': '3周,7周,11周,15周',
            'oldzc': '17476',
            'cdmc': 'EJ106',
          },
        ],
      },
      fetchedAt: DateTime(2026, 7, 14, 12),
    );

    final snapshot = AcademicScheduleWidgetService.buildSnapshot(
      schedule: schedule,
      weekState: ScheduleWeekState(
        currentWeek: 3,
        anchorMonday: DateTime(2026, 7, 13),
      ),
      now: DateTime(2026, 7, 14, 12),
    );
    final sessions = snapshot['sessions'] as List;
    final session = sessions.single as Map<String, dynamic>;

    expect(snapshot['hasSchedule'], isTrue);
    expect(snapshot['activeWeek'], 3);
    expect(session['name'], '形势与政策');
    expect(session['weekday'], 2);
    expect(session['startText'], '13:00');
    expect(session['endText'], '14:40');
    expect(session['room'], 'EJ106');
    expect(session['weeks'], [3, 7, 11, 15]);
  });

  test('marks manual academic schedule sessions', () {
    const session = CourseSession(
      id: 'manual:2:5-6:1',
      courseName: '临时课程',
      courseCode: CourseSession.manualCode,
      teacherName: '',
      campus: '',
      location: 'EJ106',
      weekday: 2,
      startSection: 5,
      endSection: 6,
      sections: [5, 6],
      weeks: [3],
      weekText: '3周',
      credit: '',
      note: '',
    );

    expect(session.isManual, isTrue);
    expect(CourseSession.fromJson(session.toJson()).isManual, isTrue);
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
