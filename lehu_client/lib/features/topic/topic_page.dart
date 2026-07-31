import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/forum_url_resolver.dart';
import '../../data/models/category.dart';
import '../../data/models/composer.dart';
import '../../data/models/post.dart';
import '../../data/models/topic.dart';
import '../../data/models/topic_detail.dart';
import '../../data/services/forum_draft_store.dart';
import '../../data/services/forum_read_position_store.dart';
import '../../data/services/html_text.dart';
import '../../data/services/local_image_picker.dart';
import '../../data/services/payload_factory.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/composer_attachments.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/forum_cooked_content.dart';
import '../../shared/widgets/forum_network_image.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/fullscreen_image_page.dart';
import '../../shared/widgets/inline_emoji_panel.dart';
import 'threaded_posts.dart';

class TopicPage extends StatefulWidget {
  const TopicPage({
    super.key,
    this.controller,
    required this.item,
    required this.detail,
    required this.category,
    required this.currentUsername,
    required this.onCreateReply,
    required this.onUploadImage,
    required this.onLikePost,
    required this.onDeletePost,
    required this.onOpenUser,
    required this.onOpenInternalTopic,
    required this.onLoginRequired,
    required this.isOnline,
    required this.isSubmittingReply,
    required this.busyLikePostIds,
    required this.busyDeletePostIds,
  });

  final TopicPageController? controller;
  final TopicListItem item;
  final TopicDetail? detail;
  final ForumCategory? category;
  final String currentUsername;
  final bool isOnline;
  final bool isSubmittingReply;
  final Set<int> busyLikePostIds;
  final Set<int> busyDeletePostIds;
  final Future<bool> Function(ReplyDraft draft) onCreateReply;
  final Future<UploadedImage> Function(PickedImage image) onUploadImage;
  final ValueChanged<Post> onLikePost;
  final ValueChanged<Post> onDeletePost;
  final ValueChanged<String> onOpenUser;
  final ValueChanged<CookedLinkPreview> onOpenInternalTopic;
  final VoidCallback onLoginRequired;

  @override
  State<TopicPage> createState() => _TopicPageState();
}

class TopicPageController {
  _TopicPageState? _state;

  void collapseComposer() {
    _state?._collapseComposerForBrowsing();
  }

  void scrollToTop() {
    _state?._scrollToTop();
  }

  void _attach(_TopicPageState state) {
    _state = state;
  }

  void _detach(_TopicPageState state) {
    if (_state == state) {
      _state = null;
    }
  }
}

class _TopicPageState extends State<TopicPage> with WidgetsBindingObserver {
  static const _collapsedReplyCount = 2;
  static const _readPositionSaveDelay = Duration(milliseconds: 700);
  static const _readPositionRestoredMessageDuration =
      Duration(milliseconds: 1200);
  static const _readPositionToastBottom = 76.0;
  static const _minimumSavedReadOffset = 80.0;
  static const _readPositionBottomSnapDistance = 180.0;
  static const _readPositionLateCorrectionDelay = Duration(milliseconds: 280);
  static const _readPositionBottomCorrectionWindow = Duration(
    milliseconds: 900,
  );
  static const _readPositionBottomCorrectionStep = Duration(milliseconds: 100);
  static const _readPositionImmediateSaveThrottle = Duration(milliseconds: 260);

  final _expandedReplyParents = <int>{};
  final _replyBarKey = GlobalKey<_TopicReplyBarState>();
  final _scrollViewKey = GlobalKey();
  final _scrollController = ScrollController();
  final _postKeys = <int, GlobalKey>{};
  Timer? _readPositionSaveTimer;
  Timer? _readPositionToastTimer;
  DateTime? _lastImmediateReadPositionSaveAt;
  String? _restoredReadPositionKey;
  bool _restoringReadPosition = false;
  bool _cancelReadPositionCorrection = false;
  bool _showReadPositionToast = false;

  String get _readPositionKey {
    return ForumReadPositionStore.topicKey(
      username: widget.currentUsername,
      topicId: widget.detail?.id ?? widget.item.id,
    );
  }

  GlobalKey _postKeyFor(int postNumber) {
    return _postKeys.putIfAbsent(postNumber, () => GlobalKey());
  }

