import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lunar/calendar/Lunar.dart';

import '../../data/models/user_profile.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/theme/shuyo_theme.dart';

class HomeDashboardPage extends StatelessWidget {
  const HomeDashboardPage({
    super.key,
    required this.profile,
    required this.isOnline,
    required this.hasLocalAccount,
    required this.forumRequiresReauthentication,
    required this.hasAcademicAccount,
    required this.isAcademicLoginCompleting,
    required this.isCheckingConnection,
    required this.isInitialConnectionCheck,
    required this.isBusy,
    required this.onLogin,
    required this.onRelogin,
    required this.onOpenAcademicSystem,
    required this.onOpenAnnouncements,
    required this.onOpenEmptyClassroom,
    required this.onOpenCourseRatings,
    required this.showForumNetworkWarning,
    required this.onOpenWebVpnProxy,
    required this.todayCourseContent,
    required this.announcementContent,
    this.isDemo = false,
  });

  final UserProfile profile;
  final bool isOnline;
  final bool hasLocalAccount;
  final bool forumRequiresReauthentication;
  final bool hasAcademicAccount;
  final bool isAcademicLoginCompleting;
  final bool isCheckingConnection;
  final bool isInitialConnectionCheck;
  final bool isBusy;
  final VoidCallback onLogin;
  final VoidCallback onRelogin;
  final VoidCallback onOpenAcademicSystem;
  final VoidCallback onOpenAnnouncements;
  final VoidCallback onOpenEmptyClassroom;
  final VoidCallback onOpenCourseRatings;
  final bool showForumNetworkWarning;
  final VoidCallback onOpenWebVpnProxy;
  final String todayCourseContent;
  final String announcementContent;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        if (isDemo) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: context.shuyoColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.shuyoColors.border),
            ),
            child: Text(
              '演示模式 · 本地静态数据，操作不会上传',
              style: TextStyle(
                color: context.shuyoColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (showForumNetworkWarning) ...[
          _CampusNetworkWarningCard(onOpenWebVpnProxy: onOpenWebVpnProxy),
          const SizedBox(height: 10),
        ],
        _HomeRow(
          title: hasLocalAccount
              ? '欢迎回来，${profile.username}'
              : isAcademicLoginCompleting
                  ? '正在完成校园登录'
                  : hasAcademicAccount
                      ? '你好！'
                      : '立即登录',
          content: !hasLocalAccount
              ? isAcademicLoginCompleting
                  ? '正在获取课表...'
                  : hasAcademicAccount
                      ? '暂未登录乐乎论坛'
                      : '登录后同步个人数据'
              : isCheckingConnection && !isInitialConnectionCheck
                  ? '正在连接论坛...'
                  : isOnline
                      ? _greeting()
                      : isInitialConnectionCheck
                          ? _greeting()
                          : forumRequiresReauthentication
                              ? '论坛登录已失效，请重新登录'
                              : '无法连接乐乎论坛，请稍后重试',
          trailing: isAcademicLoginCompleting && !hasLocalAccount
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : hasLocalAccount
                  ? IconButton(
                      tooltip: '刷新论坛连接',
                      onPressed: isBusy ? null : onRelogin,
                      icon: isBusy && !isInitialConnectionCheck
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : const Icon(Icons.refresh),
                    )
                  : const Icon(Icons.login),
          onTap: isAcademicLoginCompleting ? null : onLogin,
        ),
        _HomeRow(
          icon: Icons.event,
          title: '今日课程',
          content: todayCourseContent,
          onTap: onOpenAcademicSystem,
        ),
        _HomeRow(
          icon: Icons.developer_board,
          title: '通知公告',
          content: announcementContent,
          onTap: onOpenAnnouncements,
        ),
        _HomeRow(
          icon: Icons.location_on,
          title: '空教室查询',
          content: '选择校区、教学楼和节次后查询',
          onTap: onOpenEmptyClassroom,
        ),
        _HomeRow(
          icon: Icons.egg_alt,
          title: '课程评价',
          content: '搜索课程、课程号或教师',
          onTap: onOpenCourseRatings,
        ),
      ],
    );
  }

  String _greeting() {
    final now = DateTime.now();
    final special = _specialGreeting(now);
    if (special != null) {
      return special;
    }

    final hour = now.hour;
    if (hour < 6) {
      return _pick(const [
        '夜深了，记得休息',
        '披星戴月，也别忘了好好睡觉',
        '夜色渐深，明天又是崭新开始',
      ]);
    }
    if (hour < 11) {
      return _pick(const [
        '早上好，今天也顺利',
        '一日之计在于晨',
        '学习与生活，此刻渐入佳境',
        '早安，有个好心情',
        '保持节奏，灵感正发生',
      ]);
    }
    if (hour < 14) {
      return _pick(const [
        '快到中午啦',
        '忙碌过半，先好好吃顿午餐',
        '停下片刻，稍作休息',
      ]);
    }
    if (hour < 18) {
      return _pick(const [
        '下午好，保持节奏',
        '下午的悠闲时光～',
      ]);
    }
    return _pick(const [
      '晚上好，今天辛苦了',
      '忙碌一天，晚上放松一下',
      '晚风轻轻，愿你今晚好梦',
      '晚上好～',
    ]);
  }

  String? _specialGreeting(DateTime date) {
    final lunarGreeting = _lunarGreeting(date);
    if (lunarGreeting != null) {
      return lunarGreeting;
    }
    final key = '${date.month}-${date.day}';
    const specialGreetings = <String, List<String>>{
      '1-1': ['新年快乐，愿新岁胜旧年！🎉', '元气满满迎接新的一年！'],
      '2-14': ['愿你被温柔和快乐包围', '今天也要好好爱自己'],
      '3-8': ['祝你自在明媚，闪闪发光'],
      '5-1': ['劳动节快乐，愿努力都有收获！'],
      '6-1': ['儿童节快乐，愿你永远保有童心！'],
      '9-10': ['教师节快乐，为老师送上一份祝福吧！'],
      '10-1': ['盛世华诞，举国同庆，给自己放个大假！'],
    };
    final greetings = specialGreetings[key];
    return greetings == null ? null : _pick(greetings);
  }

  String? _lunarGreeting(DateTime date) {
    final festivals = Lunar.fromDate(date).getFestivals();
    if (_hasFestival(festivals, '除夕')) {
      return _pick(const [
        '冬尽今宵促，年开明日长。',
        '残腊即又尽，东风应渐闻。',
      ]);
    }
    if (_hasFestival(festivals, '春节')) {
      return _pick(const [
        '爆竹声中一岁除，春风送暖入屠苏。',
        '不须迎向东郊去，春在千门万户中。',
        '松竹含新秋，轩窗有余清。',
        '愿得长如此，年年物候新。',
      ]);
    }
    if (_hasFestival(festivals, '端午')) {
      return _pick(const [
        '端午安康，愿岁岁常欢愉。',
        '彩线轻缠红玉臂，小符斜挂绿云鬟。',
      ]);
    }
    if (_hasFestival(festivals, '中秋')) {
      return _pick(const [
        '但愿人长久，千里共婵娟。',
        '海上生明月，天涯共此时。',
      ]);
    }
    if (_hasFestival(festivals, '清明')) {
      return _pick(const [
        '寄相思于草木，留期许在心间。',
        '燕子来时新社，梨花落后清明。',
      ]);
    }
    if (_hasFestival(festivals, '元宵')) {
      return _pick(const [
        '今年元夜时，月与灯依旧。',
        '东风夜放花千树，更吹落、星如雨。',
      ]);
    }
    return null;
  }

  bool _hasFestival(List<String> festivals, String name) {
    return festivals.any((festival) =>
        festival == name || festival == '$name节' || festival.contains(name));
  }

  String _pick(List<String> values) {
    return values[Random().nextInt(values.length)];
  }
}

class _CampusNetworkWarningCard extends StatelessWidget {
  const _CampusNetworkWarningCard({
    required this.onOpenWebVpnProxy,
  });

  final VoidCallback onOpenWebVpnProxy;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.signal_wifi_bad,
                  color: colors.textSecondary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '未能连接到校园内网',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          RichText(
            text: TextSpan(
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
              children: const [
                TextSpan(
                  text:
                      '无法连接到上海大学内部网络，部分功能可能不可用。然而，如果你开启了“自动使用WebVPN代理”，并且已进行统一身份认证，你仍然可以直接使用这些功能。\n\n',
                ),
                TextSpan(text: '如果不起作用，请尝试使用校园VPN（'),
                TextSpan(
                  text: 'aTrustVPN',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: '）或连接ShuWlan校园网以访问内网资源。'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onOpenWebVpnProxy,
              child: const Text('WebVPN代理（推荐）'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeRow extends StatelessWidget {
  const _HomeRow({
    required this.title,
    required this.content,
    this.icon,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String content;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              SizedBox(
                width: 40,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    icon,
                    color: colors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShuYoTextStyles.title(
                      color: colors.textPrimary,
                      size: 16,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13.5,
                      height: 1.46,
                    ),
                  ),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
