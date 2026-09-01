import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/forum_url_resolver.dart';
import '../../data/models/category.dart';
import '../../data/models/composer.dart';
import '../../data/models/forum_poll.dart';
import '../../data/models/forum_search.dart';
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
import '../../shared/shuyo_text_styles.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/fullscreen_image_page.dart';
import '../../shared/widgets/inline_emoji_panel.dart';
import 'advanced_reply_composer_page.dart';
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
    required this.onVotePoll,
    required this.onTogglePollStatus,
    required this.onDeletePost,
    required this.onReportPost,
    required this.onOpenUser,
    required this.onOpenInternalTopic,
    required this.onSearchUsers,
    required this.onLoginRequired,
    this.onReadingTimingSample,
    this.onReadingTimingFlush,
    this.targetPostNumber,
    required this.isOnline,
    required this.isSubmittingReply,
    required this.busyLikePostIds,
    required this.busyPollKeys,
    required this.busyDeletePostIds,
    required this.busyReportPostIds,
    required this.reportedPostIds,
  });

  final TopicPageController? controller;
  final TopicListItem item;
  final TopicDetail? detail;
  final ForumCategory? category;
  final String currentUsername;
  final bool isOnline;
  final bool isSubmittingReply;
  final Set<int> busyLikePostIds;
  final Set<String> busyPollKeys;
  final Set<int> busyDeletePostIds;
  final Set<int> busyReportPostIds;
  final Set<int> reportedPostIds;
  final Future<bool> Function(ReplyDraft draft) onCreateReply;
  final Future<UploadedImage> Function(PickedImage image) onUploadImage;
  final ValueChanged<Post> onLikePost;
  final Future<void> Function(Post post, ForumPoll poll, List<String> optionIds)
      onVotePoll;
  final Future<void> Function(Post post, ForumPoll poll, String status)
      onTogglePollStatus;
  final ValueChanged<Post> onDeletePost;
  final ValueChanged<Post> onReportPost;
  final ValueChanged<String> onOpenUser;
  final ValueChanged<CookedLinkPreview> onOpenInternalTopic;
  final Future<List<SearchUserResult>> Function(String query) onSearchUsers;
  final VoidCallback onLoginRequired;
  final void Function(Set<int> postNumbers, Duration elapsed)?
      onReadingTimingSample;
  final VoidCallback? onReadingTimingFlush;
  final int? targetPostNumber;

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

  void scrollToPost(int postNumber) {
    _state?._scrollToPost(postNumber);
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
  static const _targetPostViewportBias = 0.42;
  static const _targetPostScrollAttempts = 8;
  static const _targetPostScrollStep = Duration(milliseconds: 70);
  static const _readingTimingSampleInterval = Duration(seconds: 1);
  static const _readingTimingMaxSample = Duration(seconds: 2);
  static const _readingTimingMinVisiblePixels = 36.0;

  final _expandedReplyParents = <int>{};
  final _replyBarKey = GlobalKey<_TopicReplyBarState>();
  final _scrollViewKey = GlobalKey();
  final _scrollController = ScrollController();
  final _postKeys = <int, GlobalKey>{};
  Timer? _readPositionSaveTimer;
  Timer? _readPositionToastTimer;
  Timer? _readingTimingTimer;
  DateTime? _lastImmediateReadPositionSaveAt;
  DateTime? _lastReadingTimingSampleAt;
  String? _restoredReadPositionKey;
  String? _targetPostScrollKey;
  bool _restoringReadPosition = false;
  bool _cancelReadPositionCorrection = false;
  bool _targetPostScrollActive = false;
  bool _cancelTargetPostScrollCorrection = false;
  int? _activeTargetPostNumber;
  bool _showTargetPostLoading = false;
  bool _showReadPositionToast = false;
  bool _readingTimingActive = true;

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
    _showTargetPostLoading = _hasTargetPost;
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScrollChanged);
    widget.controller?._attach(this);
    _startReadingTimingTimer();
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
      _targetPostScrollKey = null;
      _restoringReadPosition = false;
      _cancelReadPositionCorrection = true;
      _targetPostScrollActive = false;
      _cancelTargetPostScrollCorrection = true;
      _activeTargetPostNumber = null;
      _showTargetPostLoading = _hasTargetPost;
      _lastReadingTimingSampleAt = DateTime.now();
      _postKeys.clear();
    } else if (oldWidget.targetPostNumber != widget.targetPostNumber) {
      _targetPostScrollKey = null;
      _cancelTargetPostScrollCorrection = true;
      _activeTargetPostNumber = null;
      _showTargetPostLoading = _hasTargetPost;
    } else if (widget.targetPostNumber != null &&
        oldWidget.detail != widget.detail) {
      _targetPostScrollKey = null;
      _showTargetPostLoading = _hasTargetPost;
    }
  }

  @override
  void dispose() {
    _recordReadingTimingSample();
    widget.onReadingTimingFlush?.call();
    _readPositionSaveTimer?.cancel();
    _readPositionToastTimer?.cancel();
    _readingTimingTimer?.cancel();
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
    _scheduleInitialPosition();

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
                          busyPollKeys: widget.busyPollKeys,
                          busyDeletePostIds: widget.busyDeletePostIds,
                          busyReportPostIds: widget.busyReportPostIds,
                          reportedPostIds: widget.reportedPostIds,
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
                          onVotePoll: widget.onVotePoll,
                          onTogglePollStatus: widget.onTogglePollStatus,
                          onDelete: _confirmDelete,
                          onReport: widget.onReportPost,
                          onOpenUser: widget.onOpenUser,
                          onOpenImage: _openImagePreview,
                          onOpenInternalTopic: widget.onOpenInternalTopic,
                          postKeyFor: _postKeyFor,
                        ),
                      if (_activeTargetPostNumber != null)
                        SizedBox(height: _targetPostBottomPadding(context)),
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
              onSearchUsers: widget.onSearchUsers,
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
        if (_hasTargetPost)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_showTargetPostLoading,
              child: AnimatedOpacity(
                opacity: _showTargetPostLoading ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: const _TargetPostLoadingOverlay(),
              ),
            ),
          ),
      ],
    );
  }

  bool get _hasTargetPost {
    final postNumber = widget.targetPostNumber;
    return postNumber != null && postNumber > 0;
  }

  double _targetPostBottomPadding(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    return (viewportHeight * 0.56).clamp(260.0, 520.0).toDouble();
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

  Future<void> _scrollToPost(int postNumber) async {
    if (postNumber <= 0 || widget.detail == null) {
      _finishTargetPostScroll(postNumber);
      return;
    }
    _cancelReadPositionCorrection = true;
    _restoringReadPosition = false;
    _cancelTargetPostScrollCorrection = false;
    _startTargetPostScroll(postNumber);
    _expandParentForPost(postNumber);
    var scrolled = false;
    try {
      for (var attempt = 0; attempt < _targetPostScrollAttempts; attempt++) {
        if (_cancelTargetPostScrollCorrection) {
          return;
        }
        await (attempt == 0
            ? WidgetsBinding.instance.endOfFrame
            : Future<void>.delayed(_targetPostScrollStep));
        if (!mounted || !_scrollController.hasClients) {
          return;
        }
        if (await _ensurePostVisible(postNumber)) {
          scrolled = true;
          continue;
        }
        await _preScrollTargetIntoBuildRange(postNumber, attempt);
      }
      if (!scrolled && await _ensurePostVisible(postNumber)) {
        scrolled = true;
      }
      if (scrolled) {
        unawaited(_saveReadPositionNow());
        return;
      }
    } finally {
      _finishTargetPostScroll(postNumber);
    }
  }

  Future<bool> _ensurePostVisible(int postNumber) async {
    final context = _postKeys[postNumber]?.currentContext;
    if (context == null || !context.mounted) {
      return false;
    }
    await Scrollable.ensureVisible(
      context,
      duration: Duration.zero,
      alignment: _targetPostViewportBias,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
    return true;
  }

  Future<bool> _preScrollTargetIntoBuildRange(
    int postNumber,
    int attempt,
  ) async {
    if (!_scrollController.hasClients) {
      return false;
    }
    final rootNumber = _rootPostNumberFor(postNumber);
    if (attempt == 0 && rootNumber != null && rootNumber != postNumber) {
      final rootContext = _postKeys[rootNumber]?.currentContext;
      if (rootContext != null && rootContext.mounted) {
        await Scrollable.ensureVisible(
          rootContext,
          duration: Duration.zero,
          alignment: 0.08,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
        return true;
      }
    }
    final offset = _estimatedScrollOffsetForPost(postNumber, attempt);
    if (offset == null) {
      return false;
    }
    return _jumpToReadOffset(offset);
  }

  double? _estimatedScrollOffsetForPost(int postNumber, int attempt) {
    if (!_scrollController.hasClients || widget.detail == null) {
      return null;
    }
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    if (maxScrollExtent <= 0) {
      return null;
    }
    final displayNumbers = _estimatedDisplayPostNumbers();
    if (displayNumbers.isEmpty) {
      return null;
    }
    var index = displayNumbers.indexOf(postNumber);
    if (index < 0) {
      final rootNumber = _rootPostNumberFor(postNumber);
      if (rootNumber != null) {
        index = displayNumbers.indexOf(rootNumber);
      }
    }
    if (index < 0) {
      return null;
    }
    final baseFraction =
        ((index + 0.5) / displayNumbers.length).clamp(0.0, 1.0).toDouble();
    final viewportHeight =
        (_scrollViewKey.currentContext?.findRenderObject() as RenderBox?)
                ?.size
                .height ??
            0;
    final fallbackNudge = attempt <= 1 ? 0.0 : viewportHeight * 0.35;
    final target = (maxScrollExtent * baseFraction) - fallbackNudge;
    return target.clamp(0.0, maxScrollExtent).toDouble();
  }

  List<int> _estimatedDisplayPostNumbers() {
    final detail = widget.detail;
    if (detail == null) {
      return const [];
    }
    final threads = buildThreadedPosts(
      detail.posts.where((post) => !post.isDeleted).toList(growable: false),
    );
    final numbers = <int>[];
    for (final thread in threads) {
      numbers.add(thread.post.postNumber);
      final replies = _expandedReplyParents.contains(thread.post.postNumber)
          ? thread.replies
          : thread.replies.take(_collapsedReplyCount);
      numbers.addAll(replies.map((reply) => reply.postNumber));
    }
    return numbers;
  }

  int? _rootPostNumberFor(int postNumber) {
    final detail = widget.detail;
    if (detail == null) {
      return null;
    }
    final postsByNumber = {
      for (final post in detail.posts) post.postNumber: post,
    };
    var post = postsByNumber[postNumber];
    if (post == null) {
      return null;
    }
    final visited = <int>{postNumber};
    while (post?.replyToPostNumber != null) {
      final parentNumber = post!.replyToPostNumber!;
      final parent = postsByNumber[parentNumber];
      if (parent == null || !visited.add(parent.postNumber)) {
        break;
      }
      post = parent;
    }
    return post?.postNumber;
  }

  void _startTargetPostScroll(int postNumber) {
    if (!mounted) {
      _targetPostScrollActive = true;
      _activeTargetPostNumber = postNumber;
      _showTargetPostLoading = true;
      return;
    }
    setState(() {
      _targetPostScrollActive = true;
      _activeTargetPostNumber = postNumber;
      _showTargetPostLoading = true;
    });
  }

  void _finishTargetPostScroll(int postNumber) {
    _targetPostScrollActive = false;
    if (!mounted) {
      if (_activeTargetPostNumber == postNumber) {
        _activeTargetPostNumber = null;
      }
      _showTargetPostLoading = false;
      return;
    }
    if (_activeTargetPostNumber == postNumber || _showTargetPostLoading) {
      setState(() {
        if (_activeTargetPostNumber == postNumber) {
          _activeTargetPostNumber = null;
        }
        _showTargetPostLoading = false;
      });
    }
  }

  void _expandParentForPost(int postNumber) {
    final detail = widget.detail;
    if (detail == null) {
      return;
    }
    final postsByNumber = {
      for (final post in detail.posts) post.postNumber: post,
    };
    final post = postsByNumber[postNumber];
    final parentNumber = post?.replyToPostNumber;
    if (post == null || parentNumber == null || parentNumber == postNumber) {
      return;
    }
    var rootNumber = parentNumber;
    final visited = <int>{postNumber};
    var parent = postsByNumber[rootNumber];
    while (parent != null &&
        parent.replyToPostNumber != null &&
        visited.add(parent.postNumber)) {
      rootNumber = parent.replyToPostNumber!;
      parent = postsByNumber[rootNumber];
    }
    if (_expandedReplyParents.contains(rootNumber)) {
      return;
    }
    final threads = buildThreadedPosts(
      detail.posts.where((post) => !post.isDeleted).toList(growable: false),
    );
    final replies = threads
        .where((thread) => thread.post.postNumber == rootNumber)
        .expand((thread) => thread.replies)
        .toList(growable: false);
    final targetIndex =
        replies.indexWhere((reply) => reply.postNumber == postNumber);
    if (targetIndex < _collapsedReplyCount) {
      return;
    }
    setState(() => _expandedReplyParents.add(rootNumber));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _recordReadingTimingSample();
      _readingTimingActive = false;
      _lastReadingTimingSampleAt = null;
      widget.onReadingTimingFlush?.call();
      unawaited(_saveReadPositionNow());
    } else if (state == AppLifecycleState.resumed) {
      _readingTimingActive = true;
      _lastReadingTimingSampleAt = DateTime.now();
    }
  }

  void _startReadingTimingTimer() {
    _lastReadingTimingSampleAt = DateTime.now();
    _readingTimingTimer = Timer.periodic(
      _readingTimingSampleInterval,
      (_) => _recordReadingTimingSample(),
    );
  }

  void _recordReadingTimingSample() {
    final callback = widget.onReadingTimingSample;
    if (callback == null || !_readingTimingActive) {
      return;
    }
    final now = DateTime.now();
    final lastSampleAt = _lastReadingTimingSampleAt;
    _lastReadingTimingSampleAt = now;
    if (!mounted ||
        lastSampleAt == null ||
        widget.detail == null ||
        _showTargetPostLoading) {
      return;
    }
    var elapsed = now.difference(lastSampleAt);
    if (elapsed <= Duration.zero) {
      return;
    }
    if (elapsed > _readingTimingMaxSample) {
      elapsed = _readingTimingMaxSample;
    }
    final visiblePostNumbers = _visibleReadingPostNumbers();
    if (visiblePostNumbers.isEmpty) {
      return;
    }
    callback(visiblePostNumbers, elapsed);
  }

  Set<int> _visibleReadingPostNumbers() {
    final viewportBox =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.attached || !viewportBox.hasSize) {
      return const {};
    }
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportBox.size.height;
    final visible = <int>{};

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
      final overlapTop = postTop > viewportTop ? postTop : viewportTop;
      final overlapBottom =
          postBottom < viewportBottom ? postBottom : viewportBottom;
      final visiblePixels = overlapBottom - overlapTop;
      final requiredPixels =
          postBox.size.height < _readingTimingMinVisiblePixels
              ? postBox.size.height
              : _readingTimingMinVisiblePixels;
      if (visiblePixels >= requiredPixels) {
        visible.add(entry.key);
      }
    }
    return visible;
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
    if (_isUserScrollStart(notification) && _targetPostScrollActive) {
      _cancelTargetPostScrollCorrection = true;
      _targetPostScrollActive = false;
      if (_activeTargetPostNumber != null) {
        setState(() {
          _activeTargetPostNumber = null;
          _showTargetPostLoading = false;
        });
      }
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

  void _scheduleInitialPosition() {
    final targetPostNumber = widget.targetPostNumber;
    if (targetPostNumber != null && targetPostNumber > 0) {
      final key = '$_readPositionKey.$targetPostNumber';
      if (_targetPostScrollKey == key) {
        return;
      }
      _targetPostScrollKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_scrollToPost(targetPostNumber));
      });
      return;
    }
    _scheduleReadPositionRestore();
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
      return true;
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
          title: const Text('确认删除回复'),
          content: const Text('删除后将无法恢复，是否确认删除？'),
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
      shuyoRoute(
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
    final colors = context.shuyoColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.title,
            style: ShuYoTextStyles.title(
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
    final colors = context.shuyoColors;
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

class _TargetPostLoadingOverlay extends StatelessWidget {
  const _TargetPostLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return ColoredBox(
      color: colors.background,
      child: const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(strokeWidth: 3),
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
    required this.busyPollKeys,
    required this.busyDeletePostIds,
    required this.busyReportPostIds,
    required this.reportedPostIds,
    required this.expanded,
    required this.collapsedReplyCount,
    required this.onToggleExpanded,
    required this.onReply,
    required this.onLike,
    required this.onVotePoll,
    required this.onTogglePollStatus,
    required this.onDelete,
    required this.onReport,
    required this.onOpenUser,
    required this.onOpenImage,
    required this.onOpenInternalTopic,
    required this.postKeyFor,
  });

  final ThreadedPost thread;
  final bool canReply;
  final bool isSubmittingReply;
  final Set<int> busyLikePostIds;
  final Set<String> busyPollKeys;
  final Set<int> busyDeletePostIds;
  final Set<int> busyReportPostIds;
  final Set<int> reportedPostIds;
  final bool expanded;
  final int collapsedReplyCount;
  final VoidCallback onToggleExpanded;
  final ValueChanged<Post> onReply;
  final ValueChanged<Post> onLike;
  final Future<void> Function(Post post, ForumPoll poll, List<String> optionIds)
      onVotePoll;
  final Future<void> Function(Post post, ForumPoll poll, String status)
      onTogglePollStatus;
  final ValueChanged<Post> onDelete;
  final ValueChanged<Post> onReport;
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
          reported: post.reported || reportedPostIds.contains(post.id),
          isLiking: busyLikePostIds.contains(post.id),
          busyPollKeys: busyPollKeys,
          isDeleting: busyDeletePostIds.contains(post.id),
          isReporting: busyReportPostIds.contains(post.id),
          onReply: () => onReply(post),
          onLike: () => onLike(post),
          onVotePoll: onVotePoll,
          onTogglePollStatus: onTogglePollStatus,
          onDelete: () => onDelete(post),
          onReport: () => onReport(post),
          onOpenUser: onOpenUser,
          onOpenImage: onOpenImage,
          onOpenInternalTopic: onOpenInternalTopic,
        ),
        if (replies.isNotEmpty)
          _NestedReplies(
            parent: post,
            replies: visibleReplies,
            hiddenCount: hiddenCount,
            showToggle: replies.length > collapsedReplyCount,
            expanded: expanded,
            canReply: canReply && !isSubmittingReply,
            busyLikePostIds: busyLikePostIds,
            busyPollKeys: busyPollKeys,
            busyDeletePostIds: busyDeletePostIds,
            busyReportPostIds: busyReportPostIds,
            reportedPostIds: reportedPostIds,
            onToggleExpanded: onToggleExpanded,
            onReply: onReply,
            onLike: onLike,
            onVotePoll: onVotePoll,
            onTogglePollStatus: onTogglePollStatus,
            onDelete: onDelete,
            onReport: onReport,
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
    required this.showToggle,
    required this.expanded,
    required this.canReply,
    required this.busyLikePostIds,
    required this.busyPollKeys,
    required this.busyDeletePostIds,
    required this.busyReportPostIds,
    required this.reportedPostIds,
    required this.onToggleExpanded,
    required this.onReply,
    required this.onLike,
    required this.onVotePoll,
    required this.onTogglePollStatus,
    required this.onDelete,
    required this.onReport,
    required this.onOpenUser,
    required this.onOpenImage,
    required this.onOpenInternalTopic,
    required this.postKeyFor,
  });

  final Post parent;
  final List<Post> replies;
  final int hiddenCount;
  final bool showToggle;
  final bool expanded;
  final bool canReply;
  final Set<int> busyLikePostIds;
  final Set<String> busyPollKeys;
  final Set<int> busyDeletePostIds;
  final Set<int> busyReportPostIds;
  final Set<int> reportedPostIds;
  final VoidCallback onToggleExpanded;
  final ValueChanged<Post> onReply;
  final ValueChanged<Post> onLike;
  final Future<void> Function(Post post, ForumPoll poll, List<String> optionIds)
      onVotePoll;
  final Future<void> Function(Post post, ForumPoll poll, String status)
      onTogglePollStatus;
  final ValueChanged<Post> onDelete;
  final ValueChanged<Post> onReport;
  final ValueChanged<String> onOpenUser;
  final void Function(List<String> urls, int initialIndex) onOpenImage;
  final ValueChanged<CookedLinkPreview> onOpenInternalTopic;
  final GlobalKey Function(int postNumber) postKeyFor;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
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
              reported: reply.reported || reportedPostIds.contains(reply.id),
              isLiking: busyLikePostIds.contains(reply.id),
              busyPollKeys: busyPollKeys,
              isDeleting: busyDeletePostIds.contains(reply.id),
              isReporting: busyReportPostIds.contains(reply.id),
              onReply: () => onReply(reply),
              onLike: () => onLike(reply),
              onVotePoll: onVotePoll,
              onTogglePollStatus: onTogglePollStatus,
              onDelete: () => onDelete(reply),
              onReport: () => onReport(reply),
              onOpenUser: onOpenUser,
              onOpenImage: onOpenImage,
              onOpenInternalTopic: onOpenInternalTopic,
            ),
          if (showToggle)
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
    required this.reported,
    required this.isLiking,
    required this.busyPollKeys,
    required this.isDeleting,
    required this.isReporting,
    required this.onReply,
    required this.onLike,
    required this.onVotePoll,
    required this.onTogglePollStatus,
    required this.onDelete,
    required this.onReport,
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
  final bool reported;
  final bool isLiking;
  final Set<String> busyPollKeys;
  final bool isDeleting;
  final bool isReporting;
  final VoidCallback onReply;
  final VoidCallback onLike;
  final Future<void> Function(Post post, ForumPoll poll, List<String> optionIds)
      onVotePoll;
  final Future<void> Function(Post post, ForumPoll poll, String status)
      onTogglePollStatus;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final ValueChanged<String> onOpenUser;
  final void Function(List<String> urls, int initialIndex) onOpenImage;
  final ValueChanged<CookedLinkPreview> onOpenInternalTopic;
  final String? replyContext;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
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
                        onTap: () => onOpenUser(post.username),
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
                imageFit: BoxFit.contain,
                imageErrorHeight: 160,
                compactCards: false,
                polls: post.polls,
                canManagePolls: post.yours,
                isPollBusy: (poll) => busyPollKeys.contains(
                  _pollKey(post, poll),
                ),
                onVotePoll: (poll, optionIds) => onVotePoll(
                  post,
                  poll,
                  optionIds,
                ),
                onTogglePollStatus: (poll, status) => onTogglePollStatus(
                  post,
                  poll,
                  status,
                ),
                onOpenUser: onOpenUser,
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
    ShuYoColors colors,
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
                      onTap: () => onOpenUser(post.username),
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
                  imageFit: BoxFit.contain,
                  imageErrorHeight: 150,
                  compactCards: true,
                  polls: post.polls,
                  canManagePolls: post.yours,
                  isPollBusy: (poll) => busyPollKeys.contains(
                    _pollKey(post, poll),
                  ),
                  onVotePoll: (poll, optionIds) => onVotePoll(
                    post,
                    poll,
                    optionIds,
                  ),
                  onTogglePollStatus: (poll, status) => onTogglePollStatus(
                    post,
                    poll,
                    status,
                  ),
                  onOpenUser: onOpenUser,
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
      _PostAction(
        icon: Icons.flag_outlined,
        label: reported
            ? '已举报'
            : isReporting
                ? '举报中...'
                : '举报',
        onTap: reported || isReporting ? null : onReport,
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
        final colors = context.shuyoColors;
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
    final colors = context.shuyoColors;
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
    final colors = context.shuyoColors;
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
                child: CircularProgressIndicator(strokeWidth: 3),
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
    required this.onSearchUsers,
    required this.onSubmit,
  });

  final bool enabled;
  final bool isOnline;
  final bool isSubmitting;
  final TopicDetail detail;
  final String currentUsername;
  final VoidCallback onLoginRequired;
  final Future<UploadedImage> Function(PickedImage image) onUploadImage;
  final Future<List<SearchUserResult>> Function(String query) onSearchUsers;
  final Future<bool> Function(ReplyDraft draft) onSubmit;

  @override
  State<_ReplyBar> createState() => _TopicReplyBarState();
}

