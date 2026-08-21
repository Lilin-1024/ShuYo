import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/forum_notification.dart';
import '../../data/models/topic.dart';
import '../../data/models/topic_detail.dart';
import '../../data/repositories/forum_repository.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/empty_state.dart';
import '../profile/user_profile_page.dart';
import '../topic/topic_detail_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.repository,
    this.onRecoverConnection,
    this.onLoginRequired,
    this.onSessionExpired,
    this.onBookmarkChanged,
  });

  final ForumRepository repository;
  final Future<ForumRecoveryResult> Function()? onRecoverConnection;
  final Future<void> Function()? onLoginRequired;
  final Future<void> Function()? onSessionExpired;
  final VoidCallback? onBookmarkChanged;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        bottom: TabBar(
          controller: _controller,
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '回复'),
            Tab(text: '赞'),
            Tab(text: '提及'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: const [
          _NotificationList(filter: NotificationFeedFilter.all),
          _NotificationList(filter: NotificationFeedFilter.replies),
          _NotificationList(filter: NotificationFeedFilter.likes),
          _NotificationList(filter: NotificationFeedFilter.mentions),
        ].map((child) {
          return _NotificationListHost(
            repository: widget.repository,
            onRecoverConnection: widget.onRecoverConnection,
            filter: child.filter,
            onLoginRequired: widget.onLoginRequired,
            onSessionExpired: widget.onSessionExpired,
            onBookmarkChanged: widget.onBookmarkChanged,
          );
        }).toList(),
      ),
    );
  }
}

class _NotificationList {
  const _NotificationList({required this.filter});

  final NotificationFeedFilter filter;
}

class _NotificationListHost extends StatefulWidget {
  const _NotificationListHost({
    required this.repository,
    required this.filter,
    this.onRecoverConnection,
    this.onLoginRequired,
    this.onSessionExpired,
    this.onBookmarkChanged,
  });

  final ForumRepository repository;
  final NotificationFeedFilter filter;
  final Future<ForumRecoveryResult> Function()? onRecoverConnection;
  final Future<void> Function()? onLoginRequired;
  final Future<void> Function()? onSessionExpired;
  final VoidCallback? onBookmarkChanged;

  @override
  State<_NotificationListHost> createState() => _NotificationListHostState();
}

class _NotificationListHostState extends State<_NotificationListHost> {
  static const _targetKindWarmupLimit = 12;

