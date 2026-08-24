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
            forumRequiresReauthentication: false,
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

  testWidgets('opens account management when both accounts are logged in',
      (tester) async {
    var accountTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeDashboardPage(
            profile: UserProfile(
              user: const DiscourseUser(
                id: 1,
                username: 'user',
                avatarTemplate: '',
              ),
            ),
            isOnline: true,
            hasLocalAccount: true,
            forumRequiresReauthentication: false,
            hasAcademicAccount: true,
            isAcademicLoginCompleting: false,
            isCheckingConnection: false,
            isInitialConnectionCheck: false,
            isBusy: false,
            onLogin: () => accountTapped = true,
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

    await tester.tap(find.text('欢迎回来，user'));
    expect(accountTapped, isTrue);
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
            forumRequiresReauthentication: false,
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

  testWidgets('distinguishes an expired forum login from a network failure',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeDashboardPage(
            profile: UserProfile(
              user: const DiscourseUser(
                id: 1,
                username: 'user',
                avatarTemplate: '',
              ),
            ),
            isOnline: false,
            hasLocalAccount: true,
            forumRequiresReauthentication: true,
            hasAcademicAccount: true,
            isAcademicLoginCompleting: false,
            isCheckingConnection: false,
            isInitialConnectionCheck: false,
            isBusy: false,
            onLogin: () {},
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

    expect(find.text('论坛登录已失效，请重新登录'), findsOneWidget);
    expect(find.text('无法连接乐乎论坛，请稍后重试'), findsNothing);
  });
}
