import 'package:flutter/material.dart';

import '../../data/models/forum_notification.dart';
import '../../data/models/topic.dart';
import '../../data/repositories/forum_repository.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/empty_state.dart';
import '../topic/topic_detail_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.repository,
    this.onLoginRequired,
    this.onSessionExpired,
    this.onBookmarkChanged,
  });

  final ForumRepository repository;
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
    this.onLoginRequired,
    this.onSessionExpired,
    this.onBookmarkChanged,
  });

  final ForumRepository repository;
  final NotificationFeedFilter filter;
  final Future<void> Function()? onLoginRequired;
  final Future<void> Function()? onSessionExpired;
  final VoidCallback? onBookmarkChanged;

  @override
  State<_NotificationListHost> createState() => _NotificationListHostState();
}

class _NotificationListHostState extends State<_NotificationListHost> {
  late Future<List<ForumNotification>> _future;

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
          return const Center(child: CircularProgressIndicator());
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
        return RefreshIndicator(
          onRefresh: () async => _refresh(force: true),
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) =>
                Divider(height: 1, color: colors.border),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: Icon(_iconFor(item.kind)),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: item.read ? FontWeight.w500 : FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  item.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary),
                ),
                trailing: Text(
                  TimeFormat.compact(item.createdAt),
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                  ),
                ),
                onTap: item.canOpenTopic ? () => _openTopic(item) : null,
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _refresh({bool force = false}) async {
    final future = widget.repository.fetchNotifications(
      widget.filter,
      forceRefresh: force,
    );
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _openTopic(ForumNotification item) async {
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => TopicDetailPage(
          repository: widget.repository,
          topic: TopicListItem(
            id: item.topicId!,
            title: item.title,
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
          onLoginRequired: widget.onLoginRequired,
          onSessionExpired: widget.onSessionExpired,
          onBookmarkChanged: widget.onBookmarkChanged,
        ),
      ),
    );
  }

  IconData _iconFor(String kind) {
    return switch (kind) {
      '回复' => Icons.reply,
      '赞' => Icons.favorite_border,
      '提及' => Icons.alternate_email,
      '徽章' => Icons.workspace_premium_outlined,
      _ => Icons.notifications_none,
    };
  }
}
