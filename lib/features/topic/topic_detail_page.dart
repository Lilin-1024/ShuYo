import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/forum_activity.dart';
import '../../data/models/post.dart';
import '../../data/models/topic.dart';
import '../../data/models/topic_detail.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/discourse_api_client.dart';
import '../../data/services/payload_factory.dart';
import '../../features/profile/user_profile_page.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/widgets/app_header.dart';
import '../../shared/widgets/empty_state.dart';
import 'topic_page.dart';

class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({
    super.key,
    required this.repository,
    required this.topic,
    this.onLoginRequired,
    this.onSessionExpired,
    this.onBookmarkChanged,
  });

  final ForumRepository repository;
  final TopicListItem topic;
  final Future<void> Function()? onLoginRequired;
  final Future<void> Function()? onSessionExpired;
  final VoidCallback? onBookmarkChanged;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage> {
  static const _topicTimingDelay = Duration(milliseconds: 1100);
  static const _topicTimingMs = 1000;

  Future<TopicDetail?>? _future;
  TopicDetail? _detail;
  bool _submittingReply = false;
  bool _deletingTopic = false;
  bool _topicTimingScheduled = false;
  Timer? _topicTimingTimer;
  final _likingPostIds = <int>{};
  final _deletingPostIds = <int>{};

  @override
  void initState() {
    super.initState();
    _detail = widget.repository.cachedTopicDetail(widget.topic.id);
    _future = widget.repository.fetchTopicDetail(
      widget.topic.id,
      forceRefresh: true,
      trackVisit: true,
    );
  }

  @override
  void dispose() {
    _topicTimingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: '帖子',
              showBack: true,
              showMore: true,
              onBack: () => Navigator.of(context).pop(),
              onMore: () => _showTopicMoreSheet(widget.topic),
              onNotification: () {},
            ),
            Expanded(
              child: FutureBuilder<TopicDetail?>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    _detail = snapshot.data;
                  }
                  final detail = _detail;
                  _scheduleTopicTiming(detail);
                  if (detail == null &&
                      snapshot.connectionState != ConnectionState.done) {
                    return const _LoadingState(message: '正在加载帖子...');
                  }
                  if (detail == null && snapshot.hasError) {
                    return _ErrorState(
                      title: '帖子加载失败',
                      message: snapshot.error.toString(),
                      onRetry: _refresh,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: TopicPage(
                      item: widget.topic,
                      detail: detail,
                      category: widget.repository.categoryById(
                        detail?.categoryId ?? widget.topic.categoryId,
                      ),
                      isOnline: widget.repository.isOnline,
                      isSubmittingReply: _submittingReply,
                      busyLikePostIds: _likingPostIds,
                      busyDeletePostIds: _deletingPostIds,
                      onLikePost: _togglePostLike,
                      onDeletePost: _deletePost,
                      onUploadImage: widget.repository.uploadImage,
                      onCreateReply: _createReply,
                      onOpenUser: _openUserProfile,
                      onLoginRequired: () => unawaited(_requireLogin()),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requireLogin() async {
    await widget.onLoginRequired?.call();
  }

  void _scheduleTopicTiming(TopicDetail? detail) {
    if (_topicTimingScheduled ||
        detail == null ||
        detail.isPrivateMessage ||
        !widget.repository.isOnline) {
      return;
    }
    final postNumber = detail.firstPost?.postNumber;
    if (postNumber == null || postNumber <= 0) {
      return;
    }
    _topicTimingScheduled = true;
    _topicTimingTimer = Timer(_topicTimingDelay, () {
      if (!mounted) {
        return;
      }
      unawaited(
        widget.repository
            .recordTopicTiming(
              detail.id,
              postNumber: postNumber,
              topicTimeMs: _topicTimingMs,
            )
            .catchError((Object error) {}),
      );
    });
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchTopicDetail(
      widget.topic.id,
      forceRefresh: true,
    );
    setState(() {
      _future = future;
    });
    try {
      final detail = await future;
      if (mounted) {
        setState(() => _detail = detail);
      }
    } on Object {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _createReply(ReplyDraft draft) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return;
    }
    if (_submittingReply) {
      return;
    }
    setState(() => _submittingReply = true);
    try {
      await widget.repository.createReply(draft);
      if (!mounted) {
        return;
      }
      _showSnack('评论已发布');
      await _refresh();
    } on Object catch (error) {
      await _handleOperationError(error, title: '评论失败');
    } finally {
      if (mounted) {
        setState(() => _submittingReply = false);
      }
    }
  }

  Future<void> _togglePostLike(Post post) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return;
    }
    if (_likingPostIds.contains(post.id)) {
      return;
    }
    setState(() => _likingPostIds.add(post.id));
    try {
      if (post.liked) {
        await widget.repository.unlikePost(post.id);
      } else {
        await widget.repository.likePost(post.id);
      }
      if (!mounted) {
        return;
      }
      _showSnack(post.liked ? '已取消点赞' : '已点赞');
      await _refresh();
    } on Object catch (error) {
      await _handleOperationError(
        error,
        title: post.liked ? '无法取消点赞' : '点赞失败',
        fallbackMessage: post.liked ? '该点赞已超过论坛允许取消的时限' : null,
      );
    } finally {
      if (mounted) {
        setState(() => _likingPostIds.remove(post.id));
      }
    }
  }

  Future<void> _deletePost(Post post) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return;
    }
    if (_deletingPostIds.contains(post.id)) {
      return;
    }
    setState(() => _deletingPostIds.add(post.id));
    try {
      await widget.repository.deletePost(post);
      if (!mounted) {
        return;
      }
      _showSnack('回复已删除');
      await _refresh();
    } on Object catch (error) {
      await _handleOperationError(
        error,
        title: '无法删除回复',
        fallbackMessage: '该回复已超过论坛允许删除的时限，需联系版主处理。',
      );
    } finally {
      if (mounted) {
        setState(() => _deletingPostIds.remove(post.id));
      }
    }
  }

  Future<void> _shareTopic(TopicListItem topic) async {
    final url = 'https://bbs.shu.edu.cn/t/topic/${topic.id}';
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      _showSnack('帖子链接已复制');
    }
  }

  void _showTopicMoreSheet(TopicListItem topic) {
    final bookmarkFuture = widget.repository.isOnline
        ? widget.repository.findTopicBookmark(topic.id)
        : Future<ForumBookmark?>.value();
    final detail = _detail;
    final firstPost = detail?.firstPost;
    final isOwnTopic = detail != null &&
        !detail.isPrivateMessage &&
        (firstPost?.yours == true ||
            topic.originalPosterId == widget.repository.profile.id);
    final canDeleteTopic = isOwnTopic && detail.canDelete;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        return _TopicMoreSheet(
          bookmarkFuture: bookmarkFuture,
          showDeleteTopic: isOwnTopic,
          canDeleteTopic: canDeleteTopic,
          deletingTopic: _deletingTopic,
          onClose: () => Navigator.of(context).pop(),
          onShare: () {
            Navigator.of(context).pop();
            unawaited(_shareTopic(topic));
          },
          onReport: () {
            Navigator.of(context).pop();
            _showSnack('管理层缺失，举报功能暂无效');
          },
          onBookmark: (bookmark) {
            Navigator.of(context).pop();
            unawaited(_toggleTopicBookmark(topic, bookmark));
          },
          onDeleteTopic: () {
            Navigator.of(context).pop();
            unawaited(_deleteTopic(topic));
          },
          onDeleteTopicUnavailable: () {
            Navigator.of(context).pop();
            unawaited(_showTopicDeleteUnavailable());
          },
        );
      },
    );
  }

  Future<void> _showTopicDeleteUnavailable() async {
    await _showErrorDialog(
      title: '无法删除主题',
      message: '该主题已有回复或超过论坛允许删除的时限，需联系版主处理。',
    );
  }

  Future<void> _deleteTopic(TopicListItem topic) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return;
    }
    if (_deletingTopic) {
      return;
    }
    final detail = _detail;
    final firstPost = detail?.firstPost;
    final isOwnTopic = detail != null &&
        !detail.isPrivateMessage &&
        (firstPost?.yours == true ||
            topic.originalPosterId == widget.repository.profile.id);
    if (detail == null ||
        detail.isPrivateMessage ||
        !isOwnTopic ||
        !detail.canDelete) {
      await _showTopicDeleteUnavailable();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除这个主题？'),
          content: const Text(
            '删除后帖子将无法恢复。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _deletingTopic = true);
    try {
      await widget.repository.deleteTopic(topic);
      if (!mounted) {
        return;
      }
      _showSnack('主题已删除');
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      await _handleOperationError(
        error,
        title: '无法删除主题',
        fallbackMessage: '该主题已有回复或超过论坛允许删除的时限，需联系版主处理。',
      );
    } finally {
      if (mounted) {
        setState(() => _deletingTopic = false);
      }
    }
  }

  Future<void> _toggleTopicBookmark(
    TopicListItem topic,
    ForumBookmark? current,
  ) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return;
    }
    try {
      if (current != null && current.id > 0) {
        await widget.repository.unbookmarkTopic(current.id);
        if (!mounted) {
          return;
        }
        widget.onBookmarkChanged?.call();
        _showSnack('已取消收藏');
        return;
      }
      await widget.repository.bookmarkTopic(topic.id);
      if (!mounted) {
        return;
      }
      widget.onBookmarkChanged?.call();
      _showSnack('已收藏');
    } on Object catch (error) {
      await _handleOperationError(error, title: '收藏操作失败');
    }
  }

  Future<void> _openUserProfile(String username) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return;
    }
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => UserProfilePage(
          repository: widget.repository,
          username: username,
        ),
      ),
    );
  }

  Future<void> _handleOperationError(
    Object error, {
    required String title,
    String? fallbackMessage,
  }) async {
    if (error is ForumAuthException) {
      await widget.onSessionExpired?.call();
      await _showErrorDialog(
        title: '登录已失效',
        message: '请试着重新登录后再操作。',
      );
      return;
    }
    await _showErrorDialog(
      title: title,
      message: _friendlyError(error, fallbackMessage: fallbackMessage),
    );
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showErrorDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  String _friendlyError(Object error, {String? fallbackMessage}) {
    if (error is ForumApiException) {
      if (fallbackMessage != null && _isGenericForumError(error.message)) {
        return fallbackMessage;
      }
      return error.message;
    }
    return fallbackMessage ?? '操作失败，请稍后重试';
  }

  bool _isGenericForumError(String message) {
    return message == '论坛请求失败' ||
        message == '论坛返回的不是 JSON，可能需要重新登录' ||
        message == '操作失败，请稍后重试' ||
        message.contains('无权') ||
        message.contains('没有权限') ||
        message.toLowerCase().contains('forbidden');
  }
}

