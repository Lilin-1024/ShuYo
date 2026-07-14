import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lehu_client/data/models/academic_schedule.dart';
import 'package:lehu_client/data/models/category.dart';
import 'package:lehu_client/data/models/common.dart';
import 'package:lehu_client/data/models/composer.dart';
import 'package:lehu_client/data/models/forum_notification.dart';
import 'package:lehu_client/data/models/post.dart';
import 'package:lehu_client/data/models/topic.dart';
import 'package:lehu_client/data/models/topic_detail.dart';
import 'package:lehu_client/data/repositories/classroom_repository.dart';
import 'package:lehu_client/data/services/announcement_api_client.dart';
import 'package:lehu_client/data/services/classroom_api_client.dart';
import 'package:lehu_client/data/services/emoji_text.dart';
import 'package:lehu_client/data/services/html_text.dart';
import 'package:lehu_client/data/services/payload_factory.dart';
import 'package:lehu_client/data/services/sha1_hash.dart';
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
    expect(topic.postStreamIds, contains(topic.firstPost!.id));
    expect(HtmlText.preview(topic.firstPost!.cooked), isNotEmpty);
    expect(preview.imageUrls, isNotEmpty);
    expect(preview.text, isEmpty);
    expect(preview.text, isNot(contains('1920')));
    expect(preview.text, isNot(contains('KB')));
  });

  test('merges topic posts by id and keeps post-number order', () {
    final topic = TopicDetail(
      id: 1,
      title: 'topic',
      categoryId: 1,
      postsCount: 2,
      highestPostNumber: 2,
      canCreatePost: true,
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
    expect(Sha1Hash.hex(Uint8List.fromList(utf8.encode('abc'))),
        'a9993e364706816aba3e25717850c26c9cd0d89d');
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
