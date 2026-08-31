import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/forum_activity.dart';
import '../../data/models/forum_poll.dart';
import '../../data/models/forum_report.dart';
import '../../data/models/forum_search.dart';
import '../../data/models/post.dart';
import '../../data/models/topic.dart';
import '../../data/models/topic_detail.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/discourse_api_client.dart';
import '../../data/services/html_text.dart';
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
    this.targetPostNumber,
    this.onRecoverConnection,
    this.onLoginRequired,
    this.onSessionExpired,
    this.onBookmarkChanged,
    this.onOpenForumRoute,
  });

  final ForumRepository repository;
  final TopicListItem topic;
  final int? targetPostNumber;
  final Future<ForumRecoveryResult> Function()? onRecoverConnection;
  final Future<void> Function()? onLoginRequired;
  final Future<void> Function()? onSessionExpired;
  final VoidCallback? onBookmarkChanged;
  final ValueChanged<String>? onOpenForumRoute;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage>
    with WidgetsBindingObserver {
  static const _topicTimingFlushInterval = Duration(seconds: 30);
  static const _topicTimingMinFlushMs = 1000;
  static const _topicTimingMinSampleMs = 250;

  Future<TopicDetail?>? _future;
  TopicDetail? _detail;
  bool _submittingReply = false;
  bool _deletingTopic = false;
  bool _flushingTopicTimings = false;
  Timer? _topicTimingFlushTimer;
  int _pendingTopicTimingMs = 0;
  final _pendingPostTimingMs = <int, int>{};
  final _likingPostIds = <int>{};
  final _busyPollKeys = <String>{};
  final _deletingPostIds = <int>{};
  final _reportingPostIds = <int>{};
  final _reportedPostIds = <int>{};
  final _reportingTopicIds = <int>{};
  final _reportedTopicIds = <int>{};
  final _topicPageController = TopicPageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final cached = widget.repository.cachedTopicDetail(widget.topic.id);
    _detail = _canUseInitialDetail(cached) ? cached : null;
    _future = widget.repository.fetchTopicDetail(
      widget.topic.id,
      forceRefresh: true,
      trackVisit: true,
    );
  }

  @override
  void dispose() {
    _topicTimingFlushTimer?.cancel();
    unawaited(_flushTopicTimings(force: true));
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushTopicTimings(force: true));
    }
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
              onTitleTap: _topicPageController.collapseComposer,
              onTitleDoubleTap: _topicPageController.scrollToTop,
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
                  final waitingForTarget = detail != null &&
                      !_detailContainsTargetPost(detail) &&
                      snapshot.connectionState != ConnectionState.done;
                  if ((detail == null || waitingForTarget) &&
                      snapshot.connectionState != ConnectionState.done) {
                    return const _LoadingState();
                  }
                  if (detail == null && snapshot.hasError) {
                    return _ErrorState(
                      title: '帖子加载失败',
                      message: _topicLoadError(snapshot.error!),
                      onRetry:
                          widget.repository.hasLocalAccount ? _refresh : null,
                    );
                  }
                  if (detail == null &&
                      snapshot.connectionState == ConnectionState.done) {
                    return const EmptyState(
                      icon: Icons.article_outlined,
                      title: '无法连接论坛',
                      message: '请尝试重新登录。',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: TopicPage(
                      controller: _topicPageController,
                      item: widget.topic,
                      detail: detail,
                      targetPostNumber: widget.targetPostNumber,
                      category: widget.repository.categoryById(
                        detail?.categoryId ?? widget.topic.categoryId,
                      ),
                      currentUsername: widget.repository.profile.username,
                      isOnline: widget.repository.isOnline,
                      isSubmittingReply: _submittingReply,
                      busyLikePostIds: _likingPostIds,
                      busyPollKeys: _busyPollKeys,
                      busyDeletePostIds: _deletingPostIds,
                      busyReportPostIds: _reportingPostIds,
                      reportedPostIds: _reportedPostIds,
                      onLikePost: _togglePostLike,
                      onVotePoll: _votePoll,
                      onTogglePollStatus: _togglePollStatus,
                      onDeletePost: _deletePost,
                      onReportPost: _reportPost,
                      onUploadImage: widget.repository.uploadImage,
                      onCreateReply: _createReply,
                      onOpenUser: _openUserProfile,
                      onOpenInternalTopic: _openInternalTopic,
                      onSearchUsers: _searchUsers,
                      onLoginRequired: () => unawaited(_requireLogin()),
                      onReadingTimingSample: _recordReadingTimingSample,
                      onReadingTimingFlush: () => unawaited(
                        _flushTopicTimings(force: true),
                      ),
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

  bool _canUseInitialDetail(TopicDetail? detail) {
    if (detail == null) {
      return false;
    }
    return _detailContainsTargetPost(detail);
  }

  bool _detailContainsTargetPost(TopicDetail detail) {
    final targetPostNumber = widget.targetPostNumber;
    if (targetPostNumber == null || targetPostNumber <= 0) {
      return true;
    }
    return detail.posts.any((post) => post.postNumber == targetPostNumber);
  }

  Future<void> _requireLogin() async {
    if (widget.repository.hasLocalAccount && !widget.repository.isOnline) {
      _showSnack('无法连接论坛，请尝试重新登录。');
      return;
    }
    await widget.onLoginRequired?.call();
  }

  void _recordReadingTimingSample(Set<int> postNumbers, Duration elapsed) {
    if (!mounted ||
        postNumbers.isEmpty ||
        elapsed.inMilliseconds < _topicTimingMinSampleMs) {
      return;
    }
    final detail = _detail;
    if (detail == null ||
        detail.isPrivateMessage ||
        !widget.repository.isOnline) {
      return;
    }
    final validPostNumbers = detail.posts
        .where((post) => !post.isDeleted && post.postNumber > 0)
        .map((post) => post.postNumber)
        .toSet();
    final visiblePostNumbers = postNumbers
        .where(validPostNumbers.contains)
        .toList(growable: false)
      ..sort();
    if (visiblePostNumbers.isEmpty) {
      return;
    }
    final elapsedMs = elapsed.inMilliseconds;
    _pendingTopicTimingMs += elapsedMs;
    for (final postNumber in visiblePostNumbers) {
      _pendingPostTimingMs[postNumber] =
          (_pendingPostTimingMs[postNumber] ?? 0) + elapsedMs;
    }
    if (_pendingTopicTimingMs >= _topicTimingFlushInterval.inMilliseconds) {
      unawaited(_flushTopicTimings());
      return;
    }
    _scheduleTopicTimingFlush();
  }

  void _scheduleTopicTimingFlush() {
    if (_topicTimingFlushTimer?.isActive == true) {
      return;
    }
    _topicTimingFlushTimer = Timer(
      _topicTimingFlushInterval,
      () {
        _topicTimingFlushTimer = null;
        unawaited(_flushTopicTimings());
      },
    );
  }

  Future<void> _flushTopicTimings({bool force = false}) async {
    _topicTimingFlushTimer?.cancel();
    _topicTimingFlushTimer = null;
    if (_flushingTopicTimings) {
      return;
    }
    final detail = _detail;
    if (detail == null ||
        detail.isPrivateMessage ||
        !widget.repository.isOnline ||
        _pendingTopicTimingMs < _topicTimingMinFlushMs ||
        _pendingPostTimingMs.isEmpty) {
      return;
    }
    final topicTimeMs = _pendingTopicTimingMs;
    final postTimingsMs = Map<int, int>.from(_pendingPostTimingMs);
    _pendingTopicTimingMs = 0;
    _pendingPostTimingMs.clear();
    _flushingTopicTimings = true;
    try {
      await widget.repository.recordTopicTimings(
        detail.id,
        postTimingsMs: postTimingsMs,
        topicTimeMs: topicTimeMs,
      );
    } on Object {
      _pendingTopicTimingMs += topicTimeMs;
      for (final entry in postTimingsMs.entries) {
        _pendingPostTimingMs[entry.key] =
            (_pendingPostTimingMs[entry.key] ?? 0) + entry.value;
      }
      if (!force) {
        _scheduleTopicTimingFlush();
      }
    } finally {
      _flushingTopicTimings = false;
    }
  }

  Future<void> _refresh() async {
    var repository = widget.repository;
    if (!widget.repository.isOnline) {
      final recovery = await widget.onRecoverConnection?.call() ??
          ForumRecoveryResult(
            status: ForumRecoveryStatus.unavailable,
            repository: widget.repository,
          );
      if (!recovery.isRestored || !recovery.repository.isOnline) {
        _showSnack(_forumRecoveryMessage(recovery));
        return;
      }
      repository = recovery.repository;
    }
    final future = repository.fetchTopicDetail(
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
    } on Object catch (error) {
      if (error is ForumAuthException) {
        repository.markAuthenticationRequired();
      } else if (_isForumTransportError(error)) {
        repository.markConnectionUnavailable();
      }
      if (mounted) {
        _showSnack(_refreshFailureMessage(error, prefix: '刷新失败'));
        setState(() {});
      }
    }
  }

  Future<bool> _createReply(ReplyDraft draft) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return false;
    }
    if (_submittingReply) {
      return false;
    }
    setState(() => _submittingReply = true);
    try {
      await widget.repository.createReply(draft);
      if (!mounted) {
        return false;
      }
      _showSnack('评论已发布');
      await _refresh();
      return true;
    } on Object catch (error) {
      await _handleOperationError(error, title: '评论失败');
      return false;
    } finally {
      if (mounted) {
        setState(() => _submittingReply = false);
      }
    }
  }

  Future<List<SearchUserResult>> _searchUsers(String query) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return const [];
    }
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const [];
    }
    final result = await widget.repository.searchForum(
      normalized,
      mode: ForumSearchMode.users,
    );
    return result.users;
  }

  Future<void> _openInternalTopic(CookedLinkPreview preview) async {
    if (preview.isInternalForumRoute) {
      widget.onOpenForumRoute?.call(preview.url);
      return;
    }
    final topicId = preview.topicId;
    if (topicId == null || !mounted) {
      return;
    }
    final deleted = await Navigator.of(context).push<bool>(
      lehuRoute(
        builder: (context) => TopicDetailPage(
          repository: widget.repository,
          topic: TopicListItem(
            id: topicId,
            title: preview.title,
            postsCount: 0,
            replyCount: 0,
            highestPostNumber: preview.postNumber ?? 1,
            views: 0,
            likeCount: 0,
            categoryId: 0,
            posters: const [],
          ),
          targetPostNumber: preview.postNumber,
          onRecoverConnection: widget.onRecoverConnection,
          onLoginRequired: widget.onLoginRequired,
          onSessionExpired: widget.onSessionExpired,
          onBookmarkChanged: widget.onBookmarkChanged,
          onOpenForumRoute: widget.onOpenForumRoute,
        ),
      ),
    );
    if (deleted == true && mounted) {
      Navigator.of(context).pop(true);
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

  Future<void> _votePoll(
    Post post,
    ForumPoll poll,
    List<String> optionIds,
  ) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return;
    }
    final key = _pollKey(post, poll);
    if (_busyPollKeys.contains(key)) {
      return;
    }
    setState(() => _busyPollKeys.add(key));
    try {
      await widget.repository.votePoll(
        topicId: post.topicId,
        postId: post.id,
        pollName: poll.name,
        optionIds: optionIds,
      );
      if (!mounted) {
        return;
      }
      _showSnack(poll.hasVoted ? '已修改投票' : '已投票');
      await _refresh();
    } on Object catch (error) {
      await _handleOperationError(error, title: '投票失败');
    } finally {
      if (mounted) {
        setState(() => _busyPollKeys.remove(key));
      }
    }
  }

  Future<void> _togglePollStatus(
    Post post,
    ForumPoll poll,
    String status,
  ) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return;
    }
    final key = _pollKey(post, poll);
    if (_busyPollKeys.contains(key)) {
      return;
    }
    setState(() => _busyPollKeys.add(key));
    try {
      await widget.repository.togglePollStatus(
        topicId: post.topicId,
        postId: post.id,
        pollName: poll.name,
        status: status,
      );
      if (!mounted) {
        return;
      }
      _showSnack(status == 'closed' ? '投票已关闭' : '投票已开启');
      await _refresh();
    } on Object catch (error) {
      await _handleOperationError(error, title: '投票设置失败');
    } finally {
      if (mounted) {
        setState(() => _busyPollKeys.remove(key));
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
      await _handleDeletePostError(error, post);
    } finally {
      if (mounted) {
        setState(() => _deletingPostIds.remove(post.id));
      }
    }
  }

  Future<void> _reportPost(Post post) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return;
    }
    if (_isPostReported(post)) {
      _showSnack('已提交过举报，请等待管理员处理');
      return;
    }
    if (_reportingPostIds.contains(post.id)) {
      return;
    }
    final selection = await _showReportReasonSheet(
      title: post.postNumber == 1 ? '举报首楼' : '举报回复',
      reasons: ForumReportReason.optionsForPost(),
      flagTopic: false,
    );
    if (selection == null || !mounted) {
      return;
    }
    setState(() => _reportingPostIds.add(post.id));
    try {
      await widget.repository.reportContent(
        ForumReportDraft(
          id: post.id,
          reason: selection.reason,
          message: selection.message,
          flagTopic: false,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() => _reportedPostIds.add(post.id));
      _showSnack('举报已提交');
      await _refresh();
    } on Object catch (error) {
      await _handleOperationError(
        error,
        title: '举报失败',
        fallbackMessage: '已提交过举报，请等待管理员处理。',
      );
    } finally {
      if (mounted) {
        setState(() => _reportingPostIds.remove(post.id));
      }
    }
  }

  Future<void> _reportTopic(TopicListItem topic) async {
    if (!widget.repository.isOnline) {
      await _requireLogin();
      return;
    }
    if (_isTopicReported(topic)) {
      _showSnack('已提交过举报，请等待管理员处理');
      return;
    }
    if (_reportingTopicIds.contains(topic.id)) {
      return;
    }
    final selection = await _showReportReasonSheet(
      title: '举报主题',
      reasons: ForumReportReason.optionsForTopic(),
      flagTopic: true,
    );
    if (selection == null || !mounted) {
      return;
    }
    setState(() => _reportingTopicIds.add(topic.id));
    try {
      final post = await widget.repository.reportContent(
        ForumReportDraft(
          id: topic.id,
          reason: selection.reason,
          message: selection.message,
          flagTopic: true,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _reportedTopicIds.add(topic.id);
        if (post.id > 0) {
          _reportedPostIds.add(post.id);
        }
      });
      _showSnack('举报已提交');
      await _refresh();
    } on Object catch (error) {
      await _handleOperationError(
        error,
        title: '举报失败',
        fallbackMessage: '已提交过举报，请等待管理员处理。',
      );
    } finally {
      if (mounted) {
        setState(() => _reportingTopicIds.remove(topic.id));
      }
    }
  }

  bool _isPostReported(Post post) {
    return post.reported || _reportedPostIds.contains(post.id);
  }

  bool _isTopicReported(TopicListItem topic) {
    return _reportedTopicIds.contains(topic.id) ||
        _reportedPostIds.contains(_detail?.firstPost?.id) ||
        (_detail?.firstPost?.reported ?? false);
  }

  Future<_ReportSelection?> _showReportReasonSheet({
    required String title,
    required List<ForumReportReason> reasons,
    required bool flagTopic,
  }) {
    return showModalBottomSheet<_ReportSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        return _ReportReasonSheet(
          title: title,
          reasons: reasons,
          flagTopic: flagTopic,
        );
      },
    );
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
          reportLabel: _isTopicReported(topic) ? '已举报' : '举报',
          canReport: !_isTopicReported(topic) &&
              !_reportingTopicIds.contains(topic.id),
          onClose: () => Navigator.of(context).pop(),
          onShare: () {
            Navigator.of(context).pop();
            unawaited(_shareTopic(topic));
          },
          onReport: () {
            Navigator.of(context).pop();
            unawaited(_reportTopic(topic));
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
      message: '该主题已有回复或超过论坛允许删除的时限。\n\n如果您确实希望将其删除，请提交举报并说明原因，以便引起版主注意。',
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
        fallbackMessage:
            '该主题已有回复或超过论坛允许删除的时限。\n\n如果您确实希望将其删除，请提交举报并说明原因，以便引起版主注意。',
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

  Future<void> _handleDeletePostError(Object error, Post post) async {
    if (error is ForumAuthException) {
      await widget.onSessionExpired?.call();
      await _showErrorDialog(
        title: '登录已失效',
        message: '请试着重新登录后再操作。',
      );
      return;
    }
    await _showErrorDialog(
      title: '无法删除回复',
      message: _deletePostErrorMessage(error, post),
    );
  }

  String _deletePostErrorMessage(Object error, Post post) {
    const moderatorMessage =
        '该回复可能已超过论坛允许删除的时限，或当前状态不允许客户端删除。\n\n如果您确实希望将其删除，请提交举报并说明原因，以便引起版主注意。';
    if (error is ForumApiException) {
      if (!_isGenericForumError(error.message)) {
        return error.message;
      }
      if (error.message == forumRefreshTooFastMessage) {
        return '删除请求过于频繁，请稍后再试。';
      }
      if (!post.canDelete || _isPermissionForumError(error)) {
        return moderatorMessage;
      }
      return '删除请求失败，请稍后再试。';
    }
    return post.canDelete ? '删除失败，请稍后再试。' : moderatorMessage;
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

  String _topicLoadError(Object error) {
    if (error is ForumApiException && _isGenericForumError(error.message)) {
      return '加载失败，请稍后再试，或检查登录状态。';
    }
    return _friendlyError(error);
  }

  bool _isPermissionForumError(ForumApiException error) {
    final code = error.statusCode;
    final message = error.message;
    return code == 403 ||
        message.contains('无权') ||
        message.contains('没有权限') ||
        message.toLowerCase().contains('forbidden');
  }

  bool _isGenericForumError(String message) {
    return message == '论坛请求失败' ||
        message == forumRefreshTooFastMessage ||
        message == '论坛返回的不是 JSON，可能需要重新登录' ||
        message == '操作失败，请稍后重试' ||
        message.contains('无权') ||
        message.contains('没有权限') ||
        message.toLowerCase().contains('forbidden');
  }
}

class _ReportSelection {
  const _ReportSelection({
    required this.reason,
    this.message,
  });

  final ForumReportReason reason;
  final String? message;
}

String _pollKey(Post post, ForumPoll poll) {
  return '${post.id}:${poll.name}';
}

class _ReportReasonSheet extends StatefulWidget {
  const _ReportReasonSheet({
    required this.title,
    required this.reasons,
    required this.flagTopic,
  });

  final String title;
  final List<ForumReportReason> reasons;
  final bool flagTopic;

  @override
  State<_ReportReasonSheet> createState() => _ReportReasonSheetState();
}

class _ReportReasonSheetState extends State<_ReportReasonSheet> {
  late ForumReportReason _selected = widget.reasons.first;
  final _messageController = TextEditingController();

  bool get _needsMessage => _selected.requiresMessage;

  bool get _canSubmit {
    if (!_needsMessage) {
      return true;
    }
    return _messageController.text.trim().length >= 3;
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(8),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16.5,
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
              const SizedBox(height: 6),
              for (final reason in widget.reasons)
                _ReportReasonTile(
                  reason: reason,
                  description: reason.description(
                    flagTopic: widget.flagTopic,
                  ),
                  selected: reason == _selected,
                  onTap: () => setState(() => _selected = reason),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: _needsMessage
                    ? Padding(
                        key: const ValueKey('report-message'),
                        padding: const EdgeInsets.only(top: 4, bottom: 12),
                        child: TextField(
                          controller: _messageController,
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 160,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: '请补充说明，至少 3 个字符',
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('no-message')),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canSubmit
                      ? () {
                          Navigator.of(context).pop(
                            _ReportSelection(
                              reason: _selected,
                              message: _needsMessage
                                  ? _messageController.text.trim()
                                  : null,
                            ),
                          );
                        }
                      : null,
                  child: const Text('提交举报'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportReasonTile extends StatelessWidget {
  const _ReportReasonTile({
    required this.reason,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final ForumReportReason reason;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final activeColor = Theme.of(context).colorScheme.primary;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? activeColor : colors.textMuted,
      ),
      title: Text(
        reason.label,
        style: TextStyle(color: colors.textPrimary),
      ),
      subtitle: selected
          ? Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                description,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            )
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _TopicMoreSheet extends StatelessWidget {
  const _TopicMoreSheet({
    required this.bookmarkFuture,
    required this.showDeleteTopic,
    required this.canDeleteTopic,
    required this.deletingTopic,
    required this.reportLabel,
    required this.canReport,
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
  final String reportLabel;
  final bool canReport;
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
                    label: reportLabel,
                    onTap: canReport ? onReport : null,
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

String _forumRecoveryMessage(ForumRecoveryResult result) {
  if (result.status == ForumRecoveryStatus.requiresReauthentication) {
    return '登录状态已失效，请尝试重新登录';
  }
  final error = result.error;
  if (error is ForumApiException &&
      error.message != forumRefreshTooFastMessage) {
    return error.message;
  }
  return '无法连接论坛，请尝试重新登录。';
}

String _refreshFailureMessage(Object error, {required String prefix}) {
  if (error is ForumAuthException) {
    return '登录状态已失效，请尝试重新登录';
  }
  if (error is ForumApiException) {
    if (error.message == forumRefreshTooFastMessage) {
      return error.message;
    }
    return '$prefix：${error.message}';
  }
  return '$prefix：操作失败，请稍后重试';
}

bool _isForumTransportError(Object error) {
  return error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException ||
      error is HttpException;
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(strokeWidth: 3),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
    );
  }
}
