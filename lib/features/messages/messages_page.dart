import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../../shared/shuyo_text_styles.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
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
    this.controller,
    required this.repository,
    this.onRecoverConnection,
    this.refreshSignal = 0,
    this.showArchived = false,
    this.onArchiveViewChanged,
    this.onSelectionChanged,
    this.onRefreshStateChanged,
  });

  final MessagesPageController? controller;
  final ForumRepository repository;
  final Future<ForumRecoveryResult> Function()? onRecoverConnection;
  final int refreshSignal;
  final bool showArchived;
  final ValueChanged<bool>? onArchiveViewChanged;
  final ValueChanged<bool>? onSelectionChanged;
  final ValueChanged<bool>? onRefreshStateChanged;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class MessagesPageController {
  _MessagesPageState? _state;

  Future<void> refresh() {
    return _state?._refreshList() ?? Future<void>.value();
  }

  void _attach(_MessagesPageState state) {
    _state = state;
  }

  void _detach(_MessagesPageState state) {
    if (_state == state) {
      _state = null;
    }
  }
}

class _MessagesPageState extends State<MessagesPage> {
  static const _archivedPrivateMessagesPrefix =
      'forum.privateMessages.archived.v1.';
  static const _legacyHiddenPrivateMessagesPrefix =
      'forum.privateMessages.hidden.';

  final _previewFutures = <int, Future<_MessageTopicPreview>>{};
  final _previewVersions = <int, _MessageTopicVersion>{};
  final _messageScrollController = ScrollController();
  List<TopicListItem>? _topics;
  Set<int> _archivedTopicIds = const {};
  Set<int> _selectedTopicIds = {};
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;
  late bool _showArchived;
  int _refreshOperationId = 0;
  double _messageRowExtent = 0;

  String get _archivedPrivateMessagesKey {
    return '$_archivedPrivateMessagesPrefix'
        '${widget.repository.profile.username.toLowerCase()}';
  }

  String get _legacyHiddenPrivateMessagesKey {
    return '$_legacyHiddenPrivateMessagesPrefix'
        '${widget.repository.profile.username.toLowerCase()}';
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _showArchived = widget.showArchived;
    unawaited(_loadInitial());
  }

