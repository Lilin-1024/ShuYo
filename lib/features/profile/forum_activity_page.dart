import 'package:flutter/material.dart';

import '../../data/models/forum_activity.dart';
import '../../data/repositories/forum_repository.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/widgets/empty_state.dart';
import '../topic/topic_detail_page.dart';

class ForumActivityPage extends StatefulWidget {
  const ForumActivityPage({
    super.key,
    required this.repository,
    required this.kind,
    this.onLoginRequired,
    this.onSessionExpired,
    this.onBookmarkChanged,
  });

  final ForumRepository repository;
  final ForumActivityKind kind;
  final Future<void> Function()? onLoginRequired;
  final Future<void> Function()? onSessionExpired;
  final VoidCallback? onBookmarkChanged;

  @override
  State<ForumActivityPage> createState() => _ForumActivityPageState();
}

class _ForumActivityPageState extends State<ForumActivityPage> {
  late Future<List<ForumActivityItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchUserActivity(widget.kind);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: FutureBuilder<List<ForumActivityItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 3));
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: '加载失败',
              message: snapshot.error.toString(),
              action: TextButton.icon(
                onPressed: () => _refresh(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            );
          }
          final items = snapshot.data ?? const <ForumActivityItem>[];
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => _refresh(force: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 96),
                  EmptyState(
                    icon: _emptyIcon,
                    title: widget.kind.emptyTitle,
                    message: '下拉可刷新',
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => _refresh(force: true),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: context.lehuColors.border),
              itemBuilder: (context, index) {
                final item = items[index];
                return _ActivityRow(
                  item: item,
                  kind: widget.kind,
                  categoryName:
                      widget.repository.categoryById(item.categoryId)?.name,
                  onTap: () => _openTopic(item),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String get _title {
    return switch (widget.kind) {
      ForumActivityKind.topics => '我的话题',
      ForumActivityKind.read => '最近浏览',
      ForumActivityKind.bookmarks => '我的收藏',
    };
  }

  IconData get _emptyIcon {
    return switch (widget.kind) {
      ForumActivityKind.topics => Icons.forum,
      ForumActivityKind.read => Icons.history,
      ForumActivityKind.bookmarks => Icons.bookmark,
    };
  }

  Future<void> _refresh({bool force = false}) async {
    final future = widget.repository.fetchUserActivity(
      widget.kind,
      forceRefresh: force,
    );
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _openTopic(ForumActivityItem item) async {
    final deleted = await Navigator.of(context).push<bool>(
      lehuRoute(
        builder: (context) => TopicDetailPage(
          repository: widget.repository,
          topic: item.toTopicListItem(),
          onLoginRequired: widget.onLoginRequired,
          onSessionExpired: widget.onSessionExpired,
          onBookmarkChanged: widget.onBookmarkChanged,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    widget.onBookmarkChanged?.call();
    if (deleted == true) {
      await _refresh(force: true);
    }
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.item,
    required this.kind,
    required this.categoryName,
    required this.onTap,
  });

  final ForumActivityItem item;
  final ForumActivityKind kind;
  final String? categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = _metaParts();
    final colors = context.lehuColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LehuTextStyles.title(
                      color: colors.textPrimary,
                      size: 15.5,
                      height: 1.25,
                      weight: FontWeight.w500,
                    ),
                  ),
                  if (item.excerpt.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      item.excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 14,
                        height: 1.46,
                      ),
                    ),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      meta.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  List<String> _metaParts() {
    final parts = <String>[];
    final category = categoryName;
    if (category != null && category.isNotEmpty) {
      parts.add(category);
    }
    if (kind != ForumActivityKind.bookmarks && item.showTopicStats) {
      parts.add('${item.views} 浏览');
      parts.add('${item.replyCount} 回复');
    }
    return parts;
  }
}
