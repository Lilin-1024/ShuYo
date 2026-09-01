import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/demo/demo_data_bundle.dart';
import 'package:shuyo/data/demo/demo_forum_repository.dart';
import 'package:shuyo/data/demo/demo_session.dart';
import 'package:shuyo/data/models/composer.dart';
import 'package:shuyo/data/services/payload_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads bundled demo fixtures without personal identifiers', () async {
    final data = await DemoDataBundle.load();
    expect(data.schedule.term.studentName, '演示同学');
    expect(data.schedule.term.studentId, 'DEMO0001');
    expect(data.announcements, hasLength(4));
    expect(data.courseRatings.ratings, hasLength(20));
    expect(
      data.courseRatings.ratings.every(
        (rating) =>
            rating.teacherName.startsWith('教师') &&
            rating.user.username.startsWith('同学') &&
            !rating.content.contains('刘书朋') &&
            !rating.content.contains('王永') &&
            !rating.content.contains('渠老师'),
      ),
      isTrue,
    );
    expect(data.classroomSchedule.building.name, 'GA楼');
  });

  test('demo forum supports local topic and reply mutations', () async {
    final repository = await DemoForumRepository.load();
    expect(repository.profile.username, 'admin');
    expect(repository.isOnline, isTrue);
    final before = (await repository.fetchLatestTopics()).length;
    final post = await repository.createTopic(const CreateTopicDraft(
      title: '本地演示主题',
      raw: '只保存在本机',
      categoryId: 1,
      draftKey: 'demo-test',
    ));
    expect((await repository.fetchLatestTopics()).length, before + 1);
    await repository.createReply(ReplyDraft(
      topicId: post.topicId,
      categoryId: 1,
      raw: '本地回复',
    ));
    expect(
        (await repository.fetchTopicDetail(post.topicId))!.posts, hasLength(2));
    await repository.deleteTopic((await repository.fetchLatestTopics()).first);
  });

  test('demo session credentials are exact', () {
    expect(DemoSession.matchesCredentials('admin2512', 'abc123456'), isTrue);
    expect(DemoSession.matchesCredentials('admin2512', 'wrong'), isFalse);
  });
}
