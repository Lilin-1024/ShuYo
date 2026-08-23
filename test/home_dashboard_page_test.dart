import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/models/discourse_user.dart';
import 'package:shuyo/data/models/user_profile.dart';
import 'package:shuyo/features/home/home_dashboard_page.dart';

void main() {
  testWidgets('shows the campus-only greeting and forum login reminder',
      (tester) async {
    var loginTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeDashboardPage(
            profile: UserProfile(
              user: const DiscourseUser(
                id: 0,
                username: '',
                avatarTemplate: '',
              ),
            ),
            isOnline: false,
            hasLocalAccount: false,
            hasAcademicAccount: true,
            isAcademicLoginCompleting: false,
            isCheckingConnection: false,
            isInitialConnectionCheck: false,
            isBusy: false,
            onLogin: () => loginTapped = true,
            onRelogin: () {},
            onOpenAcademicSystem: () {},
            onOpenAnnouncements: () {},
            onOpenEmptyClassroom: () {},
            onOpenCourseRatings: () {},
            showForumNetworkWarning: false,
            onOpenWebVpnProxy: () {},
            todayCourseContent: '今日暂无课程',
            announcementContent: '暂无公告',
          ),
        ),
      ),
    );

    expect(find.text('你好！'), findsOneWidget);
    expect(find.text('暂未登录乐乎论坛'), findsOneWidget);
    expect(find.text('立即登录'), findsNothing);

    await tester.tap(find.text('你好！'));
    expect(loginTapped, isTrue);
  });

  testWidgets('disables forum login while campus login is completing',
      (tester) async {
    var loginTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeDashboardPage(
            profile: UserProfile(
              user: const DiscourseUser(
                id: 0,
                username: '',
                avatarTemplate: '',
              ),
            ),
            isOnline: false,
            hasLocalAccount: false,
            hasAcademicAccount: false,
            isAcademicLoginCompleting: true,
            isCheckingConnection: false,
            isInitialConnectionCheck: false,
            isBusy: false,
            onLogin: () => loginTapped = true,
            onRelogin: () {},
            onOpenAcademicSystem: () {},
            onOpenAnnouncements: () {},
            onOpenEmptyClassroom: () {},
            onOpenCourseRatings: () {},
            showForumNetworkWarning: false,
            onOpenWebVpnProxy: () {},
            todayCourseContent: '课表获取中...',
            announcementContent: '暂无公告',
          ),
        ),
      ),
    );

    expect(find.text('正在完成校园登录'), findsOneWidget);
    expect(find.text('正在获取课表...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('正在完成校园登录'));
    expect(loginTapped, isFalse);
  });
}
