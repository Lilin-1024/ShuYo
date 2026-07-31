import 'package:flutter/material.dart';

import '../../data/models/forum_activity.dart';
import '../../data/models/user_profile.dart';
import '../../shared/compact_number.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/theme/lehu_theme.dart';
import 'profile_header.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    super.key,
    required this.profile,
    required this.summary,
    required this.isOnline,
    required this.isBusy,
    required this.onLogin,
    required this.onEditProfile,
    required this.activityCountsFuture,
    required this.onOpenActivity,
  });

  final UserProfile profile;
  final UserSummary summary;
  final bool isOnline;
  final bool isBusy;
  final VoidCallback onLogin;
  final VoidCallback onEditProfile;
  final Future<ForumActivityCounts>? activityCountsFuture;
  final ValueChanged<ForumActivityKind> onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final visibleSummary = isOnline ? summary : _zeroSummary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        ProfileHeader(
          profile: profile,
          title: isOnline ? profile.username : '立即登录',
          subtitle: isOnline ? 'ID ${profile.id}' : '登录后查看个人资料',
          avatarUrl: isOnline ? null : '',
          backgroundUrl: isOnline ? null : '',
          onTap: isBusy ? null : (isOnline ? onEditProfile : onLogin),
          trailing: isBusy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              : const Icon(Icons.chevron_right),
        ),
        const SizedBox(height: 16),
        if (isOnline) ...[
          _ActivitySummaryBar(
            fallback: ForumActivityCounts(
              topics: summary.topicCount,
              read: summary.topicsEntered,
              bookmarks: 0,
            ),
            future: activityCountsFuture,
            onOpenActivity: isBusy ? null : onOpenActivity,
          ),
          const SizedBox(height: 20),
        ],
        _StatList(summary: visibleSummary),
      ],
    );
  }
}

const _zeroSummary = UserSummary(
  likesGiven: 0,
  likesReceived: 0,
  topicsEntered: 0,
  postsReadCount: 0,
  daysVisited: 0,
  topicCount: 0,
  postCount: 0,
  timeReadSeconds: 0,
);

class _ActivitySummaryBar extends StatelessWidget {
  const _ActivitySummaryBar({
    required this.fallback,
    required this.future,
    required this.onOpenActivity,
  });

  final ForumActivityCounts fallback;
  final Future<ForumActivityCounts>? future;
  final ValueChanged<ForumActivityKind>? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final future = this.future;
    if (future == null) {
      return _ActivitySummaryContent(
        counts: fallback,
        loadingBookmarks: false,
        onOpenActivity: onOpenActivity,
      );
    }
    return FutureBuilder<ForumActivityCounts>(
      future: future,
      builder: (context, snapshot) {
        return _ActivitySummaryContent(
          counts: snapshot.data ?? fallback,
          loadingBookmarks: snapshot.connectionState != ConnectionState.done &&
              snapshot.data == null,
          onOpenActivity: onOpenActivity,
        );
      },
    );
  }
}

class _ActivitySummaryContent extends StatelessWidget {
  const _ActivitySummaryContent({
    required this.counts,
    required this.loadingBookmarks,
    required this.onOpenActivity,
  });

  final ForumActivityCounts counts;
  final bool loadingBookmarks;
  final ValueChanged<ForumActivityKind>? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: [
          _ActivityStatButton(
            kind: ForumActivityKind.topics,
            value: compactCount(counts.topics),
            onTap: onOpenActivity,
          ),
          _ActivityStatButton(
            kind: ForumActivityKind.read,
            value: compactCount(counts.read),
            onTap: onOpenActivity,
          ),
          _ActivityStatButton(
            kind: ForumActivityKind.bookmarks,
            value: loadingBookmarks ? '-' : compactCount(counts.bookmarks),
            onTap: onOpenActivity,
          ),
        ],
      ),
    );
  }
}

class _ActivityStatButton extends StatelessWidget {
  const _ActivityStatButton({
    required this.kind,
    required this.value,
    required this.onTap,
  });

  final ForumActivityKind kind;
  final String value;
  final ValueChanged<ForumActivityKind>? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Expanded(
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(kind),
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                kind.title,
                style: LehuTextStyles.chip(
                  color: colors.textTertiary,
                  size: 12.5,
                  weight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LehuTextStyles.title(
                  color: colors.textPrimary,
                  size: 16.5,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
    final colors = context.lehuColors;
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
          if (i != stats.length - 1) Divider(height: 1, color: colors.border),
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
    final colors = context.lehuColors;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14.5,
              ),
            ),
          ),
          Text(
            item.value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
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
