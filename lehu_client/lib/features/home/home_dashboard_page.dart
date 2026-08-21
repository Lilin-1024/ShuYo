import 'package:flutter/material.dart';

import '../../data/models/user_profile.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/theme/lehu_theme.dart';

class HomeDashboardPage extends StatelessWidget {
  const HomeDashboardPage({
    super.key,
    required this.profile,
    required this.isOnline,
    required this.hasLocalAccount,
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
  });

  final UserProfile profile;
  final bool isOnline;
  final bool hasLocalAccount;
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        if (showForumNetworkWarning) ...[
          _CampusNetworkWarningCard(onOpenWebVpnProxy: onOpenWebVpnProxy),
          const SizedBox(height: 10),
        ],
        _HomeRow(
          title: hasLocalAccount ? '欢迎回来，${profile.username}' : '立即登录',
          content: !hasLocalAccount
              ? '登录后同步个人数据'
              : isOnline
                  ? _greeting()
                  : '无法连接论坛，请尝试重新登录',
          trailing: hasLocalAccount
              ? IconButton(
                  tooltip: '刷新论坛连接',
                  onPressed: isBusy ? null : onRelogin,
                  icon: isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.refresh),
                )
              : const Icon(Icons.login),
          onTap: hasLocalAccount ? null : onLogin,
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
    final hour = DateTime.now().hour;
    if (hour < 6) {
      return '夜深了，记得休息';
    }
    if (hour < 11) {
      return '早上好，今天也顺利';
    }
    if (hour < 14) {
      return '快到中午啦';
    }
    if (hour < 18) {
      return '下午好，保持节奏';
    }
    return '晚上好，今天辛苦了';
  }
}

class _CampusNetworkWarningCard extends StatelessWidget {
  const _CampusNetworkWarningCard({
    required this.onOpenWebVpnProxy,
  });

  final VoidCallback onOpenWebVpnProxy;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
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
    final colors = context.lehuColors;
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
                    style: LehuTextStyles.title(
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