  @override
  void didUpdateWidget(covariant MessagesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.repository != widget.repository) {
      _refreshOperationId++;
      if (_refreshing) {
        _refreshing = false;
        widget.onRefreshStateChanged?.call(false);
      }
      _previewFutures.clear();
      _previewVersions.clear();
      _topics = null;
      _archivedTopicIds = const {};
      _selectedTopicIds = {};
      widget.onSelectionChanged?.call(false);
      _error = null;
      _loading = true;
      _showArchived = widget.showArchived;
      _messageRowExtent = 0;
      unawaited(_loadInitial());
      return;
    }
    if (oldWidget.showArchived != widget.showArchived) {
      _showArchived = widget.showArchived;
      _selectedTopicIds = {};
      widget.onSelectionChanged?.call(false);
    }
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      unawaited(_refreshList(silent: true, showIndicator: false));
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _messageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _messageList();
  }

  Widget _messageList() {
    if (!widget.repository.hasLocalAccount) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: '暂未登录乐乎论坛',
        message: '登录后可查看论坛消息',
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
      return _messageListWithPullGesture(
        child: ListView(
          controller: _messageScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 96),
            EmptyState(
              icon: _showArchived
                  ? Icons.archive_outlined
                  : Icons.mark_chat_unread_outlined,
              title: _showArchived
                  ? '暂无归档消息'
                  : widget.repository.isCacheOnly &&
                          !widget.repository.hasCachedPrivateMessages
                      ? '无法连接论坛'
                      : '暂无私信',
              message: _showArchived
                  ? '返回消息列表查看新消息'
                  : widget.repository.isCacheOnly &&
                          !widget.repository.hasCachedPrivateMessages
                      ? '请尝试重新登录。'
                      : '从用户主页可以发起新的私信会话',
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_selectedTopicIds.isNotEmpty) _selectionBar(),
        Expanded(
          child: _messageListWithPullGesture(
            child: ListView.separated(
              controller: _messageScrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: groups.length,
              separatorBuilder: (context, index) {
                return Divider(height: 1, color: context.shuyoColors.border);
              },
              itemBuilder: (context, index) => _MessageRowSizeReporter(
                onSizeChanged: index == 0 ? _setMessageRowExtent : null,
                child: _buildGroupItem(groups[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _messageListWithPullGesture({required Widget child}) {
    return _ArchivePullToSwitch(
      showArchived: _showArchived,
      threshold: _archivePullThreshold,
      onSwitch: _setArchiveView,
      child: child,
    );
  }

  double get _archivePullThreshold {
    if (_messageRowExtent <= 0) {
      return 84;
    }
    return _messageRowExtent * 1.5;
  }

  void _setMessageRowExtent(Size size) {
    if (!mounted || size.height <= 0 || size.height == _messageRowExtent) {
      return;
    }
    setState(() => _messageRowExtent = size.height);
  }

  Widget _buildGroupItem(_PrivateConversationGroup group) {
    final colors = context.shuyoColors;
    final selected = _isGroupSelected(group);
    final archived = _showArchived;
    final tile = ListTile(
      selected: selected,
      leading: _groupLeading(group, selected),
      title: Text(
        group.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ShuYoTextStyles.title(
          color: colors.textPrimary,
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
        style: TextStyle(color: colors.textMuted, fontSize: 12.5),
      ),
      onTap: () {
        if (_selectedTopicIds.isNotEmpty) {
          _toggleGroupSelection(group);
        } else {
          unawaited(_openGroup(group));
        }
      },
      onLongPress: () => _toggleGroupSelection(group),
    );
    if (_selectedTopicIds.isNotEmpty) {
      return tile;
    }
    return Dismissible(
      key: ValueKey('message-group-${group.topicIds.join('-')}'),
      direction: DismissDirection.endToStart,
      background: _ArchiveDismissBackground(archived: archived),
      onDismissed: (_) => unawaited(
        _setTopicsArchived(
          group.topicIds,
          archived: !archived,
        ),
      ),
      child: tile,
    );
  }

  Widget _groupLeading(_PrivateConversationGroup group, bool selected) {
    final avatar = ForumAvatar(
      url: group.avatarUrl(size: 96),
      size: 42,
      privateImage: true,
    );
    if (_selectedTopicIds.isEmpty) {
      return avatar;
    }
    return Checkbox(
      value: selected,
      onChanged: (_) => _toggleGroupSelection(group),
    );
  }

  Widget _selectionBar() {
    final colors = context.shuyoColors;
    final archived = _showArchived;
    return Container(
      height: 52,
      color: colors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '取消选择',
            onPressed: () => _setSelectedTopicIds(const {}),
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text(
              '已选择 ${_selectedTopicIds.length} 个会话',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: archived ? '取消归档' : '归档',
            onPressed: () => unawaited(
              _setTopicsArchived(
                _selectedTopicIds,
                archived: !archived,
              ),
            ),
            icon: Icon(
              archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
          ),
        ],
      ),
    );
  }

  List<TopicListItem> get _visibleTopics {
    final topics = _topics;
    if (topics == null) {
      return topics ?? const [];
    }
    return topics
        .where((topic) => _archivedTopicIds.contains(topic.id) == _showArchived)
        .toList(growable: false);
  }

  Future<void> _loadInitial() async {
    try {
      final archivedTopicIdsFuture = _loadArchivedTopicIds();
      final topics = await widget.repository.fetchPrivateMessages();
      final archivedTopicIds = await archivedTopicIdsFuture;
      if (!mounted) {
        return;
      }
      setState(() {
        _topics = topics;
        _archivedTopicIds = archivedTopicIds;
        _error = null;
        _loading = false;
      });
      _updatePreviewVersions(topics);
      unawaited(_refreshList(silent: true, showIndicator: false));
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

  Future<void> _refreshList({
    bool silent = false,
    bool showIndicator = true,
  }) async {
    if (_refreshing) {
      return;
    }
    if (!widget.repository.isOnline && silent) {
      return;
    }
    final operationId = ++_refreshOperationId;
    if (showIndicator) {
      setState(() => _refreshing = true);
      widget.onRefreshStateChanged?.call(true);
    } else {
      _refreshing = true;
    }
    var refreshRepository = widget.repository;
    try {
      if (!refreshRepository.isOnline) {
        final recovery = await widget.onRecoverConnection?.call() ??
            ForumRecoveryResult(
              status: ForumRecoveryStatus.unavailable,
              repository: refreshRepository,
            );
        refreshRepository = recovery.repository;
        if (!recovery.isRestored || !refreshRepository.isOnline) {
          if (!silent && mounted) {
            _showSnack(_forumRecoveryMessage(recovery));
          }
          return;
        }
      }
      final archivedTopicIdsFuture = _loadArchivedTopicIds();
      final topics = await refreshRepository.fetchPrivateMessages(
        forceRefresh: true,
      );
      final archivedTopicIds = await archivedTopicIdsFuture;
      if (!mounted) {
        return;
      }
      final topicIds = topics.map((topic) => topic.id).toSet();
      _invalidateChangedPreviews(topics);
      setState(() {
        _topics = topics;
        _archivedTopicIds = archivedTopicIds;
        _previewFutures.removeWhere(
          (topicId, _) => !topicIds.contains(topicId),
        );
        _error = null;
      });
      _updatePreviewVersions(topics);
    } on Object catch (error) {
      if (error is ForumAuthException) {
        refreshRepository.markAuthenticationRequired();
      } else if (_isForumTransportError(error)) {
        refreshRepository.markConnectionUnavailable();
      }
      if (!mounted) {
        return;
      }
      if (_topics == null) {
        setState(() => _error = error);
      } else if (!silent) {
        _showSnack(_refreshFailureMessage(error, prefix: '私信刷新失败'));
      }
    } finally {
      if (mounted && operationId == _refreshOperationId) {
        _refreshing = false;
        if (showIndicator) {
          widget.onRefreshStateChanged?.call(false);
        }
      }
    }
  }

  Future<Set<int>> _loadArchivedTopicIds() async {
    final prefs = await SharedPreferences.getInstance();
    final archived = _parseTopicIds(
      prefs.getStringList(_archivedPrivateMessagesKey),
    );
    final legacyHidden = _parseTopicIds(
      prefs.getStringList(_legacyHiddenPrivateMessagesKey),
    );
    if (legacyHidden.isEmpty) {
      return archived;
    }
    final migrated = {...archived, ...legacyHidden};
    await prefs.setStringList(
      _archivedPrivateMessagesKey,
      _sortedTopicIdStrings(migrated),
    );
    await prefs.remove(_legacyHiddenPrivateMessagesKey);
    return migrated;
  }

  Set<int> _parseTopicIds(List<String>? values) {
    return (values ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
  }

  List<String> _sortedTopicIdStrings(Set<int> ids) {
    return ids.map((id) => '$id').toList()..sort();
  }

  Future<void> _saveArchivedTopicIds(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _archivedPrivateMessagesKey,
      _sortedTopicIdStrings(ids),
    );
  }

  Future<void> _setTopicsArchived(
    Iterable<int> topicIds, {
    required bool archived,
  }) async {
    final ids = topicIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final next = {..._archivedTopicIds};
    if (archived) {
      next.addAll(ids);
    } else {
      next.removeAll(ids);
    }
    await _saveArchivedTopicIds(next);
    if (!mounted) {
      return;
    }
    final nextSelection = {..._selectedTopicIds}..removeAll(ids);
    final selectionChanged = !_sameIntSet(
      _selectedTopicIds,
      nextSelection,
    );
    setState(() {
      _archivedTopicIds = next;
      _selectedTopicIds = nextSelection;
    });
    if (selectionChanged) {
      widget.onSelectionChanged?.call(nextSelection.isNotEmpty);
    }
    _showSnack(archived ? '已归档' : '已取消归档');
  }

  void _setArchiveView(bool showArchived) {
    if (_showArchived == showArchived) {
      return;
    }
    final hadSelection = _selectedTopicIds.isNotEmpty;
    setState(() {
      _showArchived = showArchived;
      _selectedTopicIds = {};
    });
    if (hadSelection) {
      widget.onSelectionChanged?.call(false);
    }
    widget.onArchiveViewChanged?.call(showArchived);
    _resetMessageListPosition();
  }

  void _resetMessageListPosition() {
    void animateToTop() {
      if (!mounted || !_messageScrollController.hasClients) {
        return;
      }
      final position = _messageScrollController.position;
      final target = position.minScrollExtent;
      if ((position.pixels - target).abs() < 0.5) {
        return;
      }
      unawaited(
        _messageScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    }

    animateToTop();
    WidgetsBinding.instance.addPostFrameCallback((_) => animateToTop());
  }

  bool _isGroupSelected(_PrivateConversationGroup group) {
    return group.topicIds.every(_selectedTopicIds.contains);
  }

  void _toggleGroupSelection(_PrivateConversationGroup group) {
    final ids = group.topicIds;
    final next = {..._selectedTopicIds};
    if (_isGroupSelected(group)) {
      next.removeAll(ids);
    } else {
      next.addAll(ids);
    }
    _setSelectedTopicIds(next);
  }

  void _setSelectedTopicIds(Iterable<int> topicIds) {
    final next = topicIds.toSet();
    if (_sameIntSet(_selectedTopicIds, next)) {
      return;
    }
    setState(() => _selectedTopicIds = next);
    widget.onSelectionChanged?.call(next.isNotEmpty);
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

  void _invalidateChangedPreviews(Iterable<TopicListItem> topics) {
    for (final topic in topics) {
      final previous = _previewVersions[topic.id];
      if (previous != null &&
          previous != _MessageTopicVersion.fromTopic(topic)) {
        _previewFutures.remove(topic.id);
      }
    }
  }

  void _updatePreviewVersions(Iterable<TopicListItem> topics) {
    final ids = <int>{};
    for (final topic in topics) {
      ids.add(topic.id);
      _previewVersions[topic.id] = _MessageTopicVersion.fromTopic(topic);
    }
    _previewVersions.removeWhere((topicId, _) => !ids.contains(topicId));
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
        shuyoRoute(
          builder: (context) => _MessageTopicSelectionPage(
            repository: widget.repository,
            onRecoverConnection: widget.onRecoverConnection,
            group: group,
            previewForTopic: _previewForTopic,
            archived: _showArchived,
            onSetTopicsArchived: _setTopicsArchived,
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
      shuyoRoute(
        builder: (context) => _MessageDetailPage(
          repository: widget.repository,
          onRecoverConnection: widget.onRecoverConnection,
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
    this.onRecoverConnection,
    required this.group,
    required this.previewForTopic,
    required this.archived,
    required this.onSetTopicsArchived,
  });

  final ForumRepository repository;
  final Future<ForumRecoveryResult> Function()? onRecoverConnection;
  final _PrivateConversationGroup group;
  final Future<_MessageTopicPreview> Function(TopicListItem topic)
      previewForTopic;
  final bool archived;
  final Future<void> Function(
    Iterable<int> topicIds, {
    required bool archived,
  }) onSetTopicsArchived;

  @override
  State<_MessageTopicSelectionPage> createState() =>
      _MessageTopicSelectionPageState();
}

class _MessageTopicSelectionPageState
    extends State<_MessageTopicSelectionPage> {
  late List<TopicListItem> _topics;
  final Set<int> _selectedTopicIds = {};

  @override
  void initState() {
    super.initState();
    _topics = widget.group.topics.toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final hasSelection = _selectedTopicIds.isNotEmpty;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          hasSelection
              ? '已选择 ${_selectedTopicIds.length} 个会话'
              : widget.group.displayName,
        ),
        actions: [
          if (hasSelection)
            IconButton(
              tooltip: widget.archived ? '取消归档' : '归档',
              onPressed: () => unawaited(_applyArchiveSelection()),
              icon: Icon(
                widget.archived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
            ),
        ],
      ),
      body: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _topics.length,
        separatorBuilder: (context, index) =>
            Divider(height: 1, color: colors.border),
        itemBuilder: (context, index) => _buildTopicItem(_topics[index]),
      ),
    );
  }

  Widget _buildTopicItem(TopicListItem topic) {
    final colors = context.shuyoColors;
    final selected = _selectedTopicIds.contains(topic.id);
    final tile = ListTile(
      selected: selected,
      leading: _topicLeading(topic, selected),
      title: Text(
        topic.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ShuYoTextStyles.title(
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
      onLongPress: () => _toggleTopicSelection(topic),
      onTap: () {
        if (_selectedTopicIds.isNotEmpty) {
          _toggleTopicSelection(topic);
          return;
        }
        Navigator.of(context).push<void>(
          shuyoRoute(
            builder: (context) => _MessageDetailPage(
              repository: widget.repository,
              onRecoverConnection: widget.onRecoverConnection,
              topic: topic,
              counterpartTitle: widget.group.displayName,
              counterpartUsername: widget.group.singleUsername,
            ),
          ),
        );
      },
    );
    if (_selectedTopicIds.isNotEmpty) {
      return tile;
    }
    return Dismissible(
      key: ValueKey('message-topic-${topic.id}'),
      direction: DismissDirection.endToStart,
      background: _ArchiveDismissBackground(archived: widget.archived),
      onDismissed: (_) => unawaited(
        _applyArchive({topic.id}),
      ),
      child: tile,
    );
  }

  Widget _topicLeading(TopicListItem topic, bool selected) {
    if (_selectedTopicIds.isEmpty) {
      return const Icon(Icons.chat_bubble_outline);
    }
    return Checkbox(
      value: selected,
      onChanged: (_) => _toggleTopicSelection(topic),
    );
  }

  void _toggleTopicSelection(TopicListItem topic) {
    setState(() {
      if (!_selectedTopicIds.add(topic.id)) {
        _selectedTopicIds.remove(topic.id);
      }
    });
  }

  Future<void> _applyArchiveSelection() async {
    await _applyArchive(_selectedTopicIds);
  }

  Future<void> _applyArchive(Iterable<int> topicIds) async {
    final ids = topicIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    await widget.onSetTopicsArchived(ids, archived: !widget.archived);
    if (!mounted) {
      return;
    }
    setState(() {
      _topics = _topics.where((item) => !ids.contains(item.id)).toList();
      _selectedTopicIds.removeAll(ids);
    });
    if (_topics.isEmpty) {
      Navigator.of(context).pop(true);
    }
  }
}

String _friendlyForumError(Object error) {
  if (error is ForumApiException) {
    return error.message;
  }
  return '操作失败，请稍后重试';
}

String _refreshFailureMessage(Object error, {required String prefix}) {
  if (error is ForumAuthException) {
    return '登录状态已失效，请尝试重新登录';
  }
  final message = _friendlyForumError(error);
  if (message == forumRefreshTooFastMessage) {
    return message;
  }
  return '$prefix：$message';
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

bool _isForumTransportError(Object error) {
  return error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException ||
      error is HttpException;
}

class _MessageDetailPage extends StatefulWidget {
  const _MessageDetailPage({
    required this.repository,
    this.onRecoverConnection,
    required this.topic,
    required this.counterpartTitle,
    this.counterpartUsername,
  });

  final ForumRepository repository;
  final Future<ForumRecoveryResult> Function()? onRecoverConnection;
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
    _ensureAutoRefreshTimer();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
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
      return EmptyState(
        icon: Icons.forum_outlined,
        title: widget.repository.isCacheOnly ? '无法连接论坛' : '暂无内容',
        message: widget.repository.isCacheOnly ? '请尝试重新登录。' : '这个私信会话没有返回消息',
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
    if (!widget.repository.isOnline) {
      _showSnack('无法连接论坛，请尝试重新登录。');
      return false;
    }
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
    var repository = widget.repository;
    if (!repository.isOnline) {
      final recovery = await widget.onRecoverConnection?.call() ??
          ForumRecoveryResult(
            status: ForumRecoveryStatus.unavailable,
            repository: repository,
          );
      if (!recovery.isRestored || !recovery.repository.isOnline) {
        _showSnack(_forumRecoveryMessage(recovery));
        return;
      }
      repository = recovery.repository;
      _ensureAutoRefreshTimer();
    }
    final startedAt = DateTime.now();
    final previousIds = _detail?.posts.map((post) => post.id).toSet() ?? {};
    setState(() => _refreshing = true);
    try {
      final fetched = await _fetchLatestDetail(repository);
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
      if (error is ForumAuthException) {
        repository.markAuthenticationRequired();
      } else if (_isForumTransportError(error)) {
        repository.markConnectionUnavailable();
      }
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
    if (!widget.repository.isOnline) {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
      return;
    }
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

  void _ensureAutoRefreshTimer() {
    if (_autoRefreshTimer != null || !widget.repository.isOnline) {
      return;
    }
    _autoRefreshTimer = Timer.periodic(
      _autoRefreshInterval,
      (_) => unawaited(_refreshDetailSilently()),
    );
  }

  Future<TopicDetail?> _fetchLatestDetail([ForumRepository? repository]) {
    return (repository ?? widget.repository).fetchTopicDetail(
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
      shuyoRoute(
        fullscreenDialog: true,
        builder: (context) => FullscreenImagePage(
          urls: urls,
          initialIndex: initialIndex,
          privateImage: true,
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
      shuyoRoute(
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
      shuyoRoute(
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
      shuyoRoute(
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
    final colors = context.shuyoColors;
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
                      style: ShuYoTextStyles.title(
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
    final colors = context.shuyoColors;
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
                _MessageCookedContent(
                  post: post,
                  textColor: primaryText,
                  onOpenImage: onOpenImage,
                  onOpenUser: onOpenUser,
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

class _MessageCookedContent extends StatelessWidget {
  const _MessageCookedContent({
    required this.post,
    required this.textColor,
    required this.onOpenImage,
    required this.onOpenUser,
    required this.onOpenInternalTopic,
  });

  final Post post;
  final Color textColor;
  final void Function(List<String> urls, int initialIndex) onOpenImage;
  final ValueChanged<String> onOpenUser;
  final ValueChanged<CookedLinkPreview> onOpenInternalTopic;

  @override
  Widget build(BuildContext context) {
    if (HtmlText.prefersPlainPrivateMessageText(post.cooked)) {
      final text = HtmlText.toPlainText(post.cooked).trim();
      if (text.isNotEmpty) {
        return Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            height: 1.46,
          ),
        );
      }
    }
    return ForumCookedContent(
      cooked: post.cooked,
      textColor: textColor,
      textSize: 15,
      textBottomSpacing: 6,
      imageBottomSpacing: 8,
      imageErrorHeight: 130,
      imageFit: BoxFit.contain,
      compactCards: true,
      privateImage: true,
      onOpenUser: onOpenUser,
      onOpenImage: onOpenImage,
      onOpenInternalTopic: onOpenInternalTopic,
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
    final colors = context.shuyoColors;

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
            color: context.shuyoColors.textSecondary,
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

class _MessageTopicVersion {
  const _MessageTopicVersion({
    required this.postsCount,
    required this.highestPostNumber,
    required this.lastPostedAt,
  });

  final int postsCount;
  final int highestPostNumber;
  final DateTime? lastPostedAt;

  factory _MessageTopicVersion.fromTopic(TopicListItem topic) {
    return _MessageTopicVersion(
      postsCount: topic.postsCount,
      highestPostNumber: topic.highestPostNumber,
      lastPostedAt: topic.lastPostedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _MessageTopicVersion &&
        other.postsCount == postsCount &&
        other.highestPostNumber == highestPostNumber &&
        other.lastPostedAt == lastPostedAt;
  }

  @override
  int get hashCode => Object.hash(
        postsCount,
        highestPostNumber,
        lastPostedAt,
      );
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

  List<int> get topicIds => topics.map((topic) => topic.id).toList();
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

class _ArchiveDismissBackground extends StatelessWidget {
  const _ArchiveDismissBackground({required this.archived});

  final bool archived;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Container(
      color: colors.accent,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      child: Icon(
        archived ? Icons.unarchive_outlined : Icons.archive_outlined,
        color: colors.onAccent,
      ),
    );
  }
}

class _MessageRowSizeReporter extends SingleChildRenderObjectWidget {
  const _MessageRowSizeReporter({
    required super.child,
    required this.onSizeChanged,
  });

  final ValueChanged<Size>? onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _MessageRowSizeRenderObject(onSizeChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MessageRowSizeRenderObject renderObject,
  ) {
    renderObject.onSizeChanged = onSizeChanged;
  }
}

class _MessageRowSizeRenderObject extends RenderProxyBox {
  _MessageRowSizeRenderObject(this.onSizeChanged);

  ValueChanged<Size>? onSizeChanged;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    final nextSize = size;
    if (nextSize == _lastSize || onSizeChanged == null) {
      return;
    }
    _lastSize = nextSize;
    final callback = onSizeChanged;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) {
        callback?.call(nextSize);
      }
    });
  }
}

class _ArchivePullToSwitch extends StatefulWidget {
  const _ArchivePullToSwitch({
    required this.child,
    required this.showArchived,
    required this.threshold,
    required this.onSwitch,
  });

  final Widget child;
  final bool showArchived;
  final double threshold;
  final ValueChanged<bool> onSwitch;

  @override
  State<_ArchivePullToSwitch> createState() => _ArchivePullToSwitchState();
}

class _ArchivePullToSwitchState extends State<_ArchivePullToSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settleController;
  double _pullDistance = 0;
  double _nativeOverscroll = 0;
  double _settlePullDistance = 0;
  double _settleNativeOverscroll = 0;
  bool _tracking = false;
  bool _switched = false;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(_handleSettleAnimationTick);
  }

  @override
  void didUpdateWidget(covariant _ArchivePullToSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showArchived != widget.showArchived ||
        oldWidget.threshold != widget.threshold) {
      if (!_switched) {
        _resetPullState();
      }
    }
  }

  @override
  void dispose() {
    _settleController
      ..removeListener(_handleSettleAnimationTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final settleFactor = 1 - _settleController.value;
    final displayedPullDistance = _settleController.isAnimating
        ? _settlePullDistance * settleFactor
        : _pullDistance;
    final displayedNativeOverscroll = _settleController.isAnimating
        ? _settleNativeOverscroll * settleFactor
        : _nativeOverscroll;
    final childOffset = displayedPullDistance > displayedNativeOverscroll
        ? displayedPullDistance - displayedNativeOverscroll
        : 0.0;
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ClipRect(
        child: Stack(
          children: [
            if (displayedPullDistance > 0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: displayedPullDistance,
                child: ColoredBox(
                  color: colors.accent,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 24),
                      child: Icon(
                        widget.showArchived
                            ? Icons.unarchive_outlined
                            : Icons.archive_outlined,
                        color: colors.onAccent,
                      ),
                    ),
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(0, childOffset),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final metrics = notification.metrics;
    if (notification is ScrollStartNotification) {
      _settleController.stop();
      _tracking = metrics.pixels <= metrics.minScrollExtent + 0.5;
      _switched = false;
      _resetPullState();
      return false;
    }
    if (!_tracking) {
      return false;
    }
    final nativeOverscroll = _nativeOverscrollFor(metrics);
    if (notification is OverscrollNotification) {
      if (nativeOverscroll > 0) {
        _updatePullDistance(nativeOverscroll, nativeOverscroll);
      } else if (notification.overscroll < 0) {
        _updatePullDistance(_pullDistance - notification.overscroll, 0);
      } else if (notification.overscroll > 0) {
        _updatePullDistance(_pullDistance - notification.overscroll, 0);
      }
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      if (nativeOverscroll > 0) {
        _updatePullDistance(nativeOverscroll, nativeOverscroll);
      } else {
        final delta = notification.scrollDelta ?? 0;
        if (delta < 0) {
          _updatePullDistance(_pullDistance - delta, 0);
        } else if (delta > 0 && _pullDistance > 0) {
          _updatePullDistance(_pullDistance - delta, 0);
        }
      }
      if (metrics.pixels > metrics.minScrollExtent + 1 && _pullDistance <= 0) {
        _tracking = false;
      }
      return false;
    }
    if (notification is ScrollEndNotification) {
      _tracking = false;
      if (!_switched && (_pullDistance != 0 || _nativeOverscroll != 0)) {
        setState(() {
          _pullDistance = 0;
          _nativeOverscroll = 0;
        });
      }
    }
    return false;
  }

  double _nativeOverscrollFor(ScrollMetrics metrics) {
    final distance = metrics.minScrollExtent - metrics.pixels;
    return distance > 0 ? distance : 0;
  }

  void _updatePullDistance(
    double distance,
    double nativeOverscroll,
  ) {
    if (!mounted || _switched) {
      return;
    }
    final next = distance.clamp(0.0, widget.threshold).toDouble();
    final reachedThreshold = next >= widget.threshold;
    if (next == _pullDistance && nativeOverscroll == _nativeOverscroll) {
      return;
    }
    if (reachedThreshold) {
      _switched = true;
      _tracking = false;
      final settlePullDistance = next;
      final settleNativeOverscroll = nativeOverscroll;
      widget.onSwitch(!widget.showArchived);
      _startSettleAnimation(
        settlePullDistance,
        settleNativeOverscroll,
      );
      return;
    }
    setState(() {
      _pullDistance = next;
      _nativeOverscroll = nativeOverscroll;
    });
  }

  void _startSettleAnimation(
    double pullDistance,
    double nativeOverscroll,
  ) {
    _settlePullDistance = pullDistance;
    _settleNativeOverscroll = nativeOverscroll;
    _settleController
      ..stop()
      ..value = 0;
    unawaited(_settleController.forward());
  }

  void _handleSettleAnimationTick() {
    if (!mounted) {
      return;
    }
    if (_settleController.isCompleted) {
      _pullDistance = 0;
      _nativeOverscroll = 0;
      _settlePullDistance = 0;
      _settleNativeOverscroll = 0;
    }
    setState(() {});
  }

  void _resetPullState() {
    _settleController.stop();
    if (_pullDistance == 0 && _nativeOverscroll == 0) {
      return;
    }
    setState(() {
      _pullDistance = 0;
      _nativeOverscroll = 0;
      _settlePullDistance = 0;
      _settleNativeOverscroll = 0;
    });
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
