import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/forum_url_resolver.dart';
import '../../data/models/category.dart';
import '../../data/models/composer.dart';
import '../../data/models/post.dart';
import '../../data/models/topic.dart';
import '../../data/models/topic_detail.dart';
import '../../data/services/html_text.dart';
import '../../data/services/local_image_picker.dart';
import '../../data/services/payload_factory.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/composer_attachments.dart';
import '../../shared/widgets/empty_state.dart';
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
    required this.item,
    required this.detail,
    required this.category,
    required this.onCreateReply,
    required this.onUploadImage,
    required this.onLikePost,
    required this.onDeletePost,
    required this.onOpenUser,
    required this.onLoginRequired,
    required this.isOnline,
    required this.isSubmittingReply,
    required this.busyLikePostIds,
    required this.busyDeletePostIds,
  });

  final TopicListItem item;
  final TopicDetail? detail;
  final ForumCategory? category;
  final bool isOnline;
  final bool isSubmittingReply;
  final Set<int> busyLikePostIds;
  final Set<int> busyDeletePostIds;
  final ValueChanged<ReplyDraft> onCreateReply;
  final Future<UploadedImage> Function(PickedImage image) onUploadImage;
  final ValueChanged<Post> onLikePost;
  final ValueChanged<Post> onDeletePost;
  final ValueChanged<String> onOpenUser;
  final VoidCallback onLoginRequired;

  @override
  State<TopicPage> createState() => _TopicPageState();
}

class _TopicPageState extends State<TopicPage> {
  static const _collapsedReplyCount = 2;

