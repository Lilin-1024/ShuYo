import 'package:flutter/material.dart';

import '../../data/models/category.dart';
import '../../data/models/composer.dart';
import '../../data/models/post.dart';
import '../../data/models/topic.dart';
import '../../data/models/topic_detail.dart';
import '../../data/services/html_text.dart';
import '../../data/services/local_image_picker.dart';
import '../../data/services/payload_factory.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/emoji_picker.dart';
import '../../shared/widgets/forum_network_image.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/fullscreen_image_page.dart';
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
  final ValueChanged<int> onLikePost;
  final ValueChanged<Post> onDeletePost;
  final ValueChanged<String> onOpenUser;
  final VoidCallback onLoginRequired;

  @override
  State<TopicPage> createState() => _TopicPageState();
}

class _TopicPageState extends State<TopicPage> {
  static const _collapsedReplyCount = 2;

  final _expandedReplyParents = <int>{};

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
          child: ListView(
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
        _ReplyBar(
          enabled: detail.canCreatePost && !widget.isSubmittingReply,
          isOnline: widget.isOnline,
          isSubmitting: widget.isSubmittingReply,
          onTap: () => widget.isOnline
              ? _openComposer(context)
              : widget.onLoginRequired(),
        ),
      ],
    );
  }

  void _replyTo(Post post) {
    if (!widget.isOnline) {
      widget.onLoginRequired();
      return;
    }
    _openComposer(context, replyToPostNumber: post.postNumber);
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
    widget.onLikePost(post.id);
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

  void _openComposer(BuildContext context, {int? replyToPostNumber}) {
    final detail = widget.detail;
    if (detail == null || !detail.canCreatePost || widget.isSubmittingReply) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      showDragHandle: true,
      builder: (context) {
        return _ReplyComposer(
          replyToPostNumber: replyToPostNumber,
          onUploadImage: widget.onUploadImage,
          onSubmit: (raw, images) {
            Navigator.of(context).pop();
            widget.onCreateReply(
              ReplyDraft(
                topicId: detail.id,
                categoryId: detail.categoryId,
                raw: raw,
                replyToPostNumber: replyToPostNumber,
                archetype: detail.archetype,
                images: images,
              ),
            );
          },
        );
      },
    );
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.title,
            style: LehuTextStyles.title(
              size: 20.5,
              height: 1.2,
              weight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${category?.name ?? '未知分区'} · ${detail.postsCount} 楼',
            style: const TextStyle(color: Color(0xFFBDBDBD)),
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
    return Container(
      margin: const EdgeInsets.only(left: 46, bottom: 8),
      padding: const EdgeInsets.only(left: 12),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFF2A2A2A))),
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
                    color: const Color(0xFF1C1C1C),
                    child: const Text(
                      '图片加载失败',
                      style: TextStyle(color: Color(0xFFBDBDBD)),
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF202020))),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        metaText,
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
              ],
            ),
          ),
          if (replyContext != null) ...[
            const SizedBox(height: 8),
            Text(
              replyContext!,
              style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 12.5),
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

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.enabled,
    required this.isOnline,
    required this.isSubmitting,
    required this.onTap,
  });

  final bool enabled;
  final bool isOnline;
  final bool isSubmitting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Color(0xFF202020))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: enabled ? onTap : null,
            icon: isSubmitting
                ? const _TinyProgress(color: Colors.black)
                : const Icon(Icons.edit_outlined),
            label: Text(
              isSubmitting
                  ? '发布中...'
                  : enabled
                      ? (isOnline ? '写评论' : '登录后评论')
                      : '当前帖子不可回复',
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyComposer extends StatefulWidget {
  const _ReplyComposer({
    required this.onSubmit,
    required this.onUploadImage,
    this.replyToPostNumber,
  });

  final int? replyToPostNumber;
  final void Function(String raw, List<UploadedImage> images) onSubmit;
  final Future<UploadedImage> Function(PickedImage image) onUploadImage;

  @override
  State<_ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<_ReplyComposer> {
  final _controller = TextEditingController();
  final _images = <UploadedImage>[];
  bool _uploading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final replyTo = widget.replyToPostNumber;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            replyTo == null ? '评论主题' : '回复 #$replyTo',
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 4,
            maxLines: 8,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '写点什么...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final image in _images)
                InputChip(
                  label: Text(image.filename),
                  onDeleted: _uploading
                      ? null
                      : () => setState(() => _images.remove(image)),
                ),
              ActionChip(
                avatar: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined, size: 18),
                label: const Text('添加图片'),
                onPressed: _uploading ? null : _pickAndUpload,
              ),
              ActionChip(
                avatar: const Icon(Icons.emoji_emotions_outlined, size: 18),
                label: const Text('Emoji'),
                onPressed: () => showEmojiPicker(
                  context: context,
                  controller: _controller,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _uploading
                  ? null
                  : () {
                      final text = _controller.text.trim();
                      if (text.isEmpty) {
                        return;
                      }
                      widget.onSubmit(text, List<UploadedImage>.of(_images));
                    },
              child: const Text('发布评论'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    setState(() => _uploading = true);
    try {
      final picked = await LocalImagePicker.pickImage();
      if (picked == null) {
        return;
      }
      final uploaded = await widget.onUploadImage(picked);
      _images.add(uploaded);
      final current = _controller.text.trimRight();
      _controller.text = current.isEmpty
          ? uploaded.markdown
          : '$current\n${uploaded.markdown}';
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
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
}

class _TinyProgress extends StatelessWidget {
  const _TinyProgress({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: color,
      ),
    );
  }
}
