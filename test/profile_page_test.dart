import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/discourse_user.dart';
import 'package:shuyo/data/models/user_profile.dart';
import 'package:shuyo/features/profile/profile_page.dart';

void main() {
  testWidgets('shows a complete logged-out profile state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilePage(
            profile: UserProfile(
              user: const DiscourseUser(
                id: 0,
                username: '',
                avatarTemplate: '',
              ),
            ),
            summary: const UserSummary(
              likesGiven: 0,
              likesReceived: 0,
              topicsEntered: 0,
              postsReadCount: 0,
              daysVisited: 0,
              topicCount: 0,
              postCount: 0,
              timeReadSeconds: 0,
            ),
            isOnline: false,
            hasLocalAccount: false,
            hasCachedSummary: false,
            isBusy: false,
            onEditProfile: () {},
            activityCountsFuture: null,
            onOpenActivity: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('暂未登录乐乎论坛'), findsOneWidget);
    expect(find.text('登录后可查看个人资料'), findsOneWidget);
    expect(find.text('登录功能即将开放'), findsNothing);
    expect(find.text('访问天数'), findsNothing);
  });
}
