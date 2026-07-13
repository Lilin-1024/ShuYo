import 'package:flutter/material.dart';

import '../../data/models/forum_search.dart';
import '../../data/models/topic.dart';
import '../../data/repositories/forum_repository.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/empty_state.dart';

class ForumSearchPage extends StatefulWidget {
  const ForumSearchPage({
    super.key,
    required this.repository,
  });

  final ForumRepository repository;

  @override
  State<ForumSearchPage> createState() => _ForumSearchPageState();
}

class _ForumSearchPageState extends State<ForumSearchPage> {
  final _controller = TextEditingController();
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
      body: _body(),
    );
  }

  Widget _body() {
    final future = _future;
    if (future == null) {
      return const EmptyState(
        icon: Icons.search,
        title: '搜索乐乎',
        message: '输入关键词后查看帖子和回复',
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
        if (result == null || (result.posts.isEmpty && result.topics.isEmpty)) {
          return const EmptyState(
            icon: Icons.search_off,
            title: '没有结果',
            message: '换个关键词试试',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: result.posts.length + result.topics.length,
          separatorBuilder: (context, index) =>
              const Divider(height: 1, color: Color(0xFF202020)),
          itemBuilder: (context, index) {
            if (index < result.posts.length) {
              final post = result.posts[index];
              final topic = result.topicForPost(post) ??
                  _topicFromPost(post, '主题 #${post.topicId}');
              return _SearchRow(
                title: topic.title,
                subtitle: post.blurb,
                meta: TimeFormat.compact(post.createdAt),
                onTap: () => Navigator.of(context).pop(topic),
              );
            }
            final topic = result.topics[index - result.posts.length];
            return _SearchRow(
              title: topic.title,
              subtitle: '主题',
              meta: TimeFormat.compact(topic.lastPostedAt ?? topic.createdAt),
              onTap: () => Navigator.of(context).pop(topic),
            );
          },
        );
      },
    );
  }

  void _search(String raw) {
    final query = raw.trim();
    if (query.isEmpty) {
      return;
    }
    setState(() {
      _future = widget.repository.searchForum(query);
    });
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
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: meta.isEmpty
          ? null
          : Text(
              meta,
              style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 12),
            ),
    );
  }
}
