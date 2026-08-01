import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/composer.dart';
import '../../data/models/discourse_user.dart';
import '../../data/models/post.dart';
import '../../data/models/topic.dart';
import '../../data/models/topic_detail.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/discourse_api_client.dart';
import '../../data/services/forum_draft_store.dart';
import '../../data/services/html_text.dart';
import '../../data/services/local_image_picker.dart';
import '../../data/services/payload_factory.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/composer_attachments.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/forum_cooked_content.dart';
import '../../shared/widgets/fullscreen_image_page.dart';
import '../../shared/widgets/inline_emoji_panel.dart';
import '../profile/user_profile_page.dart';
import '../topic/topic_detail_page.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
    required this.repository,
    required this.onLoginRequired,
    this.refreshSignal = 0,
  });

  final ForumRepository repository;
  final VoidCallback onLoginRequired;
  final int refreshSignal;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  static const _hiddenPrivateMessagesPrefix = 'forum.privateMessages.hidden.';

  final _previewFutures = <int, Future<_MessageTopicPreview>>{};
  List<TopicListItem>? _topics;
  Set<int> _hiddenTopicIds = const {};
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;

  String get _hiddenPrivateMessagesKey {
    return '$_hiddenPrivateMessagesPrefix'
        '${widget.repository.profile.username.toLowerCase()}';
  }

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
      _hiddenTopicIds = const {};
      _error = null;
      _loading = true;
      unawaited(_loadInitial());
      return;
    }
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      unawaited(_refreshList());
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
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    final error = _error;
    if (error != null && _topics == null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: '私信加载失败',
        message: _friendlyForumError(error),
        action: TextButton.icon(
          onPressed: () => unawaited(_refreshList()),
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }

    final groups = _conversationGroups(_visibleTopics);
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
        separatorBuilder: (context, index) {
          return Divider(height: 1, color: context.lehuColors.border);
        },
        itemBuilder: (context, index) {
          final group = groups[index];
          return ListTile(
            leading: ForumAvatar(url: group.avatarUrl(size: 96), size: 42),
            title: Text(
              group.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LehuTextStyles.title(
                color: context.lehuColors.textPrimary,
                size: 15.5,
                weight: FontWeight.w500,
              ),
            ),
            subtitle: _TopicPreviewLine(
              future: _previewForTopic(group.latestTopic),
              fallback: group.latestTopic.title,
            ),
            trailing: Text(
              TimeFormat.compact(
                group.latestTime,
                relativeWithinDay: true,
              ),
              style: TextStyle(
                color: context.lehuColors.textMuted,
                fontSize: 12.5,
              ),
            ),
            onTap: () => _openGroup(group),
            onLongPress: () => _handleGroupLongPress(group),
          );
        },
      ),
    );
  }

  List<TopicListItem> get _visibleTopics {
    final topics = _topics;
    if (topics == null || _hiddenTopicIds.isEmpty) {
      return topics ?? const [];
    }
    return topics
        .where((topic) => !_hiddenTopicIds.contains(topic.id))
        .toList(growable: false);
  }

  Future<void> _loadInitial() async {
    try {
      final hiddenTopicIdsFuture = _loadHiddenTopicIds();
      final topics = await widget.repository.fetchPrivateMessages();
      final hiddenTopicIds = await hiddenTopicIdsFuture;
      if (!mounted) {
        return;
      }
      setState(() {
        _topics = topics;
        _hiddenTopicIds = hiddenTopicIds;
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
      final hiddenTopicIdsFuture = _loadHiddenTopicIds();
      final topics = await widget.repository.fetchPrivateMessages(
        forceRefresh: true,
      );
      final hiddenTopicIds = await hiddenTopicIdsFuture;
      if (!mounted) {
        return;
      }
      final visibleTopicIds = topics
          .where((topic) => !hiddenTopicIds.contains(topic.id))
          .map((topic) => topic.id)
          .toSet();
      setState(() {
        _topics = topics;
        _hiddenTopicIds = hiddenTopicIds;
        _previewFutures.removeWhere(
          (topicId, _) => !visibleTopicIds.contains(topicId),
        );
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
          SnackBar(
            content: Text(
              _refreshFailureMessage(error, prefix: '私信刷新失败'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<Set<int>> _loadHiddenTopicIds() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_hiddenPrivateMessagesKey) ?? const [];
    return values
        .map(int.tryParse)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
  }

  Future<void> _saveHiddenTopicIds(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final values = ids.map((id) => '$id').toList()..sort();
    await prefs.setStringList(_hiddenPrivateMessagesKey, values);
  }

  Future<void> _hidePrivateMessageTopic(int topicId) async {
    final next = {..._hiddenTopicIds, topicId};
    await _saveHiddenTopicIds(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _hiddenTopicIds = next;
      _previewFutures.remove(topicId);
    });
  }

  void _handleGroupLongPress(_PrivateConversationGroup group) {
    if (group.topics.length > 1) {
      return;
    }
    unawaited(_deleteLocalConversation(group.topics.first));
  }

  Future<bool> _deleteLocalConversation(TopicListItem topic) async {
    final confirmed = await _confirmLocalConversationDeletion(context, topic);
    if (!confirmed) {
      return false;
    }
    await _hidePrivateMessageTopic(topic.id);
    if (mounted) {
      _showSnack('会话已删除');
    }
    return true;
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
    try {
      final detail = await widget.repository.fetchTopicDetail(topic.id);
      return _MessageTopicPreview.fromDetail(detail, topic);
    } on Object {
      _previewFutures.remove(topic.id);
      return _MessageTopicPreview.fromDetail(null, topic);
    }
  }

  Future<void> _openGroup(_PrivateConversationGroup group) async {
    if (group.topics.length == 1) {
      await _openMessage(
        group.topics.first,
        group.displayName,
        group.singleUsername,
      );
    } else {
      await Navigator.of(context).push<void>(
        lehuRoute(
          builder: (context) => _MessageTopicSelectionPage(
            repository: widget.repository,
            group: group,
            previewForTopic: _previewForTopic,
            onHideTopic: _hidePrivateMessageTopic,
          ),
        ),
      );
    }
    if (mounted) {
      await _refreshList();
    }
  }

  Future<void> _openMessage(
    TopicListItem topic,
    String counterpartTitle,
    String? counterpartUsername,
  ) {
    return Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => _MessageDetailPage(
          repository: widget.repository,
          topic: topic,
          counterpartTitle: counterpartTitle,
          counterpartUsername: counterpartUsername,
        ),
      ),
    );
  }
}

class _MessageTopicSelectionPage extends StatefulWidget {
  const _MessageTopicSelectionPage({
    required this.repository,
    required this.group,
    required this.previewForTopic,
    required this.onHideTopic,
  });

  final ForumRepository repository;
  final _PrivateConversationGroup group;
  final Future<_MessageTopicPreview> Function(TopicListItem topic)
      previewForTopic;
  final Future<void> Function(int topicId) onHideTopic;

  @override
  State<_MessageTopicSelectionPage> createState() =>
      _MessageTopicSelectionPageState();
}

class _MessageTopicSelectionPageState
    extends State<_MessageTopicSelectionPage> {
  late List<TopicListItem> _topics;

  @override
  void initState() {
    super.initState();
    _topics = widget.group.topics.toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(widget.group.displayName)),
      body: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _topics.length,
        separatorBuilder: (context, index) =>
            Divider(height: 1, color: colors.border),
        itemBuilder: (context, index) {
          final topic = _topics[index];
          return ListTile(
            title: Text(
              topic.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LehuTextStyles.title(
                color: colors.textPrimary,
                size: 15.5,
                weight: FontWeight.w500,
              ),
            ),
            subtitle: _TopicPreviewLine(
              future: widget.previewForTopic(topic),
              fallback: topic.title,
            ),
            trailing: Text(
              TimeFormat.compact(
                topic.lastPostedAt ?? topic.createdAt,
                relativeWithinDay: true,
              ),
              style: TextStyle(color: colors.textMuted, fontSize: 12.5),
            ),
            onLongPress: () => unawaited(_deleteLocalConversation(topic)),
            onTap: () {
              Navigator.of(context).push<void>(
                lehuRoute(
                  builder: (context) => _MessageDetailPage(
                    repository: widget.repository,
                    topic: topic,
                    counterpartTitle: widget.group.displayName,
                    counterpartUsername: widget.group.singleUsername,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _deleteLocalConversation(TopicListItem topic) async {
    final confirmed = await _confirmLocalConversationDeletion(context, topic);
    if (!confirmed) {
      return;
    }
    await widget.onHideTopic(topic.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _topics = _topics.where((item) => item.id != topic.id).toList();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('会话已删除')),
    );
    if (_topics.isEmpty) {
      Navigator.of(context).pop(true);
    }
  }
}

Future<bool> _confirmLocalConversationDeletion(
  BuildContext context,
  TopicListItem topic,
) async {
  final wantsDelete = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除'),
                subtitle: Text(
                  topic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(context).pop(true),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('取消'),
                onTap: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (wantsDelete != true || !context.mounted) {
    return false;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('确认删除会话'),
        content: const Text(
          '将从本机永久删除此私信会话记录。',
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
  return confirmed == true;
}

String _friendlyForumError(Object error) {
  if (error is ForumApiException) {
    return error.message;
  }
  return '操作失败，请稍后重试';
}

String _refreshFailureMessage(Object error, {required String prefix}) {
  final message = _friendlyForumError(error);
  if (message == forumRefreshTooFastMessage) {
    return message;
  }
  return '$prefix：$message';
}

class _MessageDetailPage extends StatefulWidget {
  const _MessageDetailPage({
    required this.repository,
    required this.topic,
    required this.counterpartTitle,
    this.counterpartUsername,
  });

  final ForumRepository repository;
  final TopicListItem topic;
  final String counterpartTitle;
  final String? counterpartUsername;

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
    _detail = widget.repository.cachedTopicDetail(widget.topic.id);
    _loadingInitial = _detail == null;
    unawaited(_loadInitial(showLoading: _detail == null));
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
    final colors = context.lehuColors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _MessageDetailHeader(
              title: widget.counterpartTitle,
              subtitle: widget.topic.title,
              onBack: () => Navigator.of(context).pop(),
              onOpenProfile: _openCounterpartProfile,
              onRefresh: _refreshDetail,
              refreshing: _refreshing,
            ),
            Expanded(child: _messageBody()),
            _MessageReplyBar(
              submitting: _submitting,
              repository: widget.repository,
              topicId: widget.topic.id,
              onSubmit: _reply,
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBody() {
    if (_loadingInitial) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    final error = _error;
    if (error != null && _detail == null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: '会话加载失败',
        message: _friendlyForumError(error),
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
            onOpenUser: _openUserProfile,
            onOpenInternalTopic: _openInternalTopic,
          ),
        );
      },
    );
  }

  Future<void> _loadInitial({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _loadingInitial = true;
        _error = null;
      });
    }
    try {
      final fetched = await _fetchLatestDetail();
      final detail = _mergeWithCurrentDetail(fetched);
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
        _loadingInitial = false;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      if (_detail == null) {
        setState(() {
          _error = error;
          _loadingInitial = false;
        });
      } else {
        setState(() => _loadingInitial = false);
      }
    }
  }

  Future<bool> _reply(String raw, List<UploadedImage> images) async {
    if (_submitting) {
      return false;
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
        return false;
      }
      _applyLocalPost(post);
      await _refreshDetail();
      unawaited(_warmPrivateMessageList());
      return true;
    } on Object catch (error) {
      if (mounted) {
        _showSnack('发送失败：${_friendlyForumError(error)}');
      }
      return false;
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
        _showSnack(_refreshFailureMessage(error, prefix: '刷新失败'));
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

  void _openInternalTopic(CookedLinkPreview preview) {
    final topicId = preview.topicId;
    if (topicId == null) {
      return;
    }
    Navigator.of(context).push<void>(
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
        ),
      ),
    );
  }

  void _openUserProfile(String username) {
    final trimmed = username.trim();
    if (trimmed.isEmpty) {
      return;
    }
    Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => UserProfilePage(
          repository: widget.repository,
          username: trimmed,
        ),
      ),
    );
  }

  void _openCounterpartProfile() {
    final username = widget.counterpartUsername;
    if (username == null || username.isEmpty) {
      return;
    }
    Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => UserProfilePage(
          repository: widget.repository,
          username: username,
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
    this.onOpenProfile,
    required this.onRefresh,
    required this.refreshing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback? onOpenProfile;
  final Future<void> Function() onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Container(
      height: 62,
      padding: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onOpenProfile,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LehuTextStyles.title(
                        color: colors.textPrimary,
                        size: 15.5,
                        weight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 3),
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
    required this.onOpenUser,
    required this.onOpenInternalTopic,
  });

  final Post post;
  final void Function(List<String> urls, int initialIndex) onOpenImage;
  final ValueChanged<String> onOpenUser;
  final ValueChanged<CookedLinkPreview> onOpenInternalTopic;

  @override
  Widget build(BuildContext context) {
    final mine = post.yours;
    final colors = context.lehuColors;
    final bubbleColor = mine ? colors.selectedFill : colors.surfaceAlt;
    final primaryText = mine ? colors.onSelectedFill : colors.textPrimary;
    final secondaryText = mine
        ? colors.onSelectedFill.withValues(alpha: 0.62)
        : colors.textTertiary;
    final timeText =
        mine ? colors.onSelectedFill.withValues(alpha: 0.48) : colors.textMuted;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => _copyText(context),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  post.username,
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 4),
                ForumCookedContent(
                  cooked: post.cooked,
                  textColor: primaryText,
                  textSize: 15,
                  textBottomSpacing: 6,
                  imageBottomSpacing: 8,
                  imageErrorHeight: 130,
                  imageFit: BoxFit.contain,
                  compactCards: true,
                  onOpenUser: onOpenUser,
                  onOpenImage: onOpenImage,
                  onOpenInternalTopic: onOpenInternalTopic,
                ),
                const SizedBox(height: 4),
                Text(
                  TimeFormat.compact(post.createdAt),
                  style: TextStyle(
                    color: timeText,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    messenger.showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }
}

class _MessageReplyBar extends StatefulWidget {
  const _MessageReplyBar({
    required this.submitting,
    required this.repository,
    required this.topicId,
    required this.onSubmit,
  });

  final bool submitting;
  final ForumRepository repository;
  final int topicId;
  final Future<bool> Function(String raw, List<UploadedImage> images) onSubmit;

  @override
  State<_MessageReplyBar> createState() => _MessageReplyBarState();
}

class _MessageReplyBarState extends State<_MessageReplyBar> {
  static const _fallbackKeyboardHeight = 282.0;
  static const _keyboardHandoffDuration = Duration(milliseconds: 360);

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _images = <UploadedImage>[];
  Timer? _keyboardHandoffTimer;
  Timer? _draftSaveTimer;
  double _lastKeyboardHeight = _fallbackKeyboardHeight;
  bool _uploading = false;
  bool _submitting = false;
  bool _showEmojiPanel = false;
  bool _switchingEmojiToKeyboard = false;
  bool _restoringDraft = false;

  String get _draftKey {
    return ForumDraftStore.privateMessageReplyKey(
      username: widget.repository.profile.username,
      topicId: widget.topicId,
    );
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    _controller.addListener(_handleDraftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadDraft());
    });
  }

  @override
  void dispose() {
    _keyboardHandoffTimer?.cancel();
    _draftSaveTimer?.cancel();
    unawaited(_saveDraftNow());
    _focusNode.removeListener(_handleFocusChanged);
    _controller.removeListener(_handleDraftChanged);
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
    final colors = context.lehuColors;

    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: colors.background,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_images.isNotEmpty) ...[
              ComposerAttachmentPreviewRow(
                images: _images,
                onRemove: widget.submitting || _uploading
                    ? null
                    : (image) {
                        setState(() => _images.remove(image));
                        _scheduleDraftSave();
                      },
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '添加图片',
                  onPressed: widget.submitting || _uploading || _submitting
                      ? null
                      : _pickAndUpload,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.image_outlined),
                ),
                SizedBox(
                  width: 40,
                  child: IconButton(
                    tooltip: 'Emoji',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 48,
                    ),
                    onPressed: widget.submitting || _uploading || _submitting
                        ? null
                        : _toggleEmojiPanel,
                    icon: Icon(
                      _showEmojiPanel
                          ? Icons.keyboard_alt_outlined
                          : Icons.emoji_emotions_outlined,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
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
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: '发送',
                  onPressed: widget.submitting || _uploading || _submitting
                      ? null
                      : _submit,
                  icon: widget.submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.send),
                ),
              ],
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

  void _handleDraftChanged() {
    _scheduleDraftSave();
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
    if (_uploading) {
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty && _images.isEmpty) {
      return;
    }
    final images = List<UploadedImage>.of(_images);
    final raw = composeRawWithImages(text, images);
    setState(() => _submitting = true);
    await _saveDraftNow();
    final success = await widget.onSubmit(raw, images);
    if (!mounted) {
      return;
    }
    if (success) {
      await ForumDraftStore.remove(_draftKey);
      if (!mounted) {
        return;
      }
      _restoringDraft = true;
      _controller.clear();
      _restoringDraft = false;
      _images.clear();
      _keyboardHandoffTimer?.cancel();
      setState(() {
        _showEmojiPanel = false;
        _switchingEmojiToKeyboard = false;
        _submitting = false;
      });
      return;
    }
    setState(() => _submitting = false);
  }

  Future<void> _loadDraft() async {
    final draft = await ForumDraftStore.load(_draftKey);
    if (!mounted || draft == null) {
      return;
    }
    _restoringDraft = true;
    _controller.text = draft.raw;
    setState(() {
      _images
        ..clear()
        ..addAll(draft.images);
    });
    _restoringDraft = false;
  }

  void _scheduleDraftSave() {
    if (_restoringDraft || _submitting || widget.submitting) {
      return;
    }
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_saveDraftNow()),
    );
  }

  Future<void> _saveDraftNow() async {
    if (_restoringDraft || _submitting || widget.submitting) {
      return;
    }
    await ForumDraftStore.save(
      _draftKey,
      ForumComposerDraft(
        raw: _controller.text,
        images: List<UploadedImage>.of(_images),
      ),
    );
  }
}

class _TopicPreviewLine extends StatelessWidget {
  const _TopicPreviewLine({
    required this.future,
    required this.fallback,
  });

  final Future<_MessageTopicPreview> future;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MessageTopicPreview>(
      future: future,
      builder: (context, snapshot) {
        final previewText = snapshot.data?.text.trim();
        final fallbackText = fallback.trim();
        final text = previewText != null && previewText.isNotEmpty
            ? previewText
            : fallbackText.isNotEmpty
                ? fallbackText
                : '暂无内容';
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.lehuColors.textSecondary,
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
        .map((segment) {
          final link = segment.link;
          if (link == null) {
            return segment.textValue;
          }
          final excerpt = link.excerpt;
          return excerpt == null || excerpt.isEmpty
              ? link.title
              : '${link.title} $excerpt';
        })
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

  String? get singleUsername {
    if (userIds.length != 1) {
      return null;
    }
    final username = users[userIds.first]?.username;
    return username == null || username.isEmpty ? null : username;
  }

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
