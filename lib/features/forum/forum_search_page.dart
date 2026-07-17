import 'package:flutter/material.dart';

import '../../data/models/forum_search.dart';
import '../../data/models/topic.dart';
import '../../data/repositories/forum_repository.dart';
import '../../features/profile/user_profile_page.dart';
import '../../features/topic/topic_detail_page.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/empty_state.dart';

class ForumSearchPage extends StatefulWidget {
  const ForumSearchPage({
    super.key,
    required this.repository,
    required this.onLoginRequired,
    this.onSessionExpired,
    this.onBookmarkChanged,
  });

  final ForumRepository repository;
  final Future<void> Function() onLoginRequired;
  final Future<void> Function()? onSessionExpired;
  final VoidCallback? onBookmarkChanged;

  @override
  State<ForumSearchPage> createState() => _ForumSearchPageState();
}

class _ForumSearchPageState extends State<ForumSearchPage> {
  final _controller = TextEditingController();
  ForumSearchMode _mode = ForumSearchMode.posts;
  ForumSearchSort _sort = ForumSearchSort.relevance;
  Future<ForumSearchResult>? _future;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索乐乎',
            border: InputBorder.none,
          ),
          onSubmitted: _search,
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: () => _search(_controller.text),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: Column(
        children: [
          _SearchOptions(
            mode: _mode,
            sort: _sort,
            onModeChanged: (mode) {
              setState(() => _mode = mode);
              _repeatSearch();
            },
            onSortChanged: (sort) {
              setState(() => _sort = sort);
              _repeatSearch();
            },
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final future = _future;
    if (future == null) {
      return EmptyState(
        icon: Icons.search,
        title: '搜索乐乎',
        message: _mode == ForumSearchMode.users ? '输入用户名关键词' : '输入关键词后查看帖子和回复',
      );
    }
    return FutureBuilder<ForumSearchResult>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            title: '搜索失败',
            message: snapshot.error.toString(),
          );
        }
        final result = snapshot.data;
        if (result == null || _isEmpty(result)) {
          return const EmptyState(
            icon: Icons.search_off,
            title: '没有结果',
            message: '换个关键词试试',
          );
        }
        return _mode == ForumSearchMode.users
            ? _UserResults(
                result: result,
                onOpenUser: _openUser,
              )
            : _PostResults(
                result: result,
                onOpenTopic: _openTopic,
              );
      },
    );
  }

  bool _isEmpty(ForumSearchResult result) {
    return _mode == ForumSearchMode.users
        ? result.users.isEmpty
        : result.posts.isEmpty && result.topics.isEmpty;
  }

  void _search(String raw) {
    final query = raw.trim();
    if (query.isEmpty) {
      return;
    }
    setState(() {
      _future = widget.repository.searchForum(
        query,
        mode: _mode,
        sort: _sort,
      );
    });
  }

  void _repeatSearch() {
    final query = _controller.text.trim();
    if (query.isNotEmpty) {
      _search(query);
    }
  }

  Future<void> _openTopic(TopicListItem topic) async {
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => TopicDetailPage(
          repository: widget.repository,
          topic: topic,
          onLoginRequired: widget.onLoginRequired,
          onSessionExpired: widget.onSessionExpired,
          onBookmarkChanged: widget.onBookmarkChanged,
        ),
      ),
    );
  }

  Future<void> _openUser(String username) async {
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => UserProfilePage(
          repository: widget.repository,
          username: username,
        ),
      ),
    );
  }
}

class _SearchOptions extends StatelessWidget {
  const _SearchOptions({
    required this.mode,
    required this.sort,
    required this.onModeChanged,
    required this.onSortChanged,
  });

  final ForumSearchMode mode;
  final ForumSearchSort sort;
  final ValueChanged<ForumSearchMode> onModeChanged;
  final ValueChanged<ForumSearchSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF202020))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _OptionChip(
                label: '话题/帖子',
                selected: mode == ForumSearchMode.posts,
                onTap: () => onModeChanged(ForumSearchMode.posts),
              ),
              const SizedBox(width: 8),
              _OptionChip(
                label: '用户',
                selected: mode == ForumSearchMode.users,
                onTap: () => onModeChanged(ForumSearchMode.users),
              ),
            ],
          ),
          if (mode == ForumSearchMode.posts) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final item in ForumSearchSort.values) ...[
                    _OptionChip(
                      label: item.label,
                      selected: sort == item,
                      onTap: () => onSortChanged(item),
                    ),
                    if (item != ForumSearchSort.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: selected ? null : onTap,
      child: Container(
        height: 32,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEDEDED) : const Color(0xFF171717),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFEDEDED) : const Color(0xFF303030),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : const Color(0xFFD6D6D6),
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _PostResults extends StatelessWidget {
  const _PostResults({
    required this.result,
    required this.onOpenTopic,
  });

  final ForumSearchResult result;
  final ValueChanged<TopicListItem> onOpenTopic;

  @override
  Widget build(BuildContext context) {
    final rows = <_PostResultRow>[
      for (final post in result.posts)
        _PostResultRow(
          topic: result.topicForPost(post) ??
              _topicFromPost(post, '主题 #${post.topicId}'),
          post: post,
        ),
      if (result.posts.isEmpty)
        for (final topic in result.topics) _PostResultRow(topic: topic),
    ];
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: rows.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: Color(0xFF202020)),
      itemBuilder: (context, index) {
        final row = rows[index];
        final post = row.post;
        return _SearchRow(
          title: row.topic.title,
          subtitle: post?.blurb ?? '主题',
          meta: TimeFormat.compact(
            post?.createdAt ?? row.topic.lastPostedAt ?? row.topic.createdAt,
          ),
          onTap: () => onOpenTopic(row.topic),
        );
      },
    );
  }

  TopicListItem _topicFromPost(SearchPostResult post, String title) {
    return TopicListItem(
      id: post.topicId,
      title: title,
      postsCount: 0,
      replyCount: 0,
      highestPostNumber: post.postNumber,
      views: 0,
      likeCount: post.likeCount,
      categoryId: 0,
      posters: const [],
      createdAt: post.createdAt,
      lastPostedAt: post.createdAt,
    );
  }
}

class _PostResultRow {
  const _PostResultRow({required this.topic, this.post});

  final TopicListItem topic;
  final SearchPostResult? post;
}

class _UserResults extends StatelessWidget {
  const _UserResults({
    required this.result,
    required this.onOpenUser,
  });

  final ForumSearchResult result;
  final ValueChanged<String> onOpenUser;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: result.users.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: Color(0xFF202020)),
      itemBuilder: (context, index) {
        final user = result.users[index];
        return ListTile(
          leading: ForumAvatar(url: user.avatarUrl(size: 96), size: 38),
          title: Text(
            user.username,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text('ID ${user.id}'),
          onTap: () => onOpenUser(user.username),
        );
      },
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: LehuTextStyles.title(
          size: 15.5,
          weight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          height: 1.46,
        ),
      ),
      trailing: meta.isEmpty
          ? null
          : Text(
              meta,
              style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 12.5),
            ),
    );
  }
}
