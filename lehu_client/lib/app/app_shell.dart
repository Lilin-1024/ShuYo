import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/post.dart';
import '../data/models/topic.dart';
import '../data/models/topic_detail.dart';
import '../data/repositories/academic_schedule_repository.dart';
import '../data/repositories/announcement_repository.dart';
import '../data/repositories/classroom_repository.dart';
import '../data/repositories/course_rating_repository.dart';
import '../data/repositories/forum_repository.dart';
import '../data/services/academic_schedule_notification_service.dart';
import '../data/services/discourse_api_client.dart';
import '../data/services/payload_factory.dart';
import '../features/auth/login_webview_page.dart';
import '../features/forum/create_topic_page.dart';
import '../features/forum/forum_filter_bar.dart';
import '../features/forum/forum_search_page.dart';
import '../features/home/academic_schedule_page.dart';
import '../features/home/announcements_page.dart';
import '../features/home/course_rating_page.dart';
import '../features/home/empty_classroom_page.dart';
import '../features/home/home_dashboard_page.dart';
import '../features/home/topic_list_page.dart';
import '../features/messages/messages_page.dart';
import '../features/messages/notifications_page.dart';
import '../features/profile/profile_page.dart';
import '../features/profile/profile_settings_page.dart';
import '../features/profile/user_profile_page.dart';
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
  TopicFeedQuery _feedQuery = const TopicFeedQuery();
  bool _reloadingSession = false;
  bool _loadingMoreFeed = false;
  bool _submittingReply = false;
  final _likingPostIds = <int>{};
  final _deletingPostIds = <int>{};
  late ForumRepository _repo;
  late final AcademicScheduleRepository _scheduleRepository;
  late final AcademicScheduleNotificationService _scheduleNotificationService;
  late final AnnouncementRepository _announcementRepository;
  late final ClassroomRepository _classroomRepository;
  late final CourseRatingRepository _courseRatingRepository;
  late Future<List<TopicListItem>> _feedFuture;
  Timer? _scheduleSummaryTimer;
  Timer? _announcementSummaryTimer;
  bool _loadingScheduleSummary = false;
  bool _loadingAnnouncementSummary = false;
  String _scheduleSummaryText = '正在读取课表...';
  String _announcementSummaryText = '正在读取通知公告...';

  @override
  void initState() {
    super.initState();
    _repo = widget.repository;
    _scheduleRepository = AcademicScheduleRepository();
    _scheduleNotificationService = AcademicScheduleNotificationService(
      repository: _scheduleRepository,
    );
    _announcementRepository = AnnouncementRepository();
    _classroomRepository = ClassroomRepository();
    _courseRatingRepository = CourseRatingRepository();
    _resetFeedFuture();
    unawaited(_refreshScheduleSummaryQuietly());
    unawaited(_loadAnnouncementSummaryFromCache());
    unawaited(_refreshAnnouncementSummaryQuietly());
    _scheduleSummaryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshScheduleSummaryQuietly(),
    );
    _announcementSummaryTimer = Timer.periodic(
      AnnouncementRepository.defaultAutoRefreshInterval,
      (_) => _refreshAnnouncementSummaryQuietly(),
    );
    unawaited(_scheduleNotificationService.syncScheduleReminders());
  }

  @override
  Widget build(BuildContext context) {
    final isProfileTab = _tabIndex == 3 && _openedTopic == null;
    final isForumTab = _tabIndex == 1 && _openedTopic == null && _repo.isOnline;

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
                showSettings: isProfileTab && _repo.isOnline,
                showMore: _openedTopic != null,
                showSearch: isForumTab,
                showCreate: isForumTab,
                notificationCount:
                    _repo.isOnline ? _repo.unreadNotificationCount : 0,
                onBack: () => setState(() => _openedTopic = null),
                onMore: _openedTopic == null
                    ? null
                    : () => _showTopicMoreSheet(_openedTopic!),
                onSearch: _openSearch,
                onCreate: _openCreateTopic,
                onSettings: () => _showSnack('客户端设置后续接入'),
                onNotification: _openNotifications,
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
            if (index == 0) {
              unawaited(_refreshScheduleSummaryQuietly());
              unawaited(_refreshAnnouncementSummaryQuietly());
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: '首页'),
            BottomNavigationBarItem(icon: Icon(Icons.forum), label: '论坛'),
            BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline), label: '消息'),
            BottomNavigationBarItem(
                icon: Icon(Icons.account_circle), label: '我'),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scheduleSummaryTimer?.cancel();
    _announcementSummaryTimer?.cancel();
    super.dispose();
  }

  String get _headerTitle {
    if (_openedTopic != null) {
      return '帖子';
    }
    return switch (_tabIndex) {
      0 => '首页',
      1 => '论坛',
      2 => '消息',
      3 => '我',
      _ => '乐乎',
    };
  }

  Widget _bodyForTab() {
    final openedTopic = _openedTopic;
    if (openedTopic != null) {
      return _openedTopicView(openedTopic);
    }

    return switch (_tabIndex) {
      0 => _homeBody(),
      1 => _repo.isOnline
          ? _forumBody()
          : _LoginRequiredTab(
              icon: Icons.forum,
              title: '登录后查看论坛',
              message: '论坛列表需要乐乎登录态',
              onTap: _openProfileLoginTab,
            ),
      2 => _repo.isOnline
          ? MessagesPage(
              repository: _repo,
              onLoginRequired: _openProfileLoginTab,
            )
          : _LoginRequiredTab(
              icon: Icons.chat_bubble,
              title: '登录后查看消息',
              message: '私信和通知需要乐乎登录态',
              onTap: _openProfileLoginTab,
            ),
      3 => ProfilePage(
          profile: _repo.profile,
          summary: _repo.userSummary,
          isOnline: _repo.isOnline,
          isBusy: _reloadingSession,
          onLogin: _login,
          onEditProfile: _openProfileSettings,
          onRelogin: _relogin,
          onLogout: _logout,
        ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _homeBody() {
    return HomeDashboardPage(
      profile: _repo.profile,
      isOnline: _repo.isOnline,
      isBusy: _reloadingSession,
      onLogin: _login,
      onRelogin: _relogin,
      onOpenAcademicSystem: () => unawaited(_openAcademicSystem()),
      onOpenAnnouncements: () => unawaited(_openAnnouncements()),
      onOpenEmptyClassroom: () => unawaited(_openEmptyClassroom()),
      onOpenCourseRatings: () => unawaited(_openCourseRatings()),
      todayCourseContent: _scheduleSummaryText,
      announcementContent: _announcementSummaryText,
      onPlaceholder: (name) => _showSnack('$name 后续接入'),
    );
  }

  Future<void> _refreshScheduleSummaryQuietly() async {
    if (_loadingScheduleSummary) {
      return;
    }
    _loadingScheduleSummary = true;
    try {
      final summary = await _scheduleRepository.homeSummary();
      if (!mounted || summary.text == _scheduleSummaryText) {
        return;
      }
      setState(() => _scheduleSummaryText = summary.text);
    } on Object {
      if (mounted && _scheduleSummaryText == '正在读取课表...') {
        setState(() => _scheduleSummaryText = '点击同步教务课表');
      }
    } finally {
      _loadingScheduleSummary = false;
    }
  }

  Future<void> _loadAnnouncementSummaryFromCache() async {
    try {
      final summary = await _announcementRepository.homeSummary();
      if (!mounted || summary.text == _announcementSummaryText) {
        return;
      }
      setState(() => _announcementSummaryText = summary.text);
    } on Object {
      if (mounted && _announcementSummaryText == '正在读取通知公告...') {
        setState(() => _announcementSummaryText = '点击查看通知公告');
      }
    }
  }

  Future<void> _refreshAnnouncementSummaryQuietly() async {
    if (_loadingAnnouncementSummary) {
      return;
    }
    _loadingAnnouncementSummary = true;
    try {
      final items = await _announcementRepository.fetchAnnouncements();
      final text = items.isEmpty ? '点击查看通知公告' : items.first.title;
      if (!mounted || text == _announcementSummaryText) {
        return;
      }
      setState(() => _announcementSummaryText = text);
    } on Object {
      if (mounted && _announcementSummaryText == '正在读取通知公告...') {
        setState(() => _announcementSummaryText = '点击查看通知公告');
      }
    } finally {
      _loadingAnnouncementSummary = false;
    }
  }

  Widget _openedTopicView(TopicListItem openedTopic) {
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
          onUploadImage: _repo.uploadImage,
          onCreateReply: _createReply,
          onOpenUser: _openUserProfile,
          onLoginRequired: _login,
        );
      },
    );
  }

  Widget _forumBody() {
    return Column(
      children: [
        ForumFilterBar(
          categories: _repo.categories,
          isHot: _feedQuery.hot,
          selectedCategoryId: _feedQuery.categoryId,
          onToggleMode: () => _setFeedQuery(
            TopicFeedQuery(
              categoryId: _feedQuery.categoryId,
              hot: !_feedQuery.hot,
            ),
          ),
          onSelectCategory: (id) => _setFeedQuery(
            TopicFeedQuery(categoryId: id, hot: _feedQuery.hot),
          ),
        ),
        Expanded(
          child: _topicList(
            future: _feedFuture,
            refresh: _refreshFeed,
            canLoadMore: _repo.canLoadMoreFeed(_feedQuery),
            isLoadingMore: _loadingMoreFeed,
            loadMore: _loadMoreFeed,
          ),
        ),
      ],
    );
  }

  Widget _topicList({
    required Future<List<TopicListItem>> future,
    required Future<void> Function() refresh,
    required bool canLoadMore,
    required bool isLoadingMore,
    required Future<void> Function() loadMore,
  }) {
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
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 96),
                EmptyState(
                  icon: Icons.inbox_outlined,
                  title: '暂无内容',
                  message: _repo.isOnline ? '论坛暂时没有返回主题。' : '本地样例中没有主题数据。',
                ),
              ],
            ),
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
            onOpenUser: (user) => _openUserProfile(user.username),
            canLoadMore: canLoadMore,
            isLoadingMore: isLoadingMore,
            onLoadMore: loadMore,
          ),
        );
      },
    );
  }

  void _resetFeedFuture() {
    _feedFuture = _repo.fetchTopicFeed(_feedQuery);
    _loadingMoreFeed = false;
  }

  void _setFeedQuery(TopicFeedQuery query) {
    setState(() {
      _feedQuery = query;
      _resetFeedFuture();
    });
  }

  Future<void> _refreshFeed() async {
    final future = _repo.fetchTopicFeed(_feedQuery, forceRefresh: true);
    setState(() => _feedFuture = future);
    await future;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadMoreFeed() async {
    if (_loadingMoreFeed || !_repo.canLoadMoreFeed(_feedQuery)) {
      return;
    }
    setState(() => _loadingMoreFeed = true);
    try {
      final topics = await _repo.loadMoreTopicFeed(_feedQuery);
      if (!mounted) {
        return;
      }
      setState(() => _feedFuture = Future.value(topics));
    } on Object catch (error) {
      await _handleOperationError(error, title: '加载更多失败');
    } finally {
      if (mounted) {
        setState(() => _loadingMoreFeed = false);
      }
    }
  }

  Future<void> _openSearch() async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => ForumSearchPage(
          repository: _repo,
          onLoginRequired: _login,
        ),
      ),
    );
  }

  Future<void> _openUserProfile(String username) async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => UserProfilePage(
          repository: _repo,
          username: username,
        ),
      ),
    );
  }

  Future<void> _openProfileSettings() async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ProfileSettingsPage(repository: _repo),
      ),
    );
    if (!mounted) {
      return;
    }
    if (changed == true) {
      try {
        await _repo.fetchCurrentUserProfile(forceRefresh: true);
      } on Object {
        // 设置页内已经完成提交；返回刷新失败时保持本地已更新的资料。
      }
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _openCreateTopic() async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    final result = await Navigator.of(context).push<CreatedTopicResult>(
      MaterialPageRoute(
        builder: (context) => CreateTopicPage(
          repository: _repo,
          categories: _repo.categories,
          initialCategoryId: _feedQuery.categoryId,
        ),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    _showSnack('帖子已发布');
    await _refreshFeed();
    setState(() {
      _openedTopic = TopicListItem(
        id: result.post.topicId,
        title: result.title,
        postsCount: 1,
        replyCount: 0,
        highestPostNumber: 1,
        views: 0,
        likeCount: 0,
        categoryId: result.categoryId,
        posters: const [],
        createdAt: result.post.createdAt,
        lastPostedAt: result.post.createdAt,
      );
    });
  }

  Future<void> _openNotifications() async {
    if (!_repo.isOnline) {
      _openProfileLoginTab();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => NotificationsPage(
          repository: _repo,
          onOpenTopic: (topic) => setState(() => _openedTopic = topic),
        ),
      ),
    );
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
        _resetFeedFuture();
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

  void _openProfileLoginTab() {
    if (!mounted) {
      return;
    }
    setState(() {
      _tabIndex = 3;
      _openedTopic = null;
    });
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
        _resetFeedFuture();
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
        _resetFeedFuture();
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
      _resetFeedFuture();
    });
  }

  Future<void> _openAcademicSystem() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => AcademicSchedulePage(
          repository: _scheduleRepository,
          notificationService: _scheduleNotificationService,
          onLoginRequired: _openAcademicLogin,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _refreshScheduleSummaryQuietly();
    unawaited(_scheduleNotificationService.syncScheduleReminders());
  }

  Future<void> _openAnnouncements() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => AnnouncementsPage(
          repository: _announcementRepository,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadAnnouncementSummaryFromCache();
    unawaited(_refreshAnnouncementSummaryQuietly());
  }

  Future<void> _openEmptyClassroom() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => EmptyClassroomPage(
          repository: _classroomRepository,
        ),
      ),
    );
  }

  Future<void> _openCourseRatings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => CourseRatingPage(
          repository: _courseRatingRepository,
        ),
      ),
    );
  }

  Future<void> _openAcademicLogin() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => const ForumWebViewPage(
          title: '教务系统',
          url: 'https://jwxt.shu.edu.cn',
        ),
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

class _LoginRequiredTab extends StatelessWidget {
  const _LoginRequiredTab({
    required this.icon,
    required this.title,
    required this.message,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: EmptyState(
        icon: icon,
        title: title,
        message: message,
        action: FilledButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.login),
          label: const Text('去登录'),
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