  late Future<List<ForumNotification>> _future;
  final _targetKinds = <String, _NotificationTargetKind>{};
  final _pendingTargetKindTopicIds = <int>{};
  final _completedTargetKindTopicIds = <int>{};

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchNotifications(widget.filter);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ForumNotification>>(
      future: _future,
      builder: (context, snapshot) {
        final colors = context.lehuColors;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 3));
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: '通知加载失败',
            message: snapshot.error.toString(),
            action: TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          );
        }
        final items = snapshot.data ?? const <ForumNotification>[];
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_none,
            title: '暂无通知',
            message: '这里还没有新的内容',
          );
        }
        _warmTargetKindCache(items);
        final groups = _groupNotifications(items);
        return RefreshIndicator(
          onRefresh: () async => _refresh(force: true),
          child: ListView.separated(
            itemCount: groups.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: colors.border),
            itemBuilder: (context, index) {
              final group = groups[index];
              return _NotificationGroupTile(
                group: group,
                onOpenLatest: () => _openTopic(group.latest),
                onOpenUser: _openUserProfile,
                onShowDetails: group.items.length > 1
                    ? () => _showGroupDetails(group)
                    : null,
              );
            },
          ),
        );
      },
    );
  }

  List<_NotificationGroup> _groupNotifications(
    List<ForumNotification> items,
  ) {
    final buckets = <String, List<ForumNotification>>{};
    for (final item in items) {
      (buckets[_groupKey(item)] ??= <ForumNotification>[]).add(item);
    }
    final groups = buckets.values.map((items) {
      items.sort(_compareNotificationTime);
      return _NotificationGroup(
        List.unmodifiable(items),
        targetKinds: _targetKinds,
      );
    }).toList();
    groups.sort((a, b) => _compareNotificationTime(a.latest, b.latest));
    return groups;
  }

  String _groupKey(ForumNotification item) {
    final topicId = item.topicId ?? 0;
    if (item.kind == '赞') {
      return 'like:$topicId:${item.postNumber ?? item.id}';
    }
    return '${item.kind}:$topicId';
  }

  int _compareNotificationTime(
    ForumNotification a,
    ForumNotification b,
  ) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null && bTime == null) {
      return b.id.compareTo(a.id);
    }
    if (aTime == null) {
      return 1;
    }
    if (bTime == null) {
      return -1;
    }
    return bTime.compareTo(aTime);
  }

  Future<void> _showGroupDetails(_NotificationGroup group) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (sheetContext) {
        return _NotificationGroupSheet(
          group: group,
          onOpenItem: (item) {
            Navigator.of(sheetContext).pop();
            unawaited(_openTopic(item));
          },
          onOpenUser: (username) {
            Navigator.of(sheetContext).pop();
            unawaited(_openUserProfile(username));
          },
        );
      },
    );
  }

  Future<void> _refresh({bool force = false}) async {
    if (force) {
      _completedTargetKindTopicIds.clear();
    }
    final future = widget.repository.fetchNotifications(
      widget.filter,
      forceRefresh: force,
    );
    setState(() {
      _future = future;
    });
    await future;
  }

  void _warmTargetKindCache(List<ForumNotification> items) {
    var changed = false;
    final missingTopicIds = <int>{};
    for (final item in items) {
      if (!_needsDetailForTargetKind(item)) {
        continue;
      }
      final topicId = item.topicId;
      if (topicId == null || topicId <= 0) {
        continue;
      }
      final detail = widget.repository.cachedTopicDetail(topicId);
      if (detail != null) {
        final cached = _cacheTargetKindFromDetail(item, detail);
        changed = cached || changed;
        if (cached) {
          continue;
        }
      }
      if (!_completedTargetKindTopicIds.contains(topicId) &&
          !_pendingTargetKindTopicIds.contains(topicId)) {
        missingTopicIds.add(topicId);
      }
    }
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
    if (missingTopicIds.isEmpty) {
      return;
    }
    final limitedTopicIds =
        missingTopicIds.take(_targetKindWarmupLimit).toList(growable: false);
    _pendingTargetKindTopicIds.addAll(limitedTopicIds);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_loadTargetKindsForTopics(items, limitedTopicIds));
      }
    });
  }

  Future<void> _loadTargetKindsForTopics(
    List<ForumNotification> sourceItems,
    List<int> topicIds,
  ) async {
    var changed = false;
    for (final topicId in topicIds) {
      try {
        final detail = await widget.repository.fetchTopicDetail(
          topicId,
          forceRefresh: true,
        );
        if (detail == null) {
          continue;
        }
        _completedTargetKindTopicIds.add(topicId);
        for (final item in sourceItems) {
          if (item.topicId == topicId) {
            changed = _cacheTargetKindFromDetail(item, detail) || changed;
          }
        }
      } on Object {
        // 保持保守文案，下一次刷新时再尝试补全。
      } finally {
        _pendingTargetKindTopicIds.remove(topicId);
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  bool _cacheTargetKindFromDetail(
    ForumNotification item,
    TopicDetail detail,
  ) {
    final kind = _detailTargetKindFor(item, detail);
    if (kind == _NotificationTargetKind.unknown) {
      return false;
    }
    final key = _targetKindCacheKey(item);
    if (_targetKinds[key] == kind) {
      return false;
    }
    _targetKinds[key] = kind;
    return true;
  }

  Future<void> _openTopic(ForumNotification item) async {
    if (!item.canOpenTopic) {
      return;
    }
    final title = item.topicTitle.isNotEmpty ? item.topicTitle : item.title;
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => TopicDetailPage(
          repository: widget.repository,
          onRecoverConnection: widget.onRecoverConnection,
          topic: TopicListItem(
            id: item.topicId!,
            title: title,
            postsCount: 0,
            replyCount: 0,
            highestPostNumber: item.postNumber ?? 0,
            views: 0,
            likeCount: 0,
            categoryId: item.categoryId,
            posters: const [],
            lastPostedAt: item.createdAt,
            createdAt: item.createdAt,
          ),
          targetPostNumber: item.postNumber,
          onLoginRequired: widget.onLoginRequired,
          onSessionExpired: widget.onSessionExpired,
          onBookmarkChanged: widget.onBookmarkChanged,
        ),
      ),
    );
  }

  Future<void> _openUserProfile(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (!widget.repository.isOnline) {
      _showSnack('无法连接论坛，请尝试重新登录。');
      return;
    }
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => UserProfilePage(
          repository: widget.repository,
          username: trimmed,
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _NotificationTargetKind { topic, comment, unknown }

bool _needsDetailForTargetKind(ForumNotification item) {
  return item.kind == '回复' &&
      item.topicId != null &&
      item.topicId! > 0 &&
      item.postNumber != null &&
      item.postNumber! > 0;
}

String _targetKindCacheKey(ForumNotification item) {
  return [
    item.kind,
    item.topicId ?? 0,
    item.postNumber ?? item.id,
  ].join(':');
}

_NotificationTargetKind _targetKindFor(
  ForumNotification item,
  Map<String, _NotificationTargetKind> cache,
) {
  if (item.kind == '赞') {
    final postNumber = item.postNumber;
    if (postNumber == null || postNumber <= 0) {
      return _NotificationTargetKind.unknown;
    }
    return postNumber == 1
        ? _NotificationTargetKind.topic
        : _NotificationTargetKind.comment;
  }
  if (item.kind == '回复') {
    return cache[_targetKindCacheKey(item)] ?? _NotificationTargetKind.unknown;
  }
  return _NotificationTargetKind.unknown;
}

_NotificationTargetKind _detailTargetKindFor(
  ForumNotification item,
  TopicDetail detail,
) {
  if (item.kind != '回复') {
    return _NotificationTargetKind.unknown;
  }
  final postNumber = item.postNumber;
  if (postNumber == null || postNumber <= 0) {
    return _NotificationTargetKind.unknown;
  }
  for (final post in detail.posts) {
    if (post.postNumber != postNumber) {
      continue;
    }
    final repliedPostNumber = post.replyToPostNumber;
    return repliedPostNumber == null || repliedPostNumber <= 1
        ? _NotificationTargetKind.topic
        : _NotificationTargetKind.comment;
  }
  return _NotificationTargetKind.unknown;
}

String _targetText(_NotificationTargetKind kind) {
  return switch (kind) {
    _NotificationTargetKind.topic => '帖子',
    _NotificationTargetKind.comment => '评论',
    _NotificationTargetKind.unknown => '内容',
  };
}

class _NotificationGroup {
  const _NotificationGroup(
    this.items, {
    required this.targetKinds,
  });

  final List<ForumNotification> items;
  final Map<String, _NotificationTargetKind> targetKinds;

  ForumNotification get latest => items.first;
  int get count => items.length;
  bool get isLike => latest.kind == '赞';
  bool get isReply => latest.kind == '回复';

  String get detailTitle {
    return latest.topicTitle.isNotEmpty ? latest.topicTitle : latest.title;
  }

  String get title {
    if (isLike) {
      final targetText = _targetText(_targetKindFor(latest, targetKinds));
      final names = _actorNames();
      final name = names.isEmpty ? '有人' : names.first;
      if (count > 1) {
        return '$name 等人 赞了你的$targetText';
      }
      return '$name 赞了你的$targetText';
    }
    if (isReply) {
      final targetText = _targetText(_targetKindFor(latest, targetKinds));
      return '回复了我的$targetText';
    }
    return detailTitle;
  }

  String get subtitle {
    final text = latest.message.isEmpty ? latest.kind : latest.message;
    if (isLike) {
      final targetKind = _targetKindFor(latest, targetKinds);
      if (targetKind == _NotificationTargetKind.topic) {
        return detailTitle;
      }
      return text;
    }
    if (isReply || count <= 1) {
      return text;
    }
    final actor = _actorName(latest);
    return actor.isEmpty ? text : '$actor：$text';
  }

  List<String> _actorNames() {
    final seen = <String>{};
    final names = <String>[];
    for (final item in items) {
      final name = _actorName(item);
      if (name.isNotEmpty && seen.add(name)) {
        names.add(name);
      }
    }
    return names;
  }

  static String _actorName(ForumNotification item) {
    if (item.actorUsername.isNotEmpty) {
      return item.actorUsername;
    }
    if (item.kind == '赞' && item.title.isNotEmpty) {
      return item.title;
    }
    return '';
  }
}

class _NotificationGroupTile extends StatelessWidget {
  const _NotificationGroupTile({
    required this.group,
    required this.onOpenLatest,
    required this.onOpenUser,
    required this.onShowDetails,
  });

  final _NotificationGroup group;
  final VoidCallback onOpenLatest;
  final ValueChanged<String> onOpenUser;
  final VoidCallback? onShowDetails;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final latest = group.latest;
    return ListTile(
      leading: _NotificationLeading(
        group: group,
        onOpenUser: group.count == 1 ? onOpenUser : null,
      ),
      title: Text(
        group.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: latest.read ? FontWeight.w500 : FontWeight.w800,
        ),
      ),
      subtitle: Text(
        group.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.textSecondary),
      ),
      trailing: _NotificationTrailing(group: group),
      onTap: latest.canOpenTopic ? onOpenLatest : null,
      onLongPress: onShowDetails,
    );
  }
}

