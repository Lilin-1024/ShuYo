import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/composer.dart';
import '../../data/models/forum_activity.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/forum_title_rules.dart';
import '../../data/services/local_image_picker.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/composer_attachments.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/inline_emoji_panel.dart';
import '../topic/topic_detail_page.dart';
import 'profile_header.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.repository,
    required this.username,
  });

  final ForumRepository repository;
  final String username;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late Future<_UserProfileBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.username)),
      body: FutureBuilder<_UserProfileBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.person_off_outlined,
              title: '主页加载失败',
              message: snapshot.error.toString(),
              action: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _future = _load();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const EmptyState(
              icon: Icons.person_outline,
              title: '没有资料',
              message: '论坛没有返回该用户的信息',
            );
          }
          return _ProfileContent(
            bundle: data,
            onMessage: data.profile.canSendPrivateMessage
                ? () => _openMessageSheet(data.profile)
                : null,
            onOpenTopics: () => _openCreatedTopics(data.profile),
          );
        },
      ),
    );
  }

  Future<_UserProfileBundle> _load() async {
    final profile = await widget.repository.fetchUserProfile(widget.username);
    UserSummary summary;
    try {
      summary = await widget.repository.fetchUserSummary(profile.username);
    } on Object {
      summary = const UserSummary(
        likesGiven: 0,
        likesReceived: 0,
        topicsEntered: 0,
        postsReadCount: 0,
        daysVisited: 0,
        topicCount: 0,
        postCount: 0,
        timeReadSeconds: 0,
      );
    }
    return _UserProfileBundle(profile: profile, summary: summary);
  }

  void _openMessageSheet(UserProfile profile) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.lehuColors.surface,
      showDragHandle: true,
      builder: (context) {
        return _PrivateMessageSheet(
          repository: widget.repository,
          recipient: profile.username,
        );
      },
    );
  }

  Future<void> _openCreatedTopics(UserProfile profile) async {
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => _UserCreatedTopicsPage(
          repository: widget.repository,
          username: profile.username,
        ),
      ),
    );
  }
}

class _UserProfileBundle {
  const _UserProfileBundle({
    required this.profile,
    required this.summary,
  });

  final UserProfile profile;
  final UserSummary summary;
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.bundle,
    required this.onMessage,
    required this.onOpenTopics,
  });

  final _UserProfileBundle bundle;
  final VoidCallback? onMessage;
  final VoidCallback onOpenTopics;

  @override
  Widget build(BuildContext context) {
    final profile = bundle.profile;
    final summary = bundle.summary;
    final colors = context.lehuColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      children: [
        ProfileHeader(
          profile: profile,
          title: profile.username,
          subtitle: _subtitle(profile),
        ),
        if (profile.bioExcerpt.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            profile.bioExcerpt,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14.5,
              height: 1.46,
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onMessage,
            icon: const Icon(Icons.mail_outline),
            label: Text(onMessage == null ? '暂不能私信' : '发私信'),
          ),
        ),
        const SizedBox(height: 20),
        _ProfileStatList(
          summary: summary,
          onOpenTopics: onOpenTopics,
        ),
      ],
    );
  }

  String _subtitle(UserProfile profile) {
    final role = profile.admin
        ? '管理员'
        : profile.moderator
            ? '版主'
            : '用户';
    final joined = TimeFormat.compact(profile.createdAt);
    return joined.isEmpty ? role : '$role · $joined 加入';
  }
}

class _ProfileStatList extends StatelessWidget {
  const _ProfileStatList({
    required this.summary,
    required this.onOpenTopics,
  });

  final UserSummary summary;
  final VoidCallback onOpenTopics;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final stats = [
      _StatItem('发帖', '${summary.topicCount}', onTap: onOpenTopics),
      _StatItem('回复', '${summary.postCount}'),
      _StatItem('收到赞', '${summary.likesReceived}'),
      _StatItem('访问天数', '${summary.daysVisited}'),
    ];
    return Column(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          _ProfileStatRow(item: stats[i]),
          if (i != stats.length - 1) Divider(height: 1, color: colors.border),
        ],
      ],
    );
  }
}

class _UserCreatedTopicsPage extends StatefulWidget {
  const _UserCreatedTopicsPage({
    required this.repository,
    required this.username,
  });

  final ForumRepository repository;
  final String username;

  @override
  State<_UserCreatedTopicsPage> createState() => _UserCreatedTopicsPageState();
}

class _UserCreatedTopicsPageState extends State<_UserCreatedTopicsPage> {
  late Future<List<ForumActivityItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchTopicsCreatedBy(widget.username);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.username}的话题')),
      body: FutureBuilder<List<ForumActivityItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: '话题加载失败',
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
                children: const [
                  SizedBox(height: 96),
                  EmptyState(
                    icon: Icons.forum_outlined,
                    title: '还没有发布话题',
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
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: context.lehuColors.border),
              itemBuilder: (context, index) {
                final item = items[index];
                return _CreatedTopicRow(
                  item: item,
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

  Future<void> _refresh({bool force = false}) async {
    final future = widget.repository.fetchTopicsCreatedBy(
      widget.username,
      forceRefresh: force,
    );
    setState(() => _future = future);
    await future;
  }

  Future<void> _openTopic(ForumActivityItem item) async {
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => TopicDetailPage(
          repository: widget.repository,
          topic: item.toTopicListItem(),
        ),
      ),
    );
  }
}

class _CreatedTopicRow extends StatelessWidget {
  const _CreatedTopicRow({
    required this.item,
    required this.categoryName,
    required this.onTap,
  });

