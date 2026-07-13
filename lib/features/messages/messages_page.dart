import 'package:flutter/material.dart';

import '../../data/models/composer.dart';
import '../../data/models/post.dart';
import '../../data/models/topic.dart';
import '../../data/models/topic_detail.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/html_text.dart';
import '../../data/services/payload_factory.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/empty_state.dart';

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
  TopicListItem? _openedMessage;
  Future<List<TopicListItem>>? _listFuture;
  Future<TopicDetail?>? _detailFuture;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _listFuture = widget.repository.fetchPrivateMessages();
  }

  @override
  Widget build(BuildContext context) {
    final opened = _openedMessage;
    if (opened != null) {
      return _messageDetail(opened);
    }
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
        return RefreshIndicator(
          onRefresh: _refreshList,
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: messages.length + 1,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, color: Color(0xFF202020)),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('新私信'),
                  subtitle: const Text('发送给指定用户'),
                  onTap: _openNewMessageSheet,
                );
              }
              final topic = messages[index - 1];
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
                onTap: () {
                  setState(() {
                    _openedMessage = topic;
                    _detailFuture =
                        widget.repository.fetchTopicDetail(topic.id);
                  });
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _messageDetail(TopicListItem topic) {
    return Column(
      children: [
        Container(
          height: 46,
          padding: const EdgeInsets.only(right: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF202020))),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: () => setState(() => _openedMessage = null),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
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
                  final post = detail.posts[detail.posts.length - index - 1];
                  return _MessageBubble(post: post);
                },
              );
            },
          ),
        ),
        _MessageReplyBar(
          submitting: _submitting,
          onSubmit: (raw) => _reply(topic, raw),
        ),
      ],
    );
  }

  Future<void> _refreshList() async {
    final future = widget.repository.fetchPrivateMessages(forceRefresh: true);
    setState(() => _listFuture = future);
    await future;
  }

  Future<void> _reply(TopicListItem topic, String raw) async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.createReply(
        ReplyDraft(
          topicId: topic.id,
          categoryId: 0,
          raw: raw,
          archetype: 'private_message',
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _detailFuture = widget.repository.fetchTopicDetail(
          topic.id,
          forceRefresh: true,
        );
      });
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

  void _openNewMessageSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      showDragHandle: true,
      builder: (context) {
        return _NewMessageSheet(
          onSubmit: (draft) {
            Navigator.of(context).pop();
            _createPrivateMessage(draft);
          },
        );
      },
    );
  }

  Future<void> _createPrivateMessage(PrivateMessageDraft draft) async {
    try {
      await widget.repository.createPrivateMessage(draft);
      await _refreshList();
      if (mounted) {
        _showSnack('私信已发送');
      }
    } on Object catch (error) {
      if (mounted) {
        _showSnack('私信发送失败：$error');
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
  const _MessageBubble({required this.post});

  final Post post;

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
              Text(
                HtmlText.preview(post.cooked),
                style: TextStyle(
                  color: mine ? Colors.black : const Color(0xFFE8E8E8),
                  height: 1.35,
                ),
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
    required this.onSubmit,
  });

  final bool submitting;
  final ValueChanged<String> onSubmit;

  @override
  State<_MessageReplyBar> createState() => _MessageReplyBarState();
}

class _MessageReplyBarState extends State<_MessageReplyBar> {
  final _controller = TextEditingController();

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
        child: Row(
          children: [
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
      ),
    );
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    _controller.clear();
    widget.onSubmit(text);
  }
}

class _NewMessageSheet extends StatefulWidget {
  const _NewMessageSheet({required this.onSubmit});

  final ValueChanged<PrivateMessageDraft> onSubmit;

  @override
  State<_NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends State<_NewMessageSheet> {
  final _recipientController = TextEditingController();
  final _titleController = TextEditingController();
  final _rawController = TextEditingController();

  @override
  void dispose() {
    _recipientController.dispose();
    _titleController.dispose();
    _rawController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '新私信',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _recipientController,
            decoration: const InputDecoration(
              labelText: '收件人用户名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _rawController,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '内容',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              child: const Text('发送'),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    final recipients = _recipientController.text.trim();
    final title = _titleController.text.trim();
    final raw = _rawController.text.trim();
    if (recipients.isEmpty || title.isEmpty || raw.isEmpty) {
      return;
    }
    widget.onSubmit(
      PrivateMessageDraft(
        recipients: recipients,
        title: title,
        raw: raw,
        draftKey:
            'new_private_message_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
  }
}