class _NotificationLeading extends StatelessWidget {
  const _NotificationLeading({
    required this.group,
    required this.onOpenUser,
  });

  final _NotificationGroup group;
  final ValueChanged<String>? onOpenUser;

  @override
  Widget build(BuildContext context) {
    final avatars = group.items
        .where((item) => item.actorAvatarTemplate.isNotEmpty)
        .toList(growable: false);
    final content = group.count > 1 && avatars.length > 1
        ? _AvatarStack(items: avatars.take(3).toList(growable: false))
        : _NotificationAvatar(item: group.latest, size: 42);
    final username = _NotificationGroup._actorName(group.latest);
    if (onOpenUser == null || username.isEmpty) {
      return content;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpenUser!(username),
      child: content,
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.items});

  final List<ForumNotification> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return SizedBox(
      width: 48,
      height: 42,
      child: Stack(
        children: [
          for (var index = 0; index < items.length; index++)
            Positioned(
              left: index * 12,
              top: index.isEven ? 0 : 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.background, width: 2),
                ),
                child: _NotificationAvatar(item: items[index], size: 30),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationAvatar extends StatelessWidget {
  const _NotificationAvatar({
    required this.item,
    required this.size,
  });

  final ForumNotification item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = item.actorAvatarUrl(size: (size * 2).round());
    if (avatarUrl.isNotEmpty) {
      return ForumAvatar(url: avatarUrl, size: size);
    }
    return SizedBox.square(
      dimension: size,
      child: Icon(_iconForNotification(item.kind)),
    );
  }
}

class _NotificationTrailing extends StatelessWidget {
  const _NotificationTrailing({required this.group});

  final _NotificationGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final time = TimeFormat.compact(group.latest.createdAt);
    if (group.count <= 1) {
      return Text(
        time,
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          time,
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 5),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Text(
              '${group.count} 条',
              style: TextStyle(color: colors.textSecondary, fontSize: 11.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationGroupSheet extends StatelessWidget {
  const _NotificationGroupSheet({
    required this.group,
    required this.onOpenItem,
    required this.onOpenUser,
  });

  final _NotificationGroup group;
  final ValueChanged<ForumNotification> onOpenItem;
  final ValueChanged<String> onOpenUser;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    group.isLike
                        ? '所有点赞'
                        : group.isReply
                            ? '所有回复'
                            : group.detailTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: group.items.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: colors.border),
              itemBuilder: (context, index) {
                final item = group.items[index];
                return group.isLike
                    ? _LikeDetailTile(item: item, onOpenUser: onOpenUser)
                    : _NotificationDetailTile(
                        item: item,
                        onOpenItem: onOpenItem,
                        onOpenUser: onOpenUser,
                      );
              },
            ),
          ),
          if (bottomPadding > 0) SizedBox(height: bottomPadding),
        ],
      ),
    );
  }
}