class _TopicReplyBarState extends State<_ReplyBar> {
  static const _mentionSearchDelay = Duration(milliseconds: 300);
  static const _mentionSuggestionLimit = 5;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _images = <UploadedImage>[];
  Timer? _mentionSearchTimer;
  Timer? _draftSaveTimer;
  int _mentionSearchSerial = 0;
  _MentionRange? _activeMention;
  List<SearchUserResult> _mentionSuggestions = const [];
  bool _uploading = false;
  bool _submitting = false;
  bool _composerOpen = false;
  bool _showEmojiPanel = false;
  bool _mentionSearching = false;
  bool _collapsedForBrowsing = false;
  bool _restoringDraft = false;
  _ReplyComposerMode _mode = _ReplyComposerMode.basic;
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

  String get _mentionQuery => _activeMention?.query ?? '';

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
    _mentionSearchTimer?.cancel();
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
        setState(() {
          _showEmojiPanel = false;
          _clearMentionAutocomplete(cancelSearch: true);
        });
      } else if (_activeMention != null) {
        setState(() => _clearMentionAutocomplete(cancelSearch: true));
      }
      return;
    }
    setState(() {
      _composerOpen = false;
      _showEmojiPanel = false;
      _clearMentionAutocomplete(cancelSearch: true);
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
      _clearMentionAutocomplete(cancelSearch: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final canType = _canType;
    final expanded = _expanded;
    final colors = context.shuyoColors;
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
                    if (_activeMention != null) ...[
                      _MentionSuggestionsPanel(
                        query: _mentionQuery,
                        searching: _mentionSearching,
                        suggestions: _mentionSuggestions,
                        onSelect: _insertMentionUser,
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
                                              strokeWidth: 3),
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
                                _ReplyComposerModeMenu(
                                  mode: _mode,
                                  enabled: canType,
                                  onChanged: _setMode,
                                ),
                                const SizedBox(width: 4),
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
                                                strokeWidth: 3),
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
    _updateMentionAutocomplete();
    if (mounted) {
      setState(() {});
    }
  }

  void _updateMentionAutocomplete() {
    final mention = _detectActiveMention(_controller.value);
    if (mention == null) {
      _clearMentionAutocomplete(cancelSearch: true);
      return;
    }
    final previous = _activeMention;
    _activeMention = mention;
    if (mention.query.isEmpty) {
      _mentionSearchTimer?.cancel();
      _mentionSearchSerial += 1;
      _mentionSearching = false;
      _mentionSuggestions = const [];
      return;
    }
    if (previous?.query == mention.query && _mentionSuggestions.isNotEmpty) {
      return;
    }
    _mentionSearchTimer?.cancel();
    _mentionSearching = true;
    _mentionSuggestions = const [];
    final serial = ++_mentionSearchSerial;
    final query = mention.query;
    _mentionSearchTimer = Timer(_mentionSearchDelay, () {
      unawaited(_searchMentionUsers(query, serial));
    });
  }

  _MentionRange? _detectActiveMention(TextEditingValue value) {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return null;
    }
    final cursor = selection.baseOffset;
    if (cursor < 0 || cursor > value.text.length) {
      return null;
    }
    final beforeCursor = value.text.substring(0, cursor);
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex < 0) {
      return null;
    }
    if (atIndex > 0 &&
        !_isMentionBoundary(beforeCursor.codeUnitAt(atIndex - 1))) {
      return null;
    }
    final query = beforeCursor.substring(atIndex + 1);
    if (query.length > 32 ||
        query.contains('@') ||
        query.contains(RegExp(r'\s'))) {
      return null;
    }
    if (query.contains(RegExp(r'''[，。！？、,.!?:;；()\[\]{}<>《》"'`~]'''))) {
      return null;
    }
    return _MentionRange(start: atIndex, end: cursor, query: query);
  }

  bool _isMentionBoundary(int codeUnit) {
    return codeUnit <= 32 ||
        codeUnit == 0x3000 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D;
  }

  Future<void> _searchMentionUsers(String query, int serial) async {
    List<SearchUserResult> users;
    try {
      users = await widget.onSearchUsers(query);
    } on Object {
      users = const [];
    }
    if (!mounted ||
        serial != _mentionSearchSerial ||
        _activeMention?.query != query) {
      return;
    }
    final seen = <String>{};
    final deduped = <SearchUserResult>[];
    for (final user in users) {
      final username = user.username.trim();
      if (username.isEmpty || !seen.add(username.toLowerCase())) {
        continue;
      }
      deduped.add(user);
      if (deduped.length >= _mentionSuggestionLimit) {
        break;
      }
    }
    setState(() {
      _mentionSearching = false;
      _mentionSuggestions = List.unmodifiable(deduped);
    });
  }

  void _insertMentionUser(SearchUserResult user) {
    final mention = _activeMention;
    final username = user.username.trim();
    if (mention == null || username.isEmpty) {
      return;
    }
    final oldText = _controller.text;
    if (mention.start < 0 ||
        mention.end > oldText.length ||
        mention.start > mention.end) {
      return;
    }
    final replacement = '@$username ';
    final nextText = oldText.replaceRange(
      mention.start,
      mention.end,
      replacement,
    );
    final nextOffset = mention.start + replacement.length;
    _clearMentionAutocomplete(cancelSearch: true);
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _focusNode.requestFocus();
  }

  void _clearMentionAutocomplete({required bool cancelSearch}) {
    if (cancelSearch) {
      _mentionSearchTimer?.cancel();
      _mentionSearchSerial += 1;
    }
    _activeMention = null;
    _mentionSearching = false;
    _mentionSuggestions = const [];
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
      setState(() {
        _showEmojiPanel = false;
        _clearMentionAutocomplete(cancelSearch: true);
      });
    }
  }

  void _toggleEmojiPanel() {
    if (!_canType) {
      _handleInputTap();
      return;
    }
    if (_showEmojiPanel) {
      setState(() {
        _showEmojiPanel = false;
        _clearMentionAutocomplete(cancelSearch: true);
      });
      _focusNode.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() {
      _composerOpen = true;
      _collapsedForBrowsing = false;
      _showEmojiPanel = true;
      _clearMentionAutocomplete(cancelSearch: true);
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
      _clearMentionAutocomplete(cancelSearch: true);
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

  Future<void> _openAdvancedComposer() async {
    if (!_canType) {
      _handleInputTap();
      return;
    }
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() {
      _mode = _ReplyComposerMode.advanced;
      _discardDetachedImages();
      _showEmojiPanel = false;
      _clearMentionAutocomplete(cancelSearch: true);
    });
    await _saveDraftNow();
    if (!mounted) {
      return;
    }
    final replyToPostNumber = _replyToPostNumber;
    final draftKey = _draftKeyFor(replyToPostNumber);
    final result =
        await Navigator.of(context).push<AdvancedReplyComposerResult>(
      shuyoRoute(
        fullscreenDialog: true,
        builder: (context) => AdvancedReplyComposerPage(
          detail: widget.detail,
          initialRaw: _controller.text,
          initialImages: _imagesForMode(),
          replyToPostNumber: replyToPostNumber,
          draftKey: draftKey,
          onUploadImage: widget.onUploadImage,
          onSubmit: widget.onSubmit,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (result == null) {
      setState(() => _mode = _ReplyComposerMode.basic);
      return;
    }
    if (result.submitted) {
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
        _mode = _ReplyComposerMode.basic;
        _clearMentionAutocomplete(cancelSearch: true);
      });
      return;
    }
    _restoringDraft = true;
    _controller.text = result.raw;
    _restoringDraft = false;
    setState(() {
      _images
        ..clear()
        ..addAll(result.images);
      _composerOpen = true;
      _collapsedForBrowsing = false;
      _showEmojiPanel = false;
      _mode = _ReplyComposerMode.basic;
      _clearMentionAutocomplete(cancelSearch: true);
    });
    _scheduleDraftSave();
  }

  void _setMode(_ReplyComposerMode mode) {
    if (mode == _ReplyComposerMode.advanced) {
      unawaited(_openAdvancedComposer());
      return;
    }
    if (mode == _mode) {
      return;
    }
    setState(() {
      _mode = mode;
      _showEmojiPanel = false;
      _clearMentionAutocomplete(cancelSearch: true);
    });
    _scheduleDraftSave();
  }

  void _discardDetachedImages() {
    final raw = _controller.text;
    _images.removeWhere((image) => !isComposerImageReferenced(raw, image));
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
    final images = _imagesForMode();
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
        _clearMentionAutocomplete(cancelSearch: true);
      });
      return;
    }
    setState(() => _submitting = false);
  }

  String _composeRaw(String text, List<UploadedImage> images) {
    if (_mode == _ReplyComposerMode.advanced) {
      return text.trim();
    }
    return composeRawWithImages(text, images);
  }

  List<UploadedImage> _imagesForMode() {
    if (_mode == _ReplyComposerMode.advanced) {
      return referencedComposerImages(_controller.text, _images);
    }
    return List<UploadedImage>.of(_images);
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
      _mode = _ReplyComposerMode.basic;
      _clearMentionAutocomplete(cancelSearch: true);
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

String _pollKey(Post post, ForumPoll poll) {
  return '${post.id}:${poll.name}';
}

class _MentionRange {
  const _MentionRange({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}

class _MentionSuggestionsPanel extends StatelessWidget {
  const _MentionSuggestionsPanel({
    required this.query,
    required this.searching,
    required this.suggestions,
    required this.onSelect,
  });

  final String query;
  final bool searching;
  final List<SearchUserResult> suggestions;
  final ValueChanged<SearchUserResult> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final child = query.isEmpty
        ? _MentionHint(text: '输入用户名搜索')
        : searching
            ? const _MentionSearching()
            : suggestions.isEmpty
                ? _MentionHint(text: '没有匹配用户')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final user in suggestions)
                        _MentionSuggestionTile(
                          user: user,
                          onTap: () => onSelect(user),
                        ),
                    ],
                  );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }
}

