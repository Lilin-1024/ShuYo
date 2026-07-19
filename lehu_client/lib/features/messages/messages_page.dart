import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/composer.dart';
import '../../data/models/discourse_user.dart';
import '../../data/models/post.dart';
import '../../data/models/topic.dart';
import '../../data/models/topic_detail.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/html_text.dart';
import '../../data/services/local_image_picker.dart';
import '../../data/services/payload_factory.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/composer_attachments.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/forum_network_image.dart';
import '../../shared/widgets/fullscreen_image_page.dart';
import '../../shared/widgets/inline_emoji_panel.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    required this.repository,
    required this.onLoginRequired,
  });

  final ForumRepository repository;
  final VoidCallback onLoginRequired;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _previewFutures = <int, Future<_MessageTopicPreview>>{};
  List<TopicListItem>? _topics;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitial());
  }

  @override
  void didUpdateWidget(covariant MessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _previewFutures.clear();
      _topics = null;
      _error = null;
      _loading = true;
      unawaited(_loadInitial());
    }
  }

  @override
  Widget build(BuildContext context) {
    return _messageList();
  }

  Widget _messageList() {
    if (!widget.repository.isOnline) {
      return EmptyState(
        icon: Icons.forum_outlined,
        title: '登录后查看私信',
        message: '私信会话需要乐乎登录态',
        action: FilledButton.icon(
          onPressed: widget.onLoginRequired,
          icon: const Icon(Icons.login),
          label: const Text('登录乐乎'),
        ),
      );
    }
    if (_loading && _topics == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null && _topics == null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: '私信加载失败',
        message: error.toString(),
        action: TextButton.icon(
          onPressed: () => unawaited(_refreshList()),
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }

    final groups = _conversationGroups(_topics ?? const []);
    if (groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshList,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 96),
            EmptyState(
              icon: Icons.mark_chat_unread_outlined,
              title: '暂无私信',
              message: '从用户主页可以发起新的私信会话',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshList,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: groups.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, color: Color(0xFF202020)),
        itemBuilder: (context, index) {
          final group = groups[index];
          return ListTile(
            leading: ForumAvatar(url: group.avatarUrl(size: 96), size: 42),
            title: Text(
              group.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LehuTextStyles.title(
                size: 15.5,
                weight: FontWeight.w500,
              ),
            ),
            subtitle: _TopicPreviewLine(
              future: _previewForTopic(group.latestTopic),
            ),
            trailing: Text(
              TimeFormat.compact(group.latestTime),
              style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 12.5),
            ),
            onTap: () => _openGroup(group),
          );
        },
      ),
    );
  }

  Future<void> _loadInitial() async {
    try {
      final topics = await widget.repository.fetchPrivateMessages();
      if (!mounted) {
        return;
      }
      setState(() {
        _topics = topics;
        _error = null;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _refreshList() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      final topics = await widget.repository.fetchPrivateMessages(
        forceRefresh: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _topics = topics;
        _previewFutures.clear();
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      if (_topics == null) {
        setState(() => _error = error);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('私信刷新失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  List<_PrivateConversationGroup> _conversationGroups(
    List<TopicListItem> topics,
  ) {
    final grouped = <String, List<TopicListItem>>{};
    final groupUsers = <String, List<int>>{};
    for (final topic in topics) {
      final userIds = _otherUserIds(topic);
      final key = userIds.isEmpty ? 'topic:${topic.id}' : userIds.join(':');
      grouped.putIfAbsent(key, () => []).add(topic);
      groupUsers[key] = userIds;
    }
    final groups = [
      for (final entry in grouped.entries)
        _PrivateConversationGroup(
          userIds: groupUsers[entry.key] ?? const [],
          users: widget.repository.users,
          topics: entry.value
            ..sort((a, b) => _topicTime(b).compareTo(_topicTime(a))),
        ),
    ];
    groups.sort((a, b) => _topicTime(b.latestTopic).compareTo(
          _topicTime(a.latestTopic),
        ));
    return groups;
  }

  List<int> _otherUserIds(TopicListItem topic) {
    final currentUserId = widget.repository.profile.id;
    final ids = [
      ...topic.posters,
      ...topic.participants,
    ].map((poster) => poster.userId).toSet()
      ..remove(currentUserId);
    if (ids.isEmpty) {
      final originalPosterId = topic.originalPosterId;
      if (originalPosterId != null && originalPosterId != currentUserId) {
        ids.add(originalPosterId);
      }
    }
    final sorted = ids.toList()..sort();
    return sorted;
  }

  Future<_MessageTopicPreview> _previewForTopic(TopicListItem topic) {
    return _previewFutures[topic.id] ??= _loadPreview(topic);
  }

  Future<_MessageTopicPreview> _loadPreview(TopicListItem topic) async {
    final detail = await widget.repository.fetchTopicDetail(topic.id);
    return _MessageTopicPreview.fromDetail(detail, topic);
  }

  Future<void> _openGroup(_PrivateConversationGroup group) async {
    if (group.topics.length == 1) {
      await _openMessage(group.topics.first, group.displayName);
    } else {
      await Navigator.of(context).push<void>(
        lehuRoute(
          builder: (context) => _MessageTopicSelectionPage(
            repository: widget.repository,
            group: group,
            previewForTopic: _previewForTopic,
          ),
        ),
      );
    }
    if (mounted) {
      await _refreshList();
    }
  }

  Future<void> _openMessage(TopicListItem topic, String counterpartTitle) {
    return Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => _MessageDetailPage(
          repository: widget.repository,
          topic: topic,
          counterpartTitle: counterpartTitle,
        ),
      ),
    );
  }
}

class _MessageTopicSelectionPage extends StatelessWidget {
  const _MessageTopicSelectionPage({
    required this.repository,
    required this.group,
    required this.previewForTopic,
  });

  final ForumRepository repository;
  final _PrivateConversationGroup group;
  final Future<_MessageTopicPreview> Function(TopicListItem topic)
      previewForTopic;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(group.displayName)),
      body: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: group.topics.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, color: Color(0xFF202020)),
        itemBuilder: (context, index) {
          final topic = group.topics[index];
          return ListTile(
            title: Text(
              topic.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LehuTextStyles.title(
                size: 15.5,
                weight: FontWeight.w500,
              ),
            ),
            subtitle: _TopicPreviewLine(future: previewForTopic(topic)),
            trailing: Text(
              TimeFormat.compact(topic.lastPostedAt ?? topic.createdAt),
              style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 12.5),
            ),
            onTap: () {
              Navigator.of(context).push<void>(
                lehuRoute(
                  builder: (context) => _MessageDetailPage(
                    repository: repository,
                    topic: topic,
                    counterpartTitle: group.displayName,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MessageDetailPage extends StatefulWidget {
  const _MessageDetailPage({
    required this.repository,
    required this.topic,
    required this.counterpartTitle,
  });

  final ForumRepository repository;
  final TopicListItem topic;
  final String counterpartTitle;

  @override
  State<_MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends State<_MessageDetailPage> {
  static const _minRefreshIndicatorDuration = Duration(milliseconds: 800);
  static const _autoRefreshInterval = Duration(seconds: 6);

  TopicDetail? _detail;
  Object? _error;
  bool _loadingInitial = true;
  bool _submitting = false;
  bool _refreshing = false;
  bool _autoRefreshing = false;
  Timer? _autoRefreshTimer;
  Set<int> _animatedPostIds = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitial());
    _autoRefreshTimer = Timer.periodic(
      _autoRefreshInterval,
      (_) => unawaited(_refreshDetailSilently()),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _MessageDetailHeader(
              title: widget.counterpartTitle,
              subtitle: widget.topic.title,
              onBack: () => Navigator.of(context).pop(),
              onRefresh: _refreshDetail,
              refreshing: _refreshing,
            ),
            Expanded(child: _messageBody()),
            _MessageReplyBar(
              submitting: _submitting,
              repository: widget.repository,
              onSubmit: _reply,
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBody() {
    if (_loadingInitial) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null && _detail == null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: '会话加载失败',
        message: error.toString(),
        action: TextButton.icon(
          onPressed: () => unawaited(_loadInitial()),
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }
    final detail = _detail;
    final posts = detail?.posts ?? const <Post>[];
    if (detail == null || posts.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: '暂无内容',
        message: '这个私信会话没有返回消息',
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[posts.length - index - 1];
        return _AnimatedMessageBubble(
          key: ValueKey(post.id),
          animate: _animatedPostIds.contains(post.id),
          child: _MessageBubble(
            post: post,
            onOpenImage: _openImagePreview,
          ),
        );
      },
    );
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loadingInitial = true;
      _error = null;
    });
    try {
      final detail = await _fetchLatestDetail();
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
        _loadingInitial = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loadingInitial = false;
      });
    }
  }

  Future<void> _reply(String raw, List<UploadedImage> images) async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final post = await widget.repository.createReply(
        ReplyDraft(
          topicId: widget.topic.id,
          categoryId: 0,
          raw: raw,
          archetype: 'regular',
          images: images,
        ),
      );
      if (!mounted) {
        return;
      }
      _applyLocalPost(post);
      await _refreshDetail();
      unawaited(_warmPrivateMessageList());
    } on Object catch (error) {
      if (mounted) {
        _showSnack('发送失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _refreshDetail() async {
    if (_refreshing) {
      return;
    }
    final startedAt = DateTime.now();
    final previousIds = _detail?.posts.map((post) => post.id).toSet() ?? {};
    setState(() => _refreshing = true);
    try {
      final fetched = await _fetchLatestDetail();
      final detail = _mergeWithCurrentDetail(fetched);
      final nextIds = detail?.posts.map((post) => post.id).toSet() ?? {};
      final newIds = nextIds.difference(previousIds);
      final changed = !_sameIntSet(previousIds, nextIds);
      final elapsed = DateTime.now().difference(startedAt);
      final remaining = _minRefreshIndicatorDuration - elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        if (changed || _detail == null) {
          _detail = detail;
          _animatedPostIds = newIds;
        }
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      if (_detail == null) {
        setState(() => _error = error);
      } else {
        _showSnack('刷新失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _refreshDetailSilently() async {
    if (!mounted ||
        _autoRefreshing ||
        _refreshing ||
        _loadingInitial ||
        _submitting ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final previousIds = _detail?.posts.map((post) => post.id).toSet() ?? {};
    _autoRefreshing = true;
    try {
      final fetched = await _fetchLatestDetail();
      final detail = _mergeWithCurrentDetail(fetched);
      final nextIds = detail?.posts.map((post) => post.id).toSet() ?? {};
      final newIds = nextIds.difference(previousIds);
      final changed = !_sameIntSet(previousIds, nextIds);
      if (!mounted) {
        return;
      }
      if (changed || (_detail == null && detail != null)) {
        setState(() {
          _detail = detail;
          _animatedPostIds = newIds;
          _error = null;
        });
      }
    } on Object {
      // 静默轮询不打扰用户；手动刷新仍会展示具体错误。
    } finally {
      _autoRefreshing = false;
    }
  }

  Future<TopicDetail?> _fetchLatestDetail() {
    return widget.repository.fetchTopicDetail(
      widget.topic.id,
      forceRefresh: true,
    );
  }

  void _applyLocalPost(Post post) {
    final current = _detail;
    if (current == null) {
      setState(() {
        _detail = TopicDetail(
          id: widget.topic.id,
          title: widget.topic.title,
          categoryId: widget.topic.categoryId,
          postsCount: 1,
          highestPostNumber: post.postNumber,
          canCreatePost: true,
          canDelete: false,
          posts: [post],
          postStreamIds: [post.id],
          archetype: 'private_message',
        );
        _animatedPostIds = {post.id};
        _error = null;
      });
      return;
    }
    setState(() {
      _detail = current.mergedWithPosts([post]);
      _animatedPostIds = {post.id};
      _error = null;
    });
  }

  TopicDetail? _mergeWithCurrentDetail(TopicDetail? fetched) {
    final current = _detail;
    if (current == null || fetched == null) {
      return fetched ?? current;
    }
    final fetchedIds = fetched.posts.map((post) => post.id).toSet();
    final missingLocalPosts = current.posts.where(
      (post) => !fetchedIds.contains(post.id),
    );
    return fetched.mergedWithPosts(missingLocalPosts);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _warmPrivateMessageList() async {
    try {
      await widget.repository.fetchPrivateMessages(forceRefresh: true);
    } on Object {
      // 会话详情已经发送成功，列表刷新失败不应打断当前阅读/回复流程。
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

class _MessageDetailHeader extends StatelessWidget {
  const _MessageDetailHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onRefresh,
    required this.refreshing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.only(right: 12),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(bottom: BorderSide(color: Color(0xFF202020))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LehuTextStyles.title(
                    size: 15.5,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _AnimatedMessageBubble extends StatefulWidget {
  const _AnimatedMessageBubble({
    super.key,
    required this.animate,
    required this.child,
  });

  final bool animate;
  final Widget child;

  @override
  State<_AnimatedMessageBubble> createState() => _AnimatedMessageBubbleState();
}

class _AnimatedMessageBubbleState extends State<_AnimatedMessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: widget.animate ? 0 : 1,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    if (widget.animate) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) {
      _controller
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.post,
    required this.onOpenImage,
  });

  final Post post;
  final void Function(List<String> urls, int initialIndex) onOpenImage;

  @override
  Widget build(BuildContext context) {
    final mine = post.yours;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFFEDEDED) : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                post.username,
                style: TextStyle(
                  color: mine ? Colors.black54 : const Color(0xFF9A9A9A),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 4),
              _MessageCookedContent(
                cooked: post.cooked,
                textColor: mine ? Colors.black : const Color(0xFFE8E8E8),
                onOpenImage: onOpenImage,
              ),
              const SizedBox(height: 4),
              Text(
                TimeFormat.compact(post.createdAt),
                style: TextStyle(
                  color: mine ? Colors.black45 : const Color(0xFF777777),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageReplyBar extends StatefulWidget {
  const _MessageReplyBar({
    required this.submitting,
    required this.repository,
    required this.onSubmit,
  });

  final bool submitting;
  final ForumRepository repository;
  final void Function(String raw, List<UploadedImage> images) onSubmit;

  @override
  State<_MessageReplyBar> createState() => _MessageReplyBarState();
}

class _MessageReplyBarState extends State<_MessageReplyBar> {
  static const _fallbackKeyboardHeight = 282.0;
  static const _inputRowHeight = 48.0;
  static const _messageFieldHeight = 42.0;
  static const _keyboardHandoffDuration = Duration(milliseconds: 360);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _images = <UploadedImage>[];
  Timer? _keyboardHandoffTimer;
  double _lastKeyboardHeight = _fallbackKeyboardHeight;
  bool _uploading = false;
  bool _showEmojiPanel = false;
  bool _switchingEmojiToKeyboard = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _keyboardHandoffTimer?.cancel();
    _focusNode.removeListener(_handleFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    if (!_showEmojiPanel && keyboardBottom > 0) {
      _lastKeyboardHeight = keyboardBottom;
    }
    final emojiHeight = _emojiPanelHeightFor(keyboardBottom);
    _completeKeyboardHandoffIfReady(keyboardBottom);

    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: const BoxDecoration(
          color: Colors.black,
          border: Border(top: BorderSide(color: Color(0xFF202020))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_images.isNotEmpty) ...[
              ComposerAttachmentPreviewRow(
                images: _images,
                onRemove: widget.submitting || _uploading
                    ? null
                    : (image) => setState(() => _images.remove(image)),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              height: _inputRowHeight,
              child: Row(
                children: [
                  IconButton(
                    tooltip: '添加图片',
                    onPressed:
                        widget.submitting || _uploading ? null : _pickAndUpload,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    tooltip: 'Emoji',
                    onPressed: widget.submitting || _uploading
                        ? null
                        : _toggleEmojiPanel,
                    icon: Icon(
                      _showEmojiPanel
                          ? Icons.keyboard_alt_outlined
                          : Icons.emoji_emotions_outlined,
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: _messageFieldHeight,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: 1,
                        onTap: _handleInputTap,
                        decoration: const InputDecoration(
                          hintText: '写私信',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: widget.submitting || _uploading ? null : _submit,
                    icon: widget.submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: emojiHeight),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              builder: (context, height, child) {
                return ClipRect(
                  child: SizedBox(
                    height: height,
                    width: double.infinity,
                    child: child,
                  ),
                );
              },
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: _lastKeyboardHeight,
                maxHeight: _lastKeyboardHeight,
                child: InlineEmojiPanel(
                  controller: _controller,
                  height: _lastKeyboardHeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _emojiPanelHeightFor(double keyboardBottom) {
    if (!_showEmojiPanel) {
      return 0;
    }
    final handoffHeight = _lastKeyboardHeight - keyboardBottom;
    return handoffHeight.clamp(0.0, _lastKeyboardHeight).toDouble();
  }

  void _completeKeyboardHandoffIfReady(double keyboardBottom) {
    if (!_switchingEmojiToKeyboard || !_showEmojiPanel) {
      return;
    }
    final remainingEmojiHeight = _lastKeyboardHeight - keyboardBottom;
    if (keyboardBottom > 0 && remainingEmojiHeight <= 8) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _switchingEmojiToKeyboard) {
          _hideEmojiPanel();
        }
      });
    }
  }

  void _handleFocusChanged() {
    if (!mounted) {
      return;
    }
    if (_focusNode.hasFocus && _showEmojiPanel) {
      _switchEmojiToKeyboard();
      return;
    }
    setState(() {});
  }

  void _handleInputTap() {
    if (_showEmojiPanel) {
      _switchEmojiToKeyboard();
    }
  }

  void _toggleEmojiPanel() {
    if (_showEmojiPanel) {
      _switchEmojiToKeyboard();
      return;
    }
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardBottom > 0) {
      _lastKeyboardHeight = keyboardBottom;
    }
    _keyboardHandoffTimer?.cancel();
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() {
      _showEmojiPanel = true;
      _switchingEmojiToKeyboard = false;
    });
  }

  void _switchEmojiToKeyboard() {
    if (!_showEmojiPanel) {
      _focusNode.requestFocus();
      return;
    }
    _keyboardHandoffTimer?.cancel();
    _keyboardHandoffTimer = Timer(_keyboardHandoffDuration, () {
      if (mounted && _switchingEmojiToKeyboard) {
        _hideEmojiPanel();
      }
    });
    setState(() => _switchingEmojiToKeyboard = true);
    _focusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _hideEmojiPanel() {
    _keyboardHandoffTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _showEmojiPanel = false;
      _switchingEmojiToKeyboard = false;
    });
  }

  Future<void> _pickAndUpload() async {
    _keyboardHandoffTimer?.cancel();
    setState(() {
      _uploading = true;
      _showEmojiPanel = false;
      _switchingEmojiToKeyboard = false;
    });
    try {
      final picked = await LocalImagePicker.pickImage();
      if (picked == null) {
        return;
      }
      final uploaded = await widget.repository.uploadImage(picked);
      _images.add(uploaded);
      if (mounted) {
        setState(() {});
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

  void _submit() {
    if (_uploading) {
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty && _images.isEmpty) {
      return;
    }
    final images = List<UploadedImage>.of(_images);
    final raw = composeRawWithImages(text, images);
    _controller.clear();
    _images.clear();
    _keyboardHandoffTimer?.cancel();
    setState(() {
      _showEmojiPanel = false;
      _switchingEmojiToKeyboard = false;
    });
    widget.onSubmit(raw, images);
  }
}

class _MessageCookedContent extends StatelessWidget {
  const _MessageCookedContent({
    required this.cooked,
    required this.textColor,
    required this.onOpenImage,
  });

  final String cooked;
  final Color textColor;
  final void Function(List<String> urls, int initialIndex) onOpenImage;

  @override
  Widget build(BuildContext context) {
    final segments = HtmlText.parseSegments(cooked);
    if (segments.isEmpty) {
      return Text(' ', style: TextStyle(color: textColor));
    }
    final imageUrls = [
      for (final segment in segments)
        if (segment.isImage) segment.value,
    ];
    final contentWidgets = <Widget>[];
    var imageIndex = 0;
    for (final segment in segments) {
      if (!segment.isImage) {
        contentWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              segment.value,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                height: 1.46,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        );
        continue;
      }
      final currentImageIndex = imageIndex++;
      contentWidgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => onOpenImage(imageUrls, currentImageIndex),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ForumNetworkImage(
                segment.value,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 130,
                    alignment: Alignment.center,
                    color: const Color(0xFF252525),
                    child: const Text('图片加载失败'),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: contentWidgets,
    );
  }
}

class _TopicPreviewLine extends StatelessWidget {
  const _TopicPreviewLine({required this.future});

  final Future<_MessageTopicPreview> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MessageTopicPreview>(
      future: future,
      builder: (context, snapshot) {
        final text = snapshot.data?.text ?? '摘要加载中...';
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFBDBDBD),
            fontSize: 14.5,
          ),
        );
      },
    );
  }
}

class _MessageTopicPreview {
  const _MessageTopicPreview({required this.text, required this.createdAt});

  final String text;
  final DateTime? createdAt;

  factory _MessageTopicPreview.fromDetail(
    TopicDetail? detail,
    TopicListItem fallback,
  ) {
    final posts = detail?.posts.where((post) => !post.isDeleted).toList();
    final post = posts == null || posts.isEmpty ? null : posts.last;
    if (post == null) {
      return _MessageTopicPreview(
        text: fallback.title,
        createdAt: fallback.lastPostedAt ?? fallback.createdAt,
      );
    }
    return _MessageTopicPreview(
      text: _previewForCooked(post.cooked),
      createdAt: post.createdAt,
    );
  }

  static String _previewForCooked(String cooked) {
    final segments = HtmlText.parseSegments(cooked);
    final hasImages = segments.any((segment) => segment.isImage);
    final text = segments
        .where((segment) => !segment.isImage)
        .map((segment) => segment.value)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) {
      return hasImages ? '[图片]' : '暂无内容';
    }
    final clipped = text.length > 48 ? '${text.substring(0, 48)}...' : text;
    return hasImages ? '$clipped [图片]' : clipped;
  }
}

class _PrivateConversationGroup {
  const _PrivateConversationGroup({
    required this.userIds,
    required this.users,
    required this.topics,
  });

  final List<int> userIds;
  final Map<int, DiscourseUser> users;
  final List<TopicListItem> topics;

  TopicListItem get latestTopic => topics.first;
  DateTime? get latestTime => latestTopic.lastPostedAt ?? latestTopic.createdAt;

  String get displayName {
    final names = userIds
        .map((id) => users[id]?.username)
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) {
      return latestTopic.title;
    }
    if (names.length <= 2) {
      return names.join('、');
    }
    return '${names.take(2).join('、')} 等 ${names.length} 人';
  }

  String avatarUrl({int size = 96}) {
    for (final id in userIds) {
      final user = users[id];
      if (user != null) {
        return user.avatarUrl(size: size);
      }
    }
    return '';
  }
}

DateTime _topicTime(TopicListItem topic) {
  return topic.lastPostedAt ??
      topic.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

bool _sameIntSet(Set<int> a, Set<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final value in a) {
    if (!b.contains(value)) {
      return false;
    }
  }
  return true;
}