  void _pruneReadPositionKeys(List<Post> posts) {
    final postNumbers = posts.map((post) => post.postNumber).toSet();
    _postKeys.removeWhere((postNumber, _) => !postNumbers.contains(postNumber));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScrollChanged);
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant TopicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    final oldTopicId = oldWidget.detail?.id ?? oldWidget.item.id;
    final nextTopicId = widget.detail?.id ?? widget.item.id;
    if (oldTopicId != nextTopicId ||
        oldWidget.currentUsername != widget.currentUsername) {
      _readPositionSaveTimer?.cancel();
      _restoredReadPositionKey = null;
      _restoringReadPosition = false;
      _cancelReadPositionCorrection = true;
      _postKeys.clear();
    }
  }

  @override
  void dispose() {
    _readPositionSaveTimer?.cancel();
    _readPositionToastTimer?.cancel();
    unawaited(_saveReadPositionNow());
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_handleScrollChanged);
    widget.controller?._detach(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    if (detail == null) {
      return EmptyState(
        icon: Icons.article_outlined,
        title: '本地暂无详情',
        message: '这个主题还没有放入 fixture。接入网络请求后会按 topic id 加载完整内容。',
      );
    }

    final threads = buildThreadedPosts(
      detail.posts.where((post) => !post.isDeleted).toList(growable: false),
    );
    _pruneReadPositionKeys(detail.posts);
    _scheduleReadPositionRestore();

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleContentTap,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: ListView(
                    key: _scrollViewKey,
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      _TopicHeader(detail: detail, category: widget.category),
                      for (final thread in threads)
                        _ThreadedPostView(
                          thread: thread,
                          canReply: detail.canCreatePost,
                          isSubmittingReply: widget.isSubmittingReply,
                          busyLikePostIds: widget.busyLikePostIds,
                          busyDeletePostIds: widget.busyDeletePostIds,
                          expanded: _expandedReplyParents.contains(
                            thread.post.postNumber,
                          ),
                          collapsedReplyCount: _collapsedReplyCount,
                          onToggleExpanded: () {
                            setState(() {
                              final parent = thread.post.postNumber;
                              if (!_expandedReplyParents.add(parent)) {
                                _expandedReplyParents.remove(parent);
                              }
                            });
                          },
                          onReply: _replyTo,
                          onLike: _like,
                          onDelete: _confirmDelete,
                          onOpenUser: widget.onOpenUser,
                          onOpenImage: _openImagePreview,
                          onOpenInternalTopic: widget.onOpenInternalTopic,
                          postKeyFor: _postKeyFor,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _ReplyBar(
              key: _replyBarKey,
              enabled: detail.canCreatePost && !widget.isSubmittingReply,
              isOnline: widget.isOnline,
              isSubmitting: widget.isSubmittingReply,
              detail: detail,
              currentUsername: widget.currentUsername,
              onLoginRequired: widget.onLoginRequired,
              onUploadImage: widget.onUploadImage,
              onSubmit: widget.onCreateReply,
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: _readPositionToastBottom,
          child: IgnorePointer(
            child: _ReadPositionToast(visible: _showReadPositionToast),
          ),
        ),
      ],
    );
  }

  void _handleContentTap() {
    _replyBarKey.currentState?.handleOutsideTap();
  }

  void _collapseComposerForBrowsing() {
    _replyBarKey.currentState?.collapseForBrowsing();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveReadPositionNow());
    }
  }

  void _handleScrollChanged() {
    if (_restoringReadPosition) {
      return;
    }
    _readPositionSaveTimer?.cancel();
    _readPositionSaveTimer = Timer(
      _readPositionSaveDelay,
      () => unawaited(_saveReadPositionNow()),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical || widget.detail == null) {
      return false;
    }
    if (_isUserScrollStart(notification) && _restoringReadPosition) {
      _cancelReadPositionCorrection = true;
      _restoringReadPosition = false;
    }
    if (_restoringReadPosition) {
      return false;
    }
    if (notification is ScrollEndNotification ||
        notification.metrics.extentAfter <= _readPositionBottomSnapDistance) {
      _saveReadPositionImmediately();
    }
    return false;
  }

  bool _isUserScrollStart(ScrollNotification notification) {
    return notification is ScrollStartNotification &&
        notification.dragDetails != null;
  }

  void _saveReadPositionImmediately() {
    final now = DateTime.now();
    final lastSavedAt = _lastImmediateReadPositionSaveAt;
    if (lastSavedAt != null &&
        now.difference(lastSavedAt) < _readPositionImmediateSaveThrottle) {
      return;
    }
    _lastImmediateReadPositionSaveAt = now;
    _readPositionSaveTimer?.cancel();
    unawaited(_saveReadPositionNow());
  }

  void _scheduleReadPositionRestore() {
    final key = _readPositionKey;
    if (_restoredReadPositionKey == key) {
      return;
    }
    _restoredReadPositionKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreReadPosition(key));
    });
  }

  Future<void> _restoreReadPosition(String key) async {
    if (!mounted || !_scrollController.hasClients) {
      if (_restoredReadPositionKey == key) {
        _restoredReadPositionKey = null;
      }
      return;
    }
    final position = await ForumReadPositionStore.load(key);
    if (!mounted ||
        position == null ||
        key != _readPositionKey ||
        !_scrollController.hasClients) {
      return;
    }
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    if (!_hasRestorableReadPosition(position, maxScrollExtent)) {
      return;
    }
    _cancelReadPositionCorrection = false;
    _restoringReadPosition = true;
    final restored = _applyRestoredReadPosition(
      position,
      allowOffsetFallback: true,
    );
    if (!restored) {
      _restoringReadPosition = false;
      return;
    }
    _showRestoredReadPositionToast();
    unawaited(_stabilizeReadPositionRestore(key, position));
  }

  bool _hasRestorableReadPosition(
    ForumReadPosition position,
    double maxScrollExtent,
  ) {
    if (maxScrollExtent <= _minimumSavedReadOffset) {
      return false;
    }
    if (_isBottomReadPosition(position)) {
      return true;
    }
    return position.offset >= _minimumSavedReadOffset;
  }

  Future<void> _stabilizeReadPositionRestore(
    String key,
    ForumReadPosition position,
  ) async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          key != _readPositionKey ||
          _cancelReadPositionCorrection) {
        return;
      }
      if (_isBottomReadPosition(position)) {
        await _keepRestoredReadPositionAtBottom(key);
        return;
      }
      _applyRestoredReadPosition(position, allowOffsetFallback: false);
      await Future<void>.delayed(_readPositionLateCorrectionDelay);
      if (!mounted ||
          key != _readPositionKey ||
          _cancelReadPositionCorrection) {
        return;
      }
      _applyRestoredReadPosition(position, allowOffsetFallback: false);
    } finally {
      if (mounted && key == _readPositionKey) {
        _restoringReadPosition = false;
      }
    }
  }

  Future<void> _keepRestoredReadPositionAtBottom(String key) async {
    final startedAt = DateTime.now();
    while (mounted &&
        key == _readPositionKey &&
        !_cancelReadPositionCorrection &&
        DateTime.now().difference(startedAt) <
            _readPositionBottomCorrectionWindow) {
      if (!_scrollController.hasClients) {
        return;
      }
      _jumpToReadOffset(_scrollController.position.maxScrollExtent);
      await Future<void>.delayed(_readPositionBottomCorrectionStep);
    }
    if (mounted &&
        key == _readPositionKey &&
        !_cancelReadPositionCorrection &&
        _scrollController.hasClients) {
      _jumpToReadOffset(_scrollController.position.maxScrollExtent);
    }
  }

  bool _applyRestoredReadPosition(
    ForumReadPosition position, {
    required bool allowOffsetFallback,
  }) {
    if (!mounted || !_scrollController.hasClients) {
      return false;
    }
    if (_isBottomReadPosition(position)) {
      return _jumpToReadOffset(_scrollController.position.maxScrollExtent);
    }
    final anchorPostNumber = position.anchorPostNumber;
    if (anchorPostNumber != null) {
      final anchorTarget = _targetOffsetForPostAnchor(
        anchorPostNumber,
        position.anchorDelta,
      );
      if (anchorTarget != null) {
        return _jumpToReadOffset(anchorTarget);
      }
    }
    if (allowOffsetFallback) {
      return _jumpToReadOffset(position.offset);
    }
    return false;
  }

  bool _isBottomReadPosition(ForumReadPosition position) {
    final bottomDistance = position.bottomDistance;
    return bottomDistance != null &&
        bottomDistance <= _readPositionBottomSnapDistance;
  }

  bool _jumpToReadOffset(double offset) {
    if (!_scrollController.hasClients) {
      return false;
    }
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    if (maxScrollExtent <= 0) {
      return false;
    }
    final target = offset.clamp(0.0, maxScrollExtent).toDouble();
    _scrollController.jumpTo(target);
    return true;
  }

  double? _targetOffsetForPostAnchor(int postNumber, double anchorDelta) {
    if (!_scrollController.hasClients) {
      return null;
    }
    final viewportBox =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    final postBox =
        _postKeys[postNumber]?.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null ||
        postBox == null ||
        !viewportBox.attached ||
        !postBox.attached ||
        !viewportBox.hasSize ||
        !postBox.hasSize) {
      return null;
    }
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final postTop = postBox.localToGlobal(Offset.zero).dy;
    final topInViewport = postTop - viewportTop;
    final postTopOffset = _scrollController.offset + topInViewport;
    return postTopOffset + anchorDelta;
  }

  void _showRestoredReadPositionToast() {
    if (!mounted) {
      return;
    }
    _readPositionToastTimer?.cancel();
    setState(() => _showReadPositionToast = true);
    _readPositionToastTimer = Timer(_readPositionRestoredMessageDuration, () {
      if (mounted) {
        setState(() => _showReadPositionToast = false);
      }
    });
  }

  Future<void> _saveReadPositionNow() async {
    _readPositionSaveTimer?.cancel();
    if (_restoringReadPosition ||
        !mounted ||
        !_scrollController.hasClients ||
        widget.detail == null) {
      return;
    }
    final offset = _scrollController.offset;
    if (offset < _minimumSavedReadOffset) {
      await ForumReadPositionStore.remove(_readPositionKey);
      return;
    }
    final bottomDistance = (_scrollController.position.maxScrollExtent - offset)
        .clamp(0.0, double.infinity)
        .toDouble();
    final anchor = _findCurrentReadAnchor();
    await ForumReadPositionStore.save(
      _readPositionKey,
      offset,
      anchorPostNumber: anchor?.postNumber,
      anchorDelta: anchor?.delta ?? 0,
      bottomDistance: bottomDistance,
    );
  }

  _ReadPositionAnchor? _findCurrentReadAnchor() {
    if (!_scrollController.hasClients) {
      return null;
    }
    final viewportBox =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.attached || !viewportBox.hasSize) {
      return null;
    }
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportBox.size.height;
    _ReadPositionAnchor? closestAbove;
    _ReadPositionAnchor? closestBelow;

    for (final entry in _postKeys.entries) {
      final postBox =
          entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (postBox == null ||
          !postBox.attached ||
          !postBox.hasSize ||
          postBox.size.height <= 0) {
        continue;
      }
      final postTop = postBox.localToGlobal(Offset.zero).dy;
      final postBottom = postTop + postBox.size.height;
      if (postBottom <= viewportTop + 1 || postTop >= viewportBottom - 1) {
        continue;
      }
      final topInViewport = postTop - viewportTop;
      final anchor = _ReadPositionAnchor(
        postNumber: entry.key,
        delta: -topInViewport,
        topInViewport: topInViewport,
      );
      if (topInViewport <= 0) {
        if (closestAbove == null ||
            topInViewport > closestAbove.topInViewport) {
          closestAbove = anchor;
        }
      } else if (closestBelow == null ||
          topInViewport < closestBelow.topInViewport) {
        closestBelow = anchor;
      }
    }

    return closestAbove ?? closestBelow;
  }

  void _replyTo(Post post) {
    if (!widget.isOnline) {
      widget.onLoginRequired();
      return;
    }
    _replyBarKey.currentState?.replyTo(post.postNumber);
  }

  void _like(Post post) {
    if (post.yours) {
      return;
    }
    if (!widget.isOnline) {
      widget.onLoginRequired();
      return;
    }
    if (widget.busyLikePostIds.contains(post.id)) {
      return;
    }
    widget.onLikePost(post);
  }

  Future<void> _confirmDelete(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除这条回复？'),
          content: const Text('删除后论坛网页端也会同步删除。'),
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
    if (confirmed == true) {
      widget.onDeletePost(post);
    }
  }

  void _openImagePreview(List<String> urls, int initialIndex) {
    Navigator.of(context).push<void>(
      lehuRoute(
        fullscreenDialog: true,
        builder: (context) => FullscreenImagePage(
          urls: urls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

class _ReadPositionAnchor {
  const _ReadPositionAnchor({
    required this.postNumber,
    required this.delta,
    required this.topInViewport,
  });

  final int postNumber;
  final double delta;
  final double topInViewport;
}

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.detail, required this.category});

  final TopicDetail detail;
  final ForumCategory? category;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.title,
            style: LehuTextStyles.title(
              color: colors.textPrimary,
              size: 20.5,
              height: 1.2,
              weight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${category?.name ?? '未知分区'} · ${detail.postsCount} 楼',
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ReadPositionToast extends StatelessWidget {
  const _ReadPositionToast({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark
        ? colors.surfaceAlt.withValues(alpha: 0.82)
        : colors.inverseSurface.withValues(alpha: 0.68);
    final foreground = dark ? colors.textSecondary : colors.inverseOnSurface;
    final borderColor =
        dark ? colors.borderStrong.withValues(alpha: 0.42) : Colors.transparent;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.16 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text(
              '已定位到上次阅读位置',
              style: TextStyle(
                color: foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThreadedPostView extends StatelessWidget {
  const _ThreadedPostView({
    required this.thread,
    required this.canReply,
    required this.isSubmittingReply,
    required this.busyLikePostIds,
    required this.busyDeletePostIds,
    required this.expanded,
    required this.collapsedReplyCount,
    required this.onToggleExpanded,
    required this.onReply,
    required this.onLike,
    required this.onDelete,
    required this.onOpenUser,
    required this.onOpenImage,
    required this.onOpenInternalTopic,
    required this.postKeyFor,
  });

  final ThreadedPost thread;
  final bool canReply;
  final bool isSubmittingReply;
  final Set<int> busyLikePostIds;
  final Set<int> busyDeletePostIds;
  final bool expanded;
  final int collapsedReplyCount;
  final VoidCallback onToggleExpanded;
  final ValueChanged<Post> onReply;
  final ValueChanged<Post> onLike;
  final ValueChanged<Post> onDelete;
  final ValueChanged<String> onOpenUser;
  final void Function(List<String> urls, int initialIndex) onOpenImage;
  final ValueChanged<CookedLinkPreview> onOpenInternalTopic;
  final GlobalKey Function(int postNumber) postKeyFor;

  @override
  Widget build(BuildContext context) {
    final post = thread.post;
    final replies = thread.replies;
    final visibleReplies =
        expanded ? replies : replies.take(collapsedReplyCount).toList();
    final hiddenCount = replies.length - visibleReplies.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PostView(
          key: postKeyFor(post.postNumber),
          post: post,
          canLike: true,
          canReply: canReply && !isSubmittingReply,
          canDelete: post.postNumber != 1 && post.yours && post.canDelete,
          isLiking: busyLikePostIds.contains(post.id),
          isDeleting: busyDeletePostIds.contains(post.id),
          onReply: () => onReply(post),
          onLike: () => onLike(post),
          onDelete: () => onDelete(post),
          onOpenUser: () => onOpenUser(post.username),
          onOpenImage: onOpenImage,
          onOpenInternalTopic: onOpenInternalTopic,
        ),
        if (replies.isNotEmpty)
          _NestedReplies(
            parent: post,
            replies: visibleReplies,
            hiddenCount: hiddenCount,
            expanded: expanded,
            canReply: canReply && !isSubmittingReply,
            busyLikePostIds: busyLikePostIds,
            busyDeletePostIds: busyDeletePostIds,
            onToggleExpanded: onToggleExpanded,
            onReply: onReply,
            onLike: onLike,
            onDelete: onDelete,
            onOpenUser: onOpenUser,
            onOpenImage: onOpenImage,
            onOpenInternalTopic: onOpenInternalTopic,
            postKeyFor: postKeyFor,
          ),
      ],
    );
  }
}

class _NestedReplies extends StatelessWidget {
  const _NestedReplies({
    required this.parent,
    required this.replies,
    required this.hiddenCount,
    required this.expanded,
    required this.canReply,
    required this.busyLikePostIds,
    required this.busyDeletePostIds,
    required this.onToggleExpanded,
    required this.onReply,
    required this.onLike,
    required this.onDelete,
    required this.onOpenUser,
    required this.onOpenImage,
    required this.onOpenInternalTopic,
    required this.postKeyFor,
  });

  final Post parent;
  final List<Post> replies;
  final int hiddenCount;
  final bool expanded;
  final bool canReply;
  final Set<int> busyLikePostIds;
  final Set<int> busyDeletePostIds;
  final VoidCallback onToggleExpanded;
  final ValueChanged<Post> onReply;
  final ValueChanged<Post> onLike;
  final ValueChanged<Post> onDelete;
  final ValueChanged<String> onOpenUser;
  final void Function(List<String> urls, int initialIndex) onOpenImage;
  final ValueChanged<CookedLinkPreview> onOpenInternalTopic;
  final GlobalKey Function(int postNumber) postKeyFor;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Container(
      margin: const EdgeInsets.only(left: 34, bottom: 8),
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final reply in replies)
            _PostView(
              key: postKeyFor(reply.postNumber),
              post: reply,
              compact: true,
              replyContext: reply.replyToPostNumber == parent.postNumber
                  ? null
                  : '回复 #${reply.replyToPostNumber}',
              canLike: true,
              canReply: canReply,
              canDelete:
                  reply.postNumber != 1 && reply.yours && reply.canDelete,
              isLiking: busyLikePostIds.contains(reply.id),
              isDeleting: busyDeletePostIds.contains(reply.id),
              onReply: () => onReply(reply),
              onLike: () => onLike(reply),
              onDelete: () => onDelete(reply),
              onOpenUser: () => onOpenUser(reply.username),
              onOpenImage: onOpenImage,
              onOpenInternalTopic: onOpenInternalTopic,
            ),
          if (hiddenCount > 0 || expanded)
            TextButton.icon(
              onPressed: onToggleExpanded,
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(expanded ? '收起回复' : '查看更多 $hiddenCount 条回复'),
            ),
        ],
      ),
    );
  }
}

class _PostView extends StatelessWidget {
  const _PostView({
    super.key,
    required this.post,
    required this.canLike,
    required this.canReply,
    required this.canDelete,
    required this.isLiking,
    required this.isDeleting,
    required this.onReply,
    required this.onLike,
    required this.onDelete,
    required this.onOpenUser,
    required this.onOpenImage,
    required this.onOpenInternalTopic,
    this.replyContext,
    this.compact = false,
  });

  final Post post;
  final bool canLike;
  final bool canReply;
  final bool canDelete;
  final bool isLiking;
  final bool isDeleting;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final VoidCallback onDelete;
  final VoidCallback onOpenUser;
  final void Function(List<String> urls, int initialIndex) onOpenImage;
  final ValueChanged<CookedLinkPreview> onOpenInternalTopic;
  final String? replyContext;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final textSize = compact ? 15.0 : 16.0;
    final timeText = TimeFormat.compact(
      post.createdAt,
      relativeWithinDay: true,
    );
    final metaText = timeText.isEmpty
        ? '#${post.postNumber}'
        : '#${post.postNumber} · $timeText';
    if (compact) {
      return _buildCompact(context, colors, textSize, timeText);
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canReply ? onReply : null,
        onLongPress: () => _showActionSheet(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: onOpenUser,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ForumAvatar(
                                url: post.avatarUrl(size: 96),
                                size: 36,
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      post.username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.detailAuthor,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      metaText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.textMuted,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (canLike)
                    _InlineLikeButton(
                      count: post.likeCount,
                      liked: post.liked,
                      enabled: !post.yours && !isLiking,
                      loading: isLiking,
                      onTap: onLike,
                    ),
                ],
              ),
            ),
            if (replyContext != null) ...[
              const SizedBox(height: 8),
              Text(
                replyContext!,
                style: TextStyle(color: colors.textMuted, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 11),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: ForumCookedContent(
                cooked: post.cooked,
                textColor: colors.textPrimary,
                textSize: textSize,
                imageFit: BoxFit.cover,
                imageErrorHeight: 160,
                compactCards: false,
                onOpenImage: onOpenImage,
                onOpenInternalTopic: onOpenInternalTopic,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(
    BuildContext context,
    LehuColors colors,
    double textSize,
    String timeText,
  ) {
    final targetText = replyContext ?? '#${post.postNumber}';
    final metaText = timeText.isEmpty ? targetText : '$targetText · $timeText';
    return Padding(
      padding: const EdgeInsets.only(top: 9, bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canReply ? onReply : null,
          onLongPress: () => _showActionSheet(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: onOpenUser,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ForumAvatar(
                              url: post.avatarUrl(size: 72),
                              size: 24,
                            ),
                            const SizedBox(width: 7),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 112),
                              child: Text(
                                post.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.detailAuthor,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        metaText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 12.5,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (canLike)
                      _InlineLikeButton(
                        count: post.likeCount,
                        liked: post.liked,
                        enabled: !post.yours && !isLiking,
                        loading: isLiking,
                        onTap: onLike,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 33, right: 10),
                child: ForumCookedContent(
                  cooked: post.cooked,
                  textColor: colors.textPrimary,
                  textSize: textSize,
                  textBottomSpacing: 5,
                  imageBottomSpacing: 7,
                  imageFit: BoxFit.cover,
                  imageErrorHeight: 150,
                  compactCards: true,
                  onOpenImage: onOpenImage,
                  onOpenInternalTopic: onOpenInternalTopic,
                ),
              ),
              const SizedBox(height: 3),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showActionSheet(BuildContext context) async {
    final actions = <_PostAction>[
      _PostAction(
        icon: Icons.copy_outlined,
        label: '复制',
        onTap: () => _copyText(context),
      ),
      if (canDelete)
        _PostAction(
          icon: Icons.delete_outline,
          label: isDeleting ? '删除中...' : '删除',
          destructive: true,
          onTap: isDeleting ? null : onDelete,
        ),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        final colors = context.lehuColors;
        return SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '回复操作',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
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
                const SizedBox(height: 4),
                for (final action in actions)
                  _PostActionTile(
                    action: action,
                    onSelected: () {
                      Navigator.of(context).pop();
                      action.onTap?.call();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyText(BuildContext context) async {
    final text = HtmlText.toPlainText(post.cooked).trim();
    final messenger = ScaffoldMessenger.of(context);
    if (text.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('没有可复制的文字')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }
}

class _PostAction {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;
}

class _PostActionTile extends StatelessWidget {
  const _PostActionTile({
    required this.action,
    required this.onSelected,
  });

  final _PostAction action;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final enabled = action.onTap != null;
    final color = action.destructive && enabled
        ? Theme.of(context).colorScheme.error
        : enabled
            ? colors.textPrimary
            : colors.textMuted;
    return ListTile(
      enabled: enabled,
      onTap: enabled ? onSelected : null,
      leading: Icon(action.icon, color: color),
      title: Text(action.label, style: TextStyle(color: color)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

class _InlineLikeButton extends StatelessWidget {
  const _InlineLikeButton({
    required this.count,
    required this.liked,
    required this.enabled,
    required this.loading,
    required this.onTap,
  });

  final int count;
  final bool liked;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final activeColor = Theme.of(context).colorScheme.primary;
    final color = liked ? activeColor : colors.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                size: 18,
                color: enabled || liked ? color : colors.textMuted,
              ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                color: enabled || liked ? color : colors.textMuted,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyBar extends StatefulWidget {
  const _ReplyBar({
    super.key,
    required this.enabled,
    required this.isOnline,
    required this.isSubmitting,
    required this.detail,
    required this.currentUsername,
    required this.onLoginRequired,
    required this.onUploadImage,
    required this.onSubmit,
  });

  final bool enabled;
  final bool isOnline;
  final bool isSubmitting;
  final TopicDetail detail;
  final String currentUsername;
  final VoidCallback onLoginRequired;
  final Future<UploadedImage> Function(PickedImage image) onUploadImage;
  final Future<bool> Function(ReplyDraft draft) onSubmit;

  @override
  State<_ReplyBar> createState() => _TopicReplyBarState();
}

class _TopicReplyBarState extends State<_ReplyBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _images = <UploadedImage>[];
  Timer? _draftSaveTimer;
  bool _uploading = false;
  bool _submitting = false;
  bool _composerOpen = false;
  bool _showEmojiPanel = false;
  bool _collapsedForBrowsing = false;
  bool _restoringDraft = false;
  int? _replyToPostNumber;

  bool get _canType =>
      widget.enabled &&
      widget.isOnline &&
      !widget.isSubmitting &&
      !_uploading &&
      !_submitting;

  bool get _expanded =>
      !_collapsedForBrowsing &&
      (_composerOpen ||
          _focusNode.hasFocus ||
          _showEmojiPanel ||
          _controller.text.trim().isNotEmpty ||
          _images.isNotEmpty ||
          _replyToPostNumber != null);

  bool get _canSend =>
      widget.isOnline &&
      !widget.isSubmitting &&
      !_submitting &&
      !_uploading &&
      (_controller.text.trim().isNotEmpty || _images.isNotEmpty);

  bool get _hasDraft =>
      _controller.text.trim().isNotEmpty ||
      _images.isNotEmpty ||
      _replyToPostNumber != null;

  String get _currentDraftKey {
    return _draftKeyFor(_replyToPostNumber);
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    _controller.addListener(_handleDraftChanged);
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    unawaited(_saveDraftNow());
    _focusNode.removeListener(_handleFocusChanged);
    _controller.removeListener(_handleDraftChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void replyTo(int postNumber) {
    if (!_canType) {
      _handleInputTap();
      return;
    }
    unawaited(_openComposerFor(postNumber, requestFocus: true));
  }

  void handleOutsideTap() {
    if (!_expanded) {
      return;
    }
    FocusScope.of(context).unfocus();
    unawaited(_saveDraftNow());
    if (_hasDraft) {
      if (_showEmojiPanel) {
        setState(() => _showEmojiPanel = false);
      }
      return;
    }
    setState(() {
      _composerOpen = false;
      _showEmojiPanel = false;
    });
  }

  void collapseForBrowsing() {
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    unawaited(_saveDraftNow());
    if (!_expanded && !_showEmojiPanel) {
      return;
    }
    setState(() {
      _composerOpen = false;
      _showEmojiPanel = false;
      _collapsedForBrowsing = _hasDraft;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canType = _canType;
    final expanded = _expanded;
    final colors = context.lehuColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_replyToPostNumber != null) ...[
                      _ReplyTargetChip(
                        postNumber: _replyToPostNumber!,
                        onClear: widget.isSubmitting
                            ? null
                            : () => unawaited(
                                  _openComposerFor(
                                    null,
                                    requestFocus: false,
                                  ),
                                ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_images.isNotEmpty) ...[
                      _AttachmentPreviewRow(
                        images: _images,
                        onRemove: widget.isSubmitting || _uploading
                            ? null
                            : (image) {
                                setState(() => _images.remove(image));
                                _scheduleDraftSave();
                              },
                      ),
                      const SizedBox(height: 8),
                    ],
                    _ComposerFrame(
                      focused: _focusNode.hasFocus || _showEmojiPanel,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            readOnly: !canType,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.newline,
                            onTap: _handleInputTap,
                            decoration: InputDecoration(
                              hintText: _hintText,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                8,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: '添加图片',
                                  onPressed: canType ? _pickAndUpload : null,
                                  icon: _uploading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.image_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Emoji',
                                  onPressed: canType ? _toggleEmojiPanel : null,
                                  icon: Icon(
                                    _showEmojiPanel
                                        ? Icons.keyboard_alt_outlined
                                        : Icons.emoji_emotions_outlined,
                                  ),
                                ),
                                const Spacer(),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilledButton(
                                    onPressed: _canSend ? _submit : null,
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(64, 34),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: widget.isSubmitting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('发送'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _showEmojiPanel
                          ? InlineEmojiPanel(
                              key: const ValueKey('emoji-panel'),
                              controller: _controller,
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('emoji-empty'),
                            ),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.enabled ? _activateComposer : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.largeAction,
                      foregroundColor: colors.onLargeAction,
                      disabledBackgroundColor: colors.disabledFill,
                      disabledForegroundColor: colors.textMuted,
                    ),
                    icon: widget.isSubmitting
                        ? const _TinyProgress()
                        : const Icon(Icons.edit_outlined),
                    label: Text(
                      widget.isSubmitting
                          ? '发布中...'
                          : widget.enabled
                              ? (widget.isOnline ? '写评论' : '登录后评论')
                              : '当前帖子不可回复',
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  void _activateComposer() {
    if (!widget.isOnline) {
      widget.onLoginRequired();
      return;
    }
    if (!widget.enabled || widget.isSubmitting) {
      return;
    }
    unawaited(_openComposerFor(null, requestFocus: true));
  }

  String get _hintText {
    if (widget.isSubmitting) {
      return '发布中...';
    }
    if (!widget.isOnline) {
      return '登录后评论';
    }
    if (!widget.enabled) {
      return '当前帖子不可回复';
    }
    return _replyToPostNumber == null ? '写评论' : '回复 #$_replyToPostNumber';
  }

  void _handleFocusChanged() {
    if (!mounted) {
      return;
    }
    if (_focusNode.hasFocus && _showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
      return;
    }
    setState(() {});
  }

  void _handleDraftChanged() {
    _scheduleDraftSave();
    if (mounted) {
      setState(() {});
    }
  }

  void _handleInputTap() {
    if (!widget.isOnline) {
      widget.onLoginRequired();
      return;
    }
    if (!widget.enabled || widget.isSubmitting) {
      return;
    }
    _composerOpen = true;
    _collapsedForBrowsing = false;
    _scheduleDraftSave();
    if (_showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
    }
  }

  void _toggleEmojiPanel() {
    if (!_canType) {
      _handleInputTap();
      return;
    }
    if (_showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
      _focusNode.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() {
      _composerOpen = true;
      _collapsedForBrowsing = false;
      _showEmojiPanel = true;
    });
  }

  Future<void> _pickAndUpload() async {
    if (!_canType) {
      return;
    }
    setState(() {
      _uploading = true;
      _composerOpen = true;
      _collapsedForBrowsing = false;
      _showEmojiPanel = false;
    });
    try {
      final picked = await LocalImagePicker.pickImage();
      if (picked == null) {
        return;
      }
      final uploaded = await widget.onUploadImage(picked);
      _images.add(uploaded);
      if (mounted) {
        setState(() {});
        _scheduleDraftSave();
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片上传失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _images.isEmpty) ||
        widget.isSubmitting ||
        _submitting ||
        _uploading) {
      return;
    }
    final replyToPostNumber = _replyToPostNumber;
    final images = List<UploadedImage>.of(_images);
    final draftKey = _draftKeyFor(replyToPostNumber);
    setState(() => _submitting = true);
    await _saveDraftNow();
    final success = await widget.onSubmit(
      ReplyDraft(
        topicId: widget.detail.id,
        categoryId: widget.detail.categoryId,
        raw: _composeRaw(text, images),
        replyToPostNumber: replyToPostNumber,
        archetype: widget.detail.archetype,
        images: images,
      ),
    );
    if (!mounted) {
      return;
    }
    if (success) {
      await ForumDraftStore.remove(draftKey);
      if (!mounted) {
        return;
      }
      _restoringDraft = true;
      _controller.clear();
      _restoringDraft = false;
      setState(() {
        _images.clear();
        _composerOpen = false;
        _collapsedForBrowsing = false;
        _replyToPostNumber = null;
        _showEmojiPanel = false;
        _submitting = false;
      });
      return;
    }
    setState(() => _submitting = false);
  }

  String _composeRaw(String text, List<UploadedImage> images) {
    return composeRawWithImages(text, images);
  }

  Future<void> _openComposerFor(
    int? replyToPostNumber, {
    required bool requestFocus,
  }) async {
    await _saveDraftNow();
    final draft = await ForumDraftStore.load(_draftKeyFor(replyToPostNumber));
    if (!mounted) {
      return;
    }
    _restoringDraft = true;
    _controller.text = draft?.raw ?? '';
    setState(() {
      _images
        ..clear()
        ..addAll(draft?.images ?? const <UploadedImage>[]);
      _composerOpen = true;
      _collapsedForBrowsing = false;
      _replyToPostNumber = replyToPostNumber;
      _showEmojiPanel = false;
    });
    _restoringDraft = false;
    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  void _scheduleDraftSave() {
    if (_restoringDraft || _submitting || widget.isSubmitting) {
      return;
    }
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_saveDraftNow()),
    );
  }

  Future<void> _saveDraftNow() async {
    if (_restoringDraft || _submitting || widget.isSubmitting) {
      return;
    }
    await ForumDraftStore.save(
      _currentDraftKey,
      ForumComposerDraft(
        raw: _controller.text,
        replyToPostNumber: _replyToPostNumber,
        images: List<UploadedImage>.of(_images),
      ),
    );
  }

  String _draftKeyFor(int? replyToPostNumber) {
    return ForumDraftStore.topicReplyKey(
      username: widget.currentUsername,
      topicId: widget.detail.id,
      replyToPostNumber: replyToPostNumber,
    );
  }
}

class _ComposerFrame extends StatelessWidget {
  const _ComposerFrame({
    required this.focused,
    required this.child,
  });

  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderColor = focused
        ? Theme.of(context).colorScheme.primary
        : context.lehuColors.borderStrong;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: focused ? 1.4 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ReplyTargetChip extends StatelessWidget {
  const _ReplyTargetChip({
    required this.postNumber,
    required this.onClear,
  });

  final int postNumber;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InputChip(
        label: Text('回复 #$postNumber'),
        onDeleted: onClear,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _AttachmentPreviewRow extends StatelessWidget {
  const _AttachmentPreviewRow({
    required this.images,
    required this.onRemove,
  });

  final List<UploadedImage> images;
  final ValueChanged<UploadedImage>? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = images[index];
          return _AttachmentPreviewTile(
            image: image,
            onRemove: onRemove == null ? null : () => onRemove!(image),
          );
        },
      ),
    );
  }
}

class _AttachmentPreviewTile extends StatelessWidget {
  const _AttachmentPreviewTile({
    required this.image,
    required this.onRemove,
  });

  final UploadedImage image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = context.lehuColors;
    return SizedBox(
      width: 74,
      height: 74,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: colors.surfaceMuted,
                child: image.url.isEmpty
                    ? const _AttachmentImageFallback()
                    : ForumNetworkImage(
                        ForumUrlResolver.resolve(image.url),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const _AttachmentImageFallback();
                        },
                      ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.borderStrong),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: -6,
            child: IconButton.filled(
              tooltip: '移除图片',
              onPressed: onRemove,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(24),
                fixedSize: const Size.square(24),
                padding: EdgeInsets.zero,
                backgroundColor: colorScheme.surface,
                foregroundColor: colorScheme.onSurface,
                disabledBackgroundColor: colors.disabledFill,
                disabledForegroundColor: colors.textMuted,
              ),
              icon: const Icon(Icons.close, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentImageFallback extends StatelessWidget {
  const _AttachmentImageFallback();

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 26,
        color: colors.textTertiary,
      ),
    );
  }
}

class _TinyProgress extends StatelessWidget {
  const _TinyProgress();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
      ),
    );
  }
}