class _MentionSuggestionTile extends StatelessWidget {
  const _MentionSuggestionTile({
    required this.user,
    required this.onTap,
  });

  final SearchUserResult user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            ForumAvatar(url: user.avatarUrl(size: 64), size: 30),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                user.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MentionSearching extends StatelessWidget {
  const _MentionSearching();

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 10),
          Text(
            '正在搜索用户',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _MentionHint extends StatelessWidget {
  const _MentionHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
      ),
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
        : context.shuyoColors.borderStrong;
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

enum _ReplyComposerMode {
  basic('基础'),
  advanced('进阶');

  const _ReplyComposerMode(this.label);

  final String label;
}

class _ReplyComposerModeMenu extends StatelessWidget {
  const _ReplyComposerModeMenu({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final _ReplyComposerMode mode;
  final bool enabled;
  final ValueChanged<_ReplyComposerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ?? context.shuyoColors.textSecondary;
    return PopupMenuButton<_ReplyComposerMode>(
      tooltip: '选择编辑模式',
      enabled: enabled,
      onSelected: onChanged,
      itemBuilder: (context) {
        return [
          for (final item in _ReplyComposerMode.values)
            PopupMenuItem(
              value: item,
              child: Row(
                children: [
                  Expanded(child: Text(item.label)),
                  if (item == mode) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ];
      },
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mode.label,
                style: TextStyle(color: color, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down, color: color),
            ],
          ),
        ),
      ),
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
    final colors = context.shuyoColors;
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
    final colors = context.shuyoColors;
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
      child: CircularProgressIndicator(strokeWidth: 3),
    );
  }
}
