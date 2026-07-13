import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/post.dart';
import '../data/models/topic.dart';
import '../data/models/topic_detail.dart';
import '../data/repositories/forum_repository.dart';
import '../data/services/discourse_api_client.dart';
import '../data/services/payload_factory.dart';
import '../features/auth/login_webview_page.dart';
import '../features/home/topic_list_page.dart';
import '../features/messages/messages_page.dart';
import '../features/profile/profile_page.dart';
import '../features/topic/topic_page.dart';
import '../features/webview/forum_webview_page.dart';
import '../shared/widgets/app_header.dart';
import '../shared/widgets/empty_state.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    required this.reloadRepository,
  });

  final ForumRepository repository;
  final Future<ForumRepository> Function() reloadRepository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tabIndex = 0;
  TopicListItem? _openedTopic;
  bool _reloadingSession = false;
  bool _loadingMoreLatest = false;
  bool _loadingMoreHot = false;
  bool _submittingReply = false;
  final _likingPostIds = <int>{};
  final _deletingPostIds = <int>{};
  late ForumRepository _repo;
  late Future<List<TopicListItem>> _latestFuture;
  late Future<List<TopicListItem>> _hotFuture;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository;
    _resetListFutures();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _repo.profile;
    final isProfileTab = _tabIndex == 3 && _openedTopic == null;

    return PopScope(
      canPop: _openedTopic == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _openedTopic != null) {
          setState(() => _openedTopic = null);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AppHeader(
                title: _headerTitle,
                showBack: _openedTopic != null,
                showSettings: isProfileTab,
                showMore: _openedTopic != null,
                notificationCount: _repo.unreadNotificationCount,
                onBack: () => setState(() => _openedTopic = null),
                onMore: _openedTopic == null
                    ? null
                    : () => _showTopicMoreSheet(_openedTopic!),
                onSettings: () => _repo.isOnline
                    ? _openForumWebView(
                        title: '设置',
                        url:
                            'https://bbs.shu.edu.cn/u/${profile.username.toLowerCase()}/preferences/account',
                      )
                    : _login(),
                onNotification: () => _repo.isOnline
                    ? _openForumWebView(
                        title: '通知',
                        url:
                            'https://bbs.shu.edu.cn/u/${profile.username.toLowerCase()}/notifications',
                      )
                    : _login(),
              ),
              Expanded(child: _bodyForTab()),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _tabIndex,
          onTap: (index) {
            setState(() {
              _tabIndex = index;
              _openedTopic = null;
            });
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.schedule), label: '最新'),
            BottomNavigationBarItem(
                icon: Icon(Icons.local_fire_department), label: '热点'),
            BottomNavigationBarItem(
                icon: Icon(Icons.forum_outlined), label: '消息'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_outline), label: '我'),
          ],
        ),
      ),
    );
  }

  String get _headerTitle {
    if (_openedTopic != null) {
      return '帖子';
    }
    return switch (_tabIndex) {
      0 => '最新',
      1 => '热点',
      2 => '消息',
      3 => '我',
      _ => '乐乎',
    };
  }

  Widget _bodyForTab() {
    final openedTopic = _openedTopic;
    if (openedTopic != null) {
      return FutureBuilder<TopicDetail?>(
        future: _repo.fetchTopicDetail(openedTopic.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _LoadingState(message: '正在加载帖子...');
          }
          if (snapshot.hasError) {
            return _ErrorState(
              title: '帖子加载失败',
              message: snapshot.error.toString(),
              onRetry: () => setState(() {
                _repo.fetchTopicDetail(openedTopic.id, forceRefresh: true);
              }),
            );
          }
          return TopicPage(
            item: openedTopic,
            detail: snapshot.data,
            category: _repo.categoryById(openedTopic.categoryId),
            isOnline: _repo.isOnline,
            isSubmittingReply: _submittingReply,
            busyLikePostIds: _likingPostIds,
            busyDeletePostIds: _deletingPostIds,
            onLikePost: _likePost,
            onDeletePost: _deletePost,
            onCreateReply: _createReply,
            onLoginRequired: _login,
          );
        },
      );
    }

    return switch (_tabIndex) {
      0 => _topicList(
          future: _latestFuture,
          refresh: _refreshLatest,
          canLoadMore: _repo.canLoadMoreLatest,
          isLoadingMore: _loadingMoreLatest,
          loadMore: _loadMoreLatest,
        ),
      1 => _topicList(
          future: _hotFuture,
          refresh: _refreshHot,
          canLoadMore: _repo.canLoadMoreHot,
          isLoadingMore: _loadingMoreHot,
          loadMore: _loadMoreHot,
        ),
      2 => const MessagesPage(),
      3 => ProfilePage(
          profile: _repo.profile,
          summary: _repo.userSummary,
          isOnline: _repo.isOnline,
          isBusy: _reloadingSession,
          onLogin: _login,
          onRelogin: _relogin,
          onLogout: _logout,
        ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _topicList(
      {required Future<List<TopicListItem>> future,
      required Future<void> Function() refresh,
      required bool canLoadMore,
      required bool isLoadingMore,
      required Future<void> Function() loadMore}) {
    return FutureBuilder<List<TopicListItem>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingState(message: '正在加载列表...');
        }
        if (snapshot.hasError) {
          return _ErrorState(
            title: '列表加载失败',
            message: snapshot.error.toString(),
            onRetry: () => refresh(),
          );
        }
        final topics = snapshot.data ?? const <TopicListItem>[];
        if (topics.isEmpty) {
          return EmptyState(
            icon: Icons.inbox_outlined,
            title: '暂无内容',
            message: _repo.isOnline ? '论坛暂时没有返回主题。' : '本地样例中没有主题数据。',
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: TopicListPage(
            topics: topics,
            users: _repo.users,
            previewForTopic: _repo.fetchTopicPreview,
            categoryById: _repo.categoryById,
            onOpenTopic: (topic) => setState(() => _openedTopic = topic),
            canLoadMore: canLoadMore,
            isLoadingMore: isLoadingMore,
            onLoadMore: loadMore,
          ),
        );
      },
    );
  }

  void _resetListFutures() {
    _latestFuture = _repo.fetchLatestTopics();
    _hotFuture = _repo.fetchHotTopics();
    _loadingMoreLatest = false;
    _loadingMoreHot = false;
  }

  Future<void> _refreshLatest() async {
    final future = _repo.fetchLatestTopics(forceRefresh: true);
    setState(() => _latestFuture = future);
    try {
      await future;
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _refreshHot() async {
    final future = _repo.fetchHotTopics(forceRefresh: true);
    setState(() => _hotFuture = future);
    try {
      await future;
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadMoreLatest() async {
    if (_loadingMoreLatest || !_repo.canLoadMoreLatest) {
      return;
    }
    setState(() => _loadingMoreLatest = true);
    try {
      final topics = await _repo.loadMoreLatestTopics();
      if (!mounted) {
        return;
      }
      setState(() => _latestFuture = Future.value(topics));
    } on Object catch (error) {
      await _handleOperationError(error, title: '加载更多失败');
    } finally {
      if (mounted) {
        setState(() => _loadingMoreLatest = false);
      }
    }
  }

  Future<void> _loadMoreHot() async {
    if (_loadingMoreHot || !_repo.canLoadMoreHot) {
      return;
    }
    setState(() => _loadingMoreHot = true);
    try {
      final topics = await _repo.loadMoreHotTopics();
      if (!mounted) {
        return;
      }
      setState(() => _hotFuture = Future.value(topics));
    } on Object catch (error) {
      await _handleOperationError(error, title: '加载更多失败');
    } finally {
      if (mounted) {
        setState(() => _loadingMoreHot = false);
      }
    }
  }

  Future<void> _login() async {
    if (_reloadingSession) {
      return;
    }
    final logged = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => const LoginWebViewPage()),
    );
    if (logged != true || !mounted) {
      return;
    }
    setState(() => _reloadingSession = true);
    try {
      final nextRepository = await widget.reloadRepository();
      if (!mounted) {
        return;
      }
      setState(() {
        _repo = nextRepository;
        _openedTopic = null;
        _reloadingSession = false;
        _resetListFutures();
      });
      _showSnack('已接入真实乐乎数据');
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _reloadingSession = false);
      await _showErrorDialog(
        title: '登录态检测失败',
        message: _loginError(error),
      );
    }
  }

  Future<void> _relogin() async {
    if (_reloadingSession) {
      return;
    }
    setState(() => _reloadingSession = true);
    try {
      await _repo.clearLoginCookies();
      final nextRepository = await ForumRepositoryFactory.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _repo = nextRepository;
        _openedTopic = null;
        _reloadingSession = false;
        _resetListFutures();
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _reloadingSession = false);
      await _showErrorDialog(
        title: '重新登录失败',
        message: _friendlyError(error),
      );
      return;
    }
    await _login();
  }

  Future<void> _logout() async {
    if (_reloadingSession) {
      return;
    }
    setState(() => _reloadingSession = true);
    try {
      await _repo.clearLoginCookies();
      final nextRepository = await ForumRepositoryFactory.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _repo = nextRepository;
        _openedTopic = null;
        _reloadingSession = false;
        _resetListFutures();
      });
      _showSnack('已退出登录');
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _reloadingSession = false);
      await _showErrorDialog(
        title: '退出登录失败',
        message: _friendlyError(error),
      );
    }
  }

  Future<void> _createReply(ReplyDraft draft) async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    if (_submittingReply) {
      return;
    }
    setState(() => _submittingReply = true);
    try {
      await _repo.createReply(draft);
      if (!mounted) {
        return;
      }
      _showSnack('评论已发布');
      await _refreshTopic(draft.topicId);
    } on Object catch (error) {
      await _handleOperationError(error, title: '评论失败');
    } finally {
      if (mounted) {
        setState(() => _submittingReply = false);
      }
    }
  }

  Future<void> _likePost(int postId) async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    if (_likingPostIds.contains(postId)) {
      return;
    }
    setState(() => _likingPostIds.add(postId));
    try {
      final post = await _repo.likePost(postId);
      if (!mounted) {
        return;
      }
      _showSnack('已点赞');
      await _refreshTopic(post.topicId);
    } on Object catch (error) {
      await _handleOperationError(error, title: '点赞失败');
    } finally {
      if (mounted) {
        setState(() => _likingPostIds.remove(postId));
      }
    }
  }

  Future<void> _deletePost(Post post) async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    if (_deletingPostIds.contains(post.id)) {
      return;
    }
    setState(() => _deletingPostIds.add(post.id));
    try {
      await _repo.deletePost(post);
      if (!mounted) {
        return;
      }
      _showSnack('回复已删除');
      await _refreshTopic(post.topicId);
    } on Object catch (error) {
      await _handleOperationError(error, title: '删除失败');
    } finally {
      if (mounted) {
        setState(() => _deletingPostIds.remove(post.id));
      }
    }
  }

  Future<void> _shareTopic(TopicListItem topic) async {
    final url = 'https://bbs.shu.edu.cn/t/topic/${topic.id}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) {
      return;
    }
    _showSnack('帖子链接已复制');
  }

  void _showTopicMoreSheet(TopicListItem topic) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        return _TopicMoreSheet(
          onClose: () => Navigator.of(context).pop(),
          onShare: () {
            Navigator.of(context).pop();
            _shareTopic(topic);
          },
          onReport: () {
            Navigator.of(context).pop();
            _showSnack('举报功能后续接入');
          },
          onBookmark: () {
            Navigator.of(context).pop();
            _showSnack('收藏功能后续接入');
          },
        );
      },
    );
  }

  Future<void> _refreshTopic(int topicId) async {
    await _repo.fetchTopicDetail(topicId, forceRefresh: true);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleOperationError(
    Object error, {
    required String title,
  }) async {
    if (error is ForumAuthException) {
      await _clearExpiredLogin();
      await _showErrorDialog(
        title: '登录已失效',
        message: '论坛没有接受当前登录态，请重新登录后再操作。',
      );
      return;
    }
    await _showErrorDialog(title: title, message: _friendlyError(error));
  }

  Future<void> _clearExpiredLogin() async {
    try {
      await _repo.clearLoginCookies();
    } on Object {
      // Cookie 清理失败不应阻断 UI 回到可用状态。
    }
    final nextRepository = await ForumRepositoryFactory.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _repo = nextRepository;
      _openedTopic = null;
      _resetListFutures();
    });
  }

  void _openForumWebView({required String title, required String url}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => ForumWebViewPage(title: title, url: url),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showErrorDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  String _friendlyError(Object error) {
    if (error is ForumApiException) {
      return error.message;
    }
    return '操作失败，请稍后重试';
  }

  String _loginError(Object error) {
    if (error is ForumAuthException) {
      return '还没有检测到登录态。请确认已在 WebView 中登录成功，再点“完成”。';
    }
    if (error is ForumApiException) {
      return error.message;
    }
    return '登录态检测失败，请确认模拟器能访问校园网或 VPN。';
  }
}

class _TopicMoreSheet extends StatelessWidget {
  const _TopicMoreSheet({
    required this.onClose,
    required this.onShare,
    required this.onReport,
    required this.onBookmark,
  });

  final VoidCallback onClose;
  final VoidCallback onShare;
  final VoidCallback onReport;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '更多',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TopicActionButton(
                    icon: Icons.ios_share,
                    label: '分享',
                    onTap: onShare,
                  ),
                ),
                Expanded(
                  child: _TopicActionButton(
                    icon: Icons.flag_outlined,
                    label: '举报',
                    onTap: onReport,
                  ),
                ),
                Expanded(
                  child: _TopicActionButton(
                    icon: Icons.bookmark_border,
                    label: '收藏',
                    onTap: onBookmark,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicActionButton extends StatelessWidget {
  const _TopicActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: SizedBox(
        height: 88,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(message, style: const TextStyle(color: Color(0xFFBDBDBD))),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: title,
      message: message,
      action: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重试'),
      ),
    );
  }
}
