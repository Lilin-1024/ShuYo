import 'package:flutter/material.dart';

import '../../data/models/user_profile.dart';
import '../../shared/widgets/avatar.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.profile,
    required this.summary,
    required this.isOnline,
    required this.isBusy,
    required this.onLogin,
    required this.onRelogin,
    required this.onLogout,
  });

  final UserProfile profile;
  final UserSummary summary;
  final bool isOnline;
  final bool isBusy;
  final VoidCallback onLogin;
  final VoidCallback onRelogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        Row(
          children: [
            ForumAvatar(url: profile.avatarUrl(size: 144), size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.username,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID ${profile.id}',
                    style: const TextStyle(color: Color(0xFFBDBDBD)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (!isOnline) ...[
          _LoginPrompt(isBusy: isBusy, onLogin: onLogin),
          const SizedBox(height: 20),
        ] else ...[
          _AccountActions(
            isBusy: isBusy,
            onRelogin: onRelogin,
            onLogout: onLogout,
          ),
          const SizedBox(height: 20),
        ],
        _StatList(summary: summary),
      ],
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({
    required this.isBusy,
    required this.onLogin,
  });

  final bool isBusy;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '当前显示本地样例数据',
          style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 14),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isBusy ? null : onLogin,
            icon: isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(isBusy ? '正在接入...' : '登录乐乎'),
          ),
        ),
      ],
    );
  }
}

class _AccountActions extends StatelessWidget {
  const _AccountActions({
    required this.isBusy,
    required this.onRelogin,
    required this.onLogout,
  });

  final bool isBusy;
  final VoidCallback onRelogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ActionRow(
          icon: Icons.sync,
          label: '重新登录',
          onTap: isBusy ? null : onRelogin,
        ),
        const Divider(height: 1, color: Color(0xFF202020)),
        _ActionRow(
          icon: Icons.logout,
          label: '退出登录',
          onTap: isBusy ? null : onLogout,
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFFD6D6D6)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFD6D6D6),
                  fontSize: 15,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: Color(0xFF8A8A8A),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatList extends StatelessWidget {
  const _StatList({required this.summary});

  final UserSummary summary;

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatItem('访问天数', '${summary.daysVisited}'),
      _StatItem('浏览主题', '${summary.topicsEntered}'),
      _StatItem('已读帖子', '${summary.postsReadCount}'),
      _StatItem('阅读分钟', '${summary.timeReadMinutes}'),
      _StatItem('发帖', '${summary.topicCount}'),
      _StatItem('回复', '${summary.postCount}'),
      _StatItem('收到赞', '${summary.likesReceived}'),
      _StatItem('给出赞', '${summary.likesGiven}'),
    ];

    return Column(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          _StatRow(item: stats[i]),
          if (i != stats.length - 1)
            const Divider(height: 1, color: Color(0xFF202020)),
        ],
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.label,
              style: const TextStyle(color: Color(0xFFD6D6D6), fontSize: 15),
            ),
          ),
          Text(
            item.value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem {
  const _StatItem(this.label, this.value);

  final String label;
  final String value;
}
