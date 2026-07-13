import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/composer.dart';
import '../../data/models/post.dart';
import '../../data/models/topic.dart';
import '../../data/models/topic_detail.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/html_text.dart';
import '../../data/services/local_image_picker.dart';
import '../../data/services/payload_factory.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/fullscreen_image_page.dart';

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
  Future<List<TopicListItem>>? _listFuture;

  @override
  void initState() {
    super.initState();
    _listFuture = widget.repository.fetchPrivateMessages();
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
    return FutureBuilder<List<TopicListItem>>(
      future: _listFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: '私信加载失败',
            message: snapshot.error.toString(),
            action: TextButton.icon(
              onPressed: _refreshList,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          );
        }
        final messages = snapshot.data ?? const <TopicListItem>[];
        if (messages.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refreshList,
            child: ListView(
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
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: messages.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, color: Color(0xFF202020)),
            itemBuilder: (context, index) {
              final topic = messages[index];
              final user = widget.repository.users[topic.originalPosterId];
              return ListTile(
                leading: ForumAvatar(
                  url: user?.avatarUrl(size: 96) ?? '',
                  size: 38,
                ),
                title: Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  topic.lastPosterLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  TimeFormat.compact(topic.lastPostedAt ?? topic.createdAt),
                  style: const TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 12,
                  ),
                ),
                onTap: () => _openMessage(topic),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _refreshList() async {
    final future = widget.repository.fetchPrivateMessages(forceRefresh: true);
    setState(() => _listFuture = future);
    await future;
  }

  Future<void> _openMessage(TopicListItem topic) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _MessageDetailPage(
          repository: widget.repository,
          topic: topic,
        ),
      ),
    );
    if (mounted) {
      await _refreshList();
    }
  }
}

class _MessageDetailPage extends StatefulWidget {
  const _MessageDetailPage({
    required this.repository,
    required this.topic,
  });

  final ForumRepository repository;
  final TopicListItem topic;

  @override
  State<_MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends State<_MessageDetailPage> {
  late Future<TopicDetail?> _detailFuture;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _detailFuture = widget.repository.fetchTopicDetail(widget.topic.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _MessageDetailHeader(
              title: widget.topic.title,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: FutureBuilder<TopicDetail?>(
                future: _detailFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: '会话加载失败',
                      message: snapshot.error.toString(),
                    );
                  }
                  final detail = snapshot.data;
                  if (detail == null || detail.posts.isEmpty) {
                    return const EmptyState(
                      icon: Icons.forum_outlined,
                      title: '暂无内容',
                      message: '这个私信会话没有返回消息',
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    itemCount: detail.posts.length,
                    itemBuilder: (context, index) {
                      final post =
                          detail.posts[detail.posts.length - index - 1];
                      return _MessageBubble(
                        post: post,
                        onOpenImage: _openImagePreview,
                      );
                    },
                  );
                },
              ),
            ),
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

  Future<void> _reply(String raw, List<UploadedImage> images) async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.createReply(
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
      setState(() {
        _detailFuture = widget.repository.fetchTopicDetail(
          widget.topic.id,
          forceRefresh: true,
        );
      });
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

  void _openImagePreview(String url) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => FullscreenImagePage(url: url),
      ),
    );
  }
}

class _MessageDetailHeader extends StatelessWidget {
  const _MessageDetailHeader({
    required this.title,
    required this.onBack,
  });

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
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
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

extension on TopicListItem {
  String get lastPosterLabel {
    if (lastPostedAt == null) {
      return '$postsCount 条消息';
    }
    return '$postsCount 条消息';
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.post,
    required this.onOpenImage,
  });

  final Post post;
  final ValueChanged<String> onOpenImage;

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
                  fontSize: 12,
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
                  fontSize: 11,
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
    return SafeArea(
      top: false,
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
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final image in _images)
                      InputChip(
                        label: Text(image.filename),
                        onDeleted: widget.submitting
                            ? null
                            : () => setState(() => _images.remove(image)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
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
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '写私信',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: '发送',
                  onPressed: widget.submitting ? null : _submit,
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
          ],
        ),
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
      final uploaded = await widget.repository.uploadImage(picked);
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

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    _controller.clear();
    final images = List<UploadedImage>.of(_images);
    _images.clear();
    setState(() {});
    widget.onSubmit(text, images);
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
  final ValueChanged<String> onOpenImage;

  @override
  Widget build(BuildContext context) {
    final segments = HtmlText.parseSegments(cooked);
    if (segments.isEmpty) {
      return Text(' ', style: TextStyle(color: textColor));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segment in segments)
          if (segment.isImage)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => onOpenImage(segment.value),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
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
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                segment.value,
                style: TextStyle(color: textColor, height: 1.38),
              ),
            ),
      ],
    );
  }
}