  final ForumActivityItem item;
  final String? categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final meta = <String>[
      if (categoryName != null && categoryName!.isNotEmpty) categoryName!,
      '${item.views} 浏览',
      '${item.replyCount} 回复',
    ];
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
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right, size: 20, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _PrivateMessageSheet extends StatefulWidget {
  const _PrivateMessageSheet({
    required this.repository,
    required this.recipient,
  });

  final ForumRepository repository;
  final String recipient;

  @override
  State<_PrivateMessageSheet> createState() => _PrivateMessageSheetState();
}

class _PrivateMessageSheetState extends State<_PrivateMessageSheet> {
  final _titleController = TextEditingController();
  final _rawController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _rawFocusNode = FocusNode();
  final _openedAt = DateTime.now();
  final _images = <UploadedImage>[];
  bool _submitting = false;
  bool _uploading = false;
  bool _showEmojiPanel = false;
  bool _normalizingTitle = false;
  bool _titleEmojiRejected = false;
  bool _lastTextFocusWasTitle = false;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_handleTitleChanged);
    _titleFocusNode.addListener(_handleTitleFocusChanged);
    _rawFocusNode.addListener(_handleRawFocusChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
    _titleFocusNode.removeListener(_handleTitleFocusChanged);
    _rawFocusNode.removeListener(_handleRawFocusChanged);
    _titleController.dispose();
    _rawController.dispose();
    _titleFocusNode.dispose();
    _rawFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '发给 ${widget.recipient}',
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: '标题',
              border: const OutlineInputBorder(),
              errorText: _titleEmojiRejected
                  ? ForumTitleRules.disallowedEmojiMessage
                  : null,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _rawController,
            focusNode: _rawFocusNode,
            minLines: 4,
            maxLines: 8,
            onTap: _handleRawTap,
            decoration: const InputDecoration(
              labelText: '内容',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          if (_images.isNotEmpty) ...[
            ComposerAttachmentPreviewRow(
              images: _images,
              onRemove: _submitting || _uploading
                  ? null
                  : (image) => setState(() => _images.remove(image)),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
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
                onPressed: _submitting || _uploading ? null : _toggleEmojiPanel,
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _showEmojiPanel
                ? InlineEmojiPanel(
                    key: const ValueKey('emoji-panel'),
                    controller: _rawController,
                  )
                : const SizedBox.shrink(
                    key: ValueKey('emoji-empty'),
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting || _uploading ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_submitting ? '发送中...' : '发送'),
            ),
          ),
        ],
      ),
    );
  }

  void _handleTitleChanged() {
    if (_normalizingTitle) {
      return;
    }
    final value = _titleController.value;
    final sanitized = ForumTitleRules.sanitizeEditingValue(value);
    final rejected = sanitized.text != value.text;
    if (rejected) {
      _normalizingTitle = true;
      _titleController.value = sanitized;
      _normalizingTitle = false;
    }
    if (mounted && _titleEmojiRejected != rejected) {
      setState(() => _titleEmojiRejected = rejected);
    }
  }

  void _handleTitleFocusChanged() {
    if (_titleFocusNode.hasFocus) {
      _lastTextFocusWasTitle = true;
    }
  }

  void _handleRawFocusChanged() {
    if (!mounted) {
      return;
    }
    if (_rawFocusNode.hasFocus) {
      _lastTextFocusWasTitle = false;
    }
    if (_rawFocusNode.hasFocus && _showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
      return;
    }
    setState(() {});
  }

  void _handleRawTap() {
    if (_showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
    }
  }

  void _toggleEmojiPanel() {
    if (_showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
      _rawFocusNode.requestFocus();
      return;
    }
    final shouldGuideTitleEmoji =
        _titleFocusNode.hasFocus || _lastTextFocusWasTitle;
    _lastTextFocusWasTitle = false;
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() {
      _showEmojiPanel = true;
      if (shouldGuideTitleEmoji) {
        _titleEmojiRejected = true;
      }
    });
  }

  Future<void> _pickAndUpload() async {
    setState(() {
      _uploading = true;
      _showEmojiPanel = false;
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
        _showSnack('图片上传失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_uploading) {
      return;
    }
    final title = _titleController.text.trim();
    final raw = composeRawWithImages(_rawController.text, _images);
    if (ForumTitleRules.containsDisallowedEmoji(title)) {
      _titleController.value = ForumTitleRules.sanitizeEditingValue(
        _titleController.value,
      );
      setState(() => _titleEmojiRejected = true);
      return;
    }
    if (title.length < 2) {
      _showSnack('标题至少 2 个字');
      return;
    }
    if (raw.length < 3) {
      _showSnack('内容至少 3 个字');
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.createPrivateMessage(
        PrivateMessageDraft(
          title: title,
          raw: raw,
          recipients: widget.recipient,
          draftKey:
              'new_private_message_${DateTime.now().millisecondsSinceEpoch}',
          images: _images,
          composerOpenDurationMs:
              DateTime.now().difference(_openedAt).inMilliseconds,
        ),
      );
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('私信已发送')));
    } on Object catch (error) {
      if (mounted) {
        _showSnack('私信发送失败：$error');
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
}

class _StatItem {
  const _StatItem(this.label, this.value, {this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;
}

class _ProfileStatRow extends StatelessWidget {
  const _ProfileStatRow({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final child = SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            item.value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (item.onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
          ],
        ],
      ),
    );
    if (item.onTap == null) {
      return child;
    }
    return InkWell(
      onTap: item.onTap,
      child: child,
    );
  }
}