class _TopicMoreSheet extends StatelessWidget {
  const _TopicMoreSheet({
    required this.bookmarkFuture,
    required this.showDeleteTopic,
    required this.canDeleteTopic,
    required this.deletingTopic,
    required this.onClose,
    required this.onShare,
    required this.onReport,
    required this.onBookmark,
    required this.onDeleteTopic,
    required this.onDeleteTopicUnavailable,
  });

  final Future<ForumBookmark?> bookmarkFuture;
  final bool showDeleteTopic;
  final bool canDeleteTopic;
  final bool deletingTopic;
  final VoidCallback onClose;
  final VoidCallback onShare;
  final VoidCallback onReport;
  final ValueChanged<ForumBookmark?> onBookmark;
  final VoidCallback onDeleteTopic;
  final VoidCallback onDeleteTopicUnavailable;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '更多',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TopicActionButton(
                    icon: Icons.ios_share,
                    label: '分享',
                    onTap: onShare,
                  ),
                ),
                Expanded(
                  child: _TopicActionButton(
                    icon: Icons.flag_outlined,
                    label: '举报',
                    onTap: onReport,
                  ),
                ),
                Expanded(
                  child: FutureBuilder<ForumBookmark?>(
                    future: bookmarkFuture,
                    builder: (context, snapshot) {
                      final loading =
                          snapshot.connectionState != ConnectionState.done;
                      final bookmark = snapshot.data;
                      final bookmarked = bookmark != null && bookmark.id > 0;
                      return _TopicActionButton(
                        icon:
                            bookmarked ? Icons.bookmark : Icons.bookmark_border,
                        label: bookmarked ? '取消收藏' : '收藏',
                        onTap: loading ? null : () => onBookmark(bookmark),
                      );
                    },
                  ),
                ),
                if (showDeleteTopic)
                  Expanded(
                    child: _TopicActionButton(
                      icon: Icons.delete_outline,
                      label: canDeleteTopic ? '删除主题' : '无法删帖',
                      onTap: deletingTopic
                          ? null
                          : canDeleteTopic
                              ? onDeleteTopic
                              : onDeleteTopicUnavailable,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicActionButton extends StatelessWidget {
  const _TopicActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final colors = context.lehuColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: SizedBox(
        height: 88,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 26,
              color: enabled ? colors.textSecondary : colors.textMuted,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: enabled ? colors.textPrimary : colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(message, style: TextStyle(color: colors.textSecondary)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: title,
      message: message,
      action: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重试'),
      ),
    );
  }
}