class _LikeDetailTile extends StatelessWidget {
  const _LikeDetailTile({
    required this.item,
    required this.onOpenUser,
  });

  final ForumNotification item;
  final ValueChanged<String> onOpenUser;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final username = _NotificationGroup._actorName(item);
    return ListTile(
      leading: _NotificationAvatar(item: item, size: 38),
      title: Text(
        username.isEmpty ? '未知用户' : username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Text(
        TimeFormat.compact(item.createdAt),
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      ),
      onTap: username.isEmpty ? null : () => onOpenUser(username),
    );
  }
}

class _NotificationDetailTile extends StatelessWidget {
  const _NotificationDetailTile({
    required this.item,
    required this.onOpenItem,
    required this.onOpenUser,
  });

  final ForumNotification item;
  final ValueChanged<ForumNotification> onOpenItem;
  final ValueChanged<String> onOpenUser;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final username = _NotificationGroup._actorName(item);
    return ListTile(
      leading: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: username.isEmpty ? null : () => onOpenUser(username),
        child: _NotificationAvatar(item: item, size: 38),
      ),
      title: Text(
        username.isEmpty ? item.kind : '$username · ${item.kind}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        item.message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.textSecondary),
      ),
      trailing: Text(
        TimeFormat.compact(item.createdAt),
        style: TextStyle(color: colors.textMuted, fontSize: 12),
      ),
      onTap: item.canOpenTopic ? () => onOpenItem(item) : null,
    );
  }
}

IconData _iconForNotification(String kind) {
  return switch (kind) {
    '回复' => Icons.reply,
    '赞' => Icons.favorite_border,
    '提及' => Icons.alternate_email,
    '引用' => Icons.format_quote,
    _ => Icons.notifications_none,
  };
}
