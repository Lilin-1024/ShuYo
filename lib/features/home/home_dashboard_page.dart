import 'package:flutter/material.dart';

import '../../data/models/user_profile.dart';

class HomeDashboardPage extends StatelessWidget {
  const HomeDashboardPage({
    super.key,
    required this.profile,
    required this.isOnline,
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
    required this.onPlaceholder,
  });

  final UserProfile profile;
  final bool isOnline;
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
  final ValueChanged<String> onPlaceholder;

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
          title: isOnline ? '欢迎回来，${profile.username}' : '立即登录',
          content: isOnline ? _greeting() : '登录后同步个人数据',
          trailing: isOnline
              ? IconButton(
                  tooltip: '重新登录',
                  onPressed: isBusy ? null : onRelogin,
                  icon: isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                )
              : const Icon(Icons.login),
          onTap: isOnline ? null : onLogin,
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
        _HomeRow(
          title: '检查更新',
          content: '当前版本 0.1.0',
          onTap: () => onPlaceholder('检查更新'),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.signal_wifi_bad, color: Color(0xFFE0B45B), size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '未能连接到校园内网',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                color: Color(0xFFBDBDBD),
                fontSize: 13.5,
                height: 1.45,
              ),
              children: [
                TextSpan(
                  text:
                      '无法连接到上海大学内部网络，部分功能可能不可用。然而，如果你开启了“自动使用WebVPN代理”，并且已进行统一身份认证，你仍然可以直接使用这些功能。\n\n',
                ),
                TextSpan(text: '如果不起作用，请尝试使用校园VPN（'),
                TextSpan(
                  text: 'aTrustVPN',
                  style: TextStyle(fontWeight: FontWeight.w800),
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
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF202020))),
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
                    color: const Color(0xFFBDBDBD),
                    size: 24,
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
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFAAAAAA),
                      fontSize: 14,
                      height: 1.3,
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