  final _expandedReplyParents = <int>{};
  final _replyBarKey = GlobalKey<_TopicReplyBarState>();

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

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleContentTap,
            child: ListView(
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
                  ),
              ],
            ),
          ),
        ),
        _ReplyBar(
          key: _replyBarKey,
          enabled: detail.canCreatePost && !widget.isSubmittingReply,
          isOnline: widget.isOnline,
          isSubmitting: widget.isSubmittingReply,
          detail: detail,
          onLoginRequired: widget.onLoginRequired,
          onUploadImage: widget.onUploadImage,
          onSubmit: widget.onCreateReply,
        ),
      ],
    );
  }

  void _handleContentTap() {
    _replyBarKey.currentState?.handleOutsideTap();
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
          post: post,
          canLike: !post.yours,
          canReply: canReply && !isSubmittingReply,
          canDelete: post.postNumber != 1 && post.yours && post.canDelete,
          isLiking: busyLikePostIds.contains(post.id),
          isDeleting: busyDeletePostIds.contains(post.id),
          onReply: () => onReply(post),
          onLike: () => onLike(post),
          onDelete: () => onDelete(post),
          onOpenUser: () => onOpenUser(post.username),
          onOpenImage: onOpenImage,
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

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Container(
      margin: const EdgeInsets.only(left: 46, bottom: 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.borderStrong)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final reply in replies)
            _PostView(
              post: reply,
              compact: true,
              replyContext: reply.replyToPostNumber == parent.postNumber
                  ? null
                  : '回复 #${reply.replyToPostNumber}',
              canLike: !reply.yours,
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
  final String? replyContext;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final textSize = compact ? 15.0 : 16.0;
    final timeText = TimeFormat.compact(post.createdAt);
    final metaText = timeText.isEmpty
        ? '#${post.postNumber}'
        : '#${post.postNumber} · $timeText';
    final contentWidgets = <Widget>[];
    final segments = HtmlText.parseSegments(post.cooked);
    final imageUrls = [
      for (final segment in segments)
        if (segment.isImage) segment.value,
    ];
    var imageIndex = 0;
    for (final segment in segments) {
      if (!segment.isImage) {
        contentWidgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              segment.value,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: textSize,
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
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () => onOpenImage(imageUrls, currentImageIndex),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: ForumNetworkImage(
                segment.value,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 160,
                    alignment: Alignment.center,
                    color: colors.surfaceMuted,
                    child: Text(
                      '图片加载失败',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(vertical: compact ? 12 : 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onOpenUser,
            child: Row(
              children: [
                ForumAvatar(
                    url: post.avatarUrl(size: 96), size: compact ? 30 : 36),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
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
          if (replyContext != null) ...[
            const SizedBox(height: 8),
            Text(
              replyContext!,
              style: TextStyle(color: colors.textMuted, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 12),
          ...contentWidgets,
          Row(
            children: [
              if (canLike)
                TextButton.icon(
                  onPressed: isLiking ? null : onLike,
                  icon: isLiking
                      ? const _TinyProgress()
                      : Icon(
                          post.liked ? Icons.favorite : Icons.favorite_border,
                          size: 18,
                        ),
                  label: Text('${post.likeCount}'),
                ),
              if (canReply)
                TextButton.icon(
                  onPressed: onReply,
                  icon: const Icon(Icons.reply, size: 18),
                  label: const Text('回复'),
                ),
              if (canDelete)
                TextButton.icon(
                  onPressed: isDeleting ? null : onDelete,
                  icon: isDeleting
                      ? const _TinyProgress()
                      : const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除'),
                ),
            ],
          ),
        ],
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
    required this.onLoginRequired,
    required this.onUploadImage,
    required this.onSubmit,
  });

  final bool enabled;
  final bool isOnline;
  final bool isSubmitting;
  final TopicDetail detail;
  final VoidCallback onLoginRequired;
  final Future<UploadedImage> Function(PickedImage image) onUploadImage;
  final ValueChanged<ReplyDraft> onSubmit;

  @override
  State<_ReplyBar> createState() => _TopicReplyBarState();
}

class _TopicReplyBarState extends State<_ReplyBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _images = <UploadedImage>[];
  bool _uploading = false;
  bool _composerOpen = false;
  bool _showEmojiPanel = false;
  int? _replyToPostNumber;

  bool get _canType =>
      widget.enabled && widget.isOnline && !widget.isSubmitting && !_uploading;

  bool get _expanded =>
      _composerOpen ||
      _focusNode.hasFocus ||
      _showEmojiPanel ||
      _controller.text.trim().isNotEmpty ||
      _images.isNotEmpty ||
      _replyToPostNumber != null;

  bool get _canSend =>
      widget.isOnline &&
      !widget.isSubmitting &&
      !_uploading &&
      (_controller.text.trim().isNotEmpty || _images.isNotEmpty);

  bool get _hasDraft =>
      _controller.text.trim().isNotEmpty ||
      _images.isNotEmpty ||
      _replyToPostNumber != null;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    _controller.addListener(_handleDraftChanged);
  }

  @override
  void dispose() {
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
    setState(() {
      _composerOpen = true;
      _replyToPostNumber = postNumber;
      _showEmojiPanel = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void handleOutsideTap() {
    if (!_expanded) {
      return;
    }
    FocusScope.of(context).unfocus();
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
                            : () => setState(() => _replyToPostNumber = null),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_images.isNotEmpty) ...[
                      _AttachmentPreviewRow(
                        images: _images,
                        onRemove: widget.isSubmitting || _uploading
                            ? null
                            : (image) => setState(() => _images.remove(image)),
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
    setState(() {
      _composerOpen = true;
      _showEmojiPanel = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
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
    final text = _controller.text.trim();
    if ((text.isEmpty && _images.isEmpty) ||
        widget.isSubmitting ||
        _uploading) {
      return;
    }
    final images = List<UploadedImage>.of(_images);
    widget.onSubmit(
      ReplyDraft(
        topicId: widget.detail.id,
        categoryId: widget.detail.categoryId,
        raw: _composeRaw(text, images),
        replyToPostNumber: _replyToPostNumber,
        archetype: widget.detail.archetype,
        images: images,
      ),
    );
    setState(() {
      _controller.clear();
      _images.clear();
      _composerOpen = false;
      _replyToPostNumber = null;
      _showEmojiPanel = false;
    });
  }

  String _composeRaw(String text, List<UploadedImage> images) {
    return composeRawWithImages(text, images);
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
