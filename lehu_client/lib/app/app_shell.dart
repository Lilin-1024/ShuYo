import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/academic_constants.dart';
import '../core/academic_url_resolver.dart';
import '../core/client_app_info.dart';
import '../core/forum_url_resolver.dart';
import '../data/models/forum_activity.dart';
import '../data/models/topic.dart';
import '../data/repositories/client_backend_repository.dart';
import '../data/repositories/academic_schedule_repository.dart';
import '../data/repositories/announcement_repository.dart';
import '../data/repositories/classroom_repository.dart';
import '../data/repositories/course_rating_repository.dart';
import '../data/repositories/forum_repository.dart';
import '../data/services/academic_schedule_notification_service.dart';
import '../data/services/academic_schedule_api_client.dart';
import '../data/services/client_settings_service.dart';
import '../data/services/discourse_api_client.dart';
import '../data/services/forum_image_headers.dart';
import '../data/services/forum_reachability_service.dart';
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
import '../features/profile/forum_activity_page.dart';
import '../features/profile/profile_settings_page.dart';
import '../features/profile/user_profile_page.dart';
import '../features/settings/client_settings_page.dart';
import '../features/topic/topic_detail_page.dart';
import '../features/webview/academic_webvpn_preloader.dart';
import '../features/webview/forum_webview_page.dart';
import '../shared/navigation/lehu_route.dart';
import '../shared/widgets/client_update_prompt.dart';
import '../shared/widgets/info_confirm_dialog.dart';
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
  static const _forumAccessModeReloadTimeout = Duration(seconds: 12);
  static const _forumBadgeRefreshInterval = Duration(seconds: 90);

  int _tabIndex = 0;
  TopicFeedQuery _feedQuery = const TopicFeedQuery();
  bool _reloadingSession = false;
  bool _loadingMoreFeed = false;
  late ForumRepository _repo;
  late final AcademicScheduleRepository _scheduleRepository;
  late final AcademicScheduleNotificationService _scheduleNotificationService;
  late final ClientSettingsService _clientSettingsService;
  late final ClientBackendRepository _clientBackendRepository;
  late final ForumReachabilityService _forumReachabilityService;
  late final AnnouncementRepository _announcementRepository;
  late final ClassroomRepository _classroomRepository;
  late final CourseRatingRepository _courseRatingRepository;
  late Future<List<TopicListItem>> _feedFuture;
  Future<ForumActivityCounts>? _activityCountsFuture;
  Timer? _scheduleSummaryTimer;
  Timer? _announcementSummaryTimer;
  Timer? _forumBadgeRefreshTimer;
  bool _loadingScheduleSummary = false;
  bool _syncingAcademicSchedule = false;
  bool _loadingAnnouncementSummary = false;
  bool _refreshingForumBadges = false;
  bool _checkingForumReachability = false;
  bool _checkingClientBackendPrompts = false;
  bool _forumNetworkUnavailable = false;
  bool _autoUseWebVpnProxy = ForumUrlResolver.usesWebVpn;
  int _seenNotificationBadgeCount = 0;
  int _seenMessageBadgeCount = 0;
  DateTime? _lastForumReachabilityCheck;
  String _scheduleSummaryText = '正在读取课表...';
  String _announcementSummaryText = '正在读取通知公告...';
  Completer<bool>? _academicWebVpnPreloadCompleter;
  int _academicWebVpnPreloadToken = 0;
  int _forumRepositoryReloadToken = 0;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository;
    _scheduleRepository = AcademicScheduleRepository();
    _scheduleNotificationService = AcademicScheduleNotificationService(
      repository: _scheduleRepository,
    );
    _clientSettingsService = ClientSettingsService();
    _clientBackendRepository = ClientBackendRepository();
    _forumReachabilityService = const ForumReachabilityService();
    _announcementRepository = AnnouncementRepository();
    _classroomRepository = ClassroomRepository();
    _courseRatingRepository = CourseRatingRepository();
    _resetFeedFuture();
    unawaited(_loadLocalForumBadges());
    unawaited(_refreshScheduleSummaryQuietly());
    unawaited(_loadNetworkSettings());
    unawaited(_refreshForumReachabilityQuietly(force: true));
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
    _forumBadgeRefreshTimer = Timer.periodic(
      _forumBadgeRefreshInterval,
      (_) => unawaited(_refreshForumBadgesQuietly()),
    );
    unawaited(_scheduleNotificationService.syncScheduleReminders());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkClientBackendPrompts());
    });
  }

  @override
  Widget build(BuildContext context) {
    final canOpenClientSettings =
        _tabIndex == 0 || _tabIndex == 1 || _tabIndex == 3;
    final isForumTab = _tabIndex == 1 && _repo.isOnline;

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                AppHeader(
                  title: _headerTitle,
                  showSettings: canOpenClientSettings,
                  showSearch: isForumTab,
                  showCreate: isForumTab,
                  notificationCount: _notificationBadgeCount,
                  onSearch: _openSearch,
                  onCreate: _openCreateTopic,
                  onSettings: _openClientSettings,
                  onNotification: _openNotifications,
                ),
                Expanded(child: _bodyForTab()),
              ],
            ),
          ),
          if (_academicWebVpnPreloadCompleter != null)
            Positioned(
              left: 0,
              top: 0,
              child: AcademicWebVpnPreloader(
                key: ValueKey(_academicWebVpnPreloadToken),
                onComplete: _completeAcademicWebVpnPreload,
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (index) {
          setState(() => _tabIndex = index);
          if (index == 2) {
            unawaited(_markMessageBadgeSeen());
          }
          if (index == 0) {
            unawaited(_refreshScheduleSummaryQuietly());
            unawaited(_refreshForumReachabilityQuietly());
            unawaited(_refreshAnnouncementSummaryQuietly());
          }
        },
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: '首页'),
          const BottomNavigationBarItem(icon: Icon(Icons.forum), label: '论坛'),
          BottomNavigationBarItem(
            icon: _TabBadgeIcon(
              icon: Icons.chat_bubble_outline,
              count: _messageBadgeCount,
            ),
            label: '消息',
          ),
          const BottomNavigationBarItem(
              icon: Icon(Icons.account_circle), label: '我'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scheduleSummaryTimer?.cancel();
    _announcementSummaryTimer?.cancel();
    _forumBadgeRefreshTimer?.cancel();
    super.dispose();
  }

  String get _headerTitle {
    return switch (_tabIndex) {
      0 => '首页',
      1 => '论坛',
      2 => '消息',
      3 => '我',
      _ => '乐乎',
    };
  }

  int get _notificationBadgeCount {
    if (!_repo.isOnline) {
      return 0;
    }
    final count = _repo.unreadNotificationCount;
    return count <= _seenNotificationBadgeCount
        ? 0
        : count - _seenNotificationBadgeCount;
  }

  int get _messageBadgeCount {
    if (!_repo.isOnline) {
      return 0;
    }
    final count = _repo.unreadPrivateMessageCount;
    return count <= _seenMessageBadgeCount ? 0 : count - _seenMessageBadgeCount;
  }

  String get _forumBadgeCacheUserKey => _repo.profile.username.toLowerCase();

  String _notificationBadgeSeenKey(String username) {
    return 'forum.badge.seen.notifications.$username';
  }

  String _messageBadgeSeenKey(String username) {
    return 'forum.badge.seen.messages.$username';
  }

  Future<void> _loadLocalForumBadges() async {
    if (!_repo.isOnline) {
      if (mounted) {
        setState(() {
          _seenNotificationBadgeCount = 0;
          _seenMessageBadgeCount = 0;
        });
      }
      return;
    }
    final username = _forumBadgeCacheUserKey;
    final prefs = await SharedPreferences.getInstance();
    final notificationCount =
        prefs.getInt(_notificationBadgeSeenKey(username)) ?? 0;
    final messageCount = prefs.getInt(_messageBadgeSeenKey(username)) ?? 0;
    final normalizedNotificationCount =
        notificationCount.clamp(0, _repo.unreadNotificationCount);
    final normalizedMessageCount =
        messageCount.clamp(0, _repo.unreadPrivateMessageCount);
    if (!mounted || username != _forumBadgeCacheUserKey) {
      return;
    }
    setState(() {
      _seenNotificationBadgeCount = normalizedNotificationCount;
      _seenMessageBadgeCount = normalizedMessageCount;
    });
    if (normalizedNotificationCount != notificationCount) {
      unawaited(
        prefs.setInt(
          _notificationBadgeSeenKey(username),
          normalizedNotificationCount,
        ),
      );
    }
    if (normalizedMessageCount != messageCount) {
      unawaited(
        prefs.setInt(_messageBadgeSeenKey(username), normalizedMessageCount),
      );
    }
  }

  Future<void> _markNotificationBadgeSeen() async {
    if (!_repo.isOnline) {
      return;
    }
    final username = _forumBadgeCacheUserKey;
    final count = _repo.unreadNotificationCount;
    setState(() => _seenNotificationBadgeCount = count);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notificationBadgeSeenKey(username), count);
  }

  Future<void> _markMessageBadgeSeen() async {
    if (!_repo.isOnline) {
      return;
    }
    final username = _forumBadgeCacheUserKey;
    final count = _repo.unreadPrivateMessageCount;
    setState(() => _seenMessageBadgeCount = count);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_messageBadgeSeenKey(username), count);
  }

  Future<void> _refreshForumBadgesQuietly() async {
    if (_refreshingForumBadges || _reloadingSession || !_repo.isOnline) {
      return;
    }
    _refreshingForumBadges = true;
    final username = _forumBadgeCacheUserKey;
    try {
      await _repo.refreshSession();
      if (!mounted || !_repo.isOnline || username != _forumBadgeCacheUserKey) {
        return;
      }
      final normalizedNotificationCount =
          _seenNotificationBadgeCount.clamp(0, _repo.unreadNotificationCount);
      final normalizedMessageCount =
          _seenMessageBadgeCount.clamp(0, _repo.unreadPrivateMessageCount);
      final shouldPersist =
          normalizedNotificationCount != _seenNotificationBadgeCount ||
              normalizedMessageCount != _seenMessageBadgeCount;
      setState(() {
        _seenNotificationBadgeCount = normalizedNotificationCount;
        _seenMessageBadgeCount = normalizedMessageCount;
      });
      if (shouldPersist) {
        final prefs = await SharedPreferences.getInstance();
        await Future.wait([
          prefs.setInt(
            _notificationBadgeSeenKey(username),
            normalizedNotificationCount,
          ),
          prefs.setInt(_messageBadgeSeenKey(username), normalizedMessageCount),
        ]);
      }
    } on Object {
      // 后台刷新红点失败不打扰用户，下一轮会继续尝试。
    } finally {
      _refreshingForumBadges = false;
    }
  }

  Widget _bodyForTab() {
    return switch (_tabIndex) {
      0 => _homeBody(),
      1 => _repo.isOnline
          ? _forumBody()
          : _LoginRequiredTab(
              icon: Icons.forum,
              title: '登录以查看论坛',
              message: '论坛需要登录后访问哦',
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
              message: '立即登录！查看论坛私信',
              onTap: _openProfileLoginTab,
            ),
      3 => ProfilePage(
          profile: _repo.profile,
          summary: _repo.userSummary,
          isOnline: _repo.isOnline,
          isBusy: _reloadingSession,
          onLogin: _login,
          onEditProfile: _openProfileSettings,
          activityCountsFuture: _profileActivityCountsFuture,
          onOpenActivity: (kind) => unawaited(_openProfileActivity(kind)),
        ),
      _ => const SizedBox.shrink(),
    };
  }

  Future<ForumActivityCounts>? get _profileActivityCountsFuture {
    if (!_repo.isOnline) {
      return null;
    }
    return _activityCountsFuture ??= _repo.fetchActivityCounts();
  }

  Widget _homeBody() {
    return HomeDashboardPage(
      profile: _repo.profile,
      isOnline: _repo.isOnline,
      isBusy: _reloadingSession,
      onLogin: _login,
      onRelogin: _relogin,
      onOpenAcademicSystem: _syncingAcademicSchedule
          ? _showScheduleSyncingSnack
          : () => unawaited(_openAcademicSystem()),
      onOpenAnnouncements: () => unawaited(_openAnnouncements()),
      onOpenEmptyClassroom: () => unawaited(_openEmptyClassroom()),
      onOpenCourseRatings: () => unawaited(_openCourseRatings()),
      showForumNetworkWarning: _forumNetworkUnavailable && !_autoUseWebVpnProxy,
      onOpenWebVpnProxy: () => unawaited(_openWebVpnProxy()),
      todayCourseContent:
          _syncingAcademicSchedule ? '课表获取中...' : _scheduleSummaryText,
      announcementContent: _announcementSummaryText,
    );
  }

  Future<void> _loadNetworkSettings() async {
    try {
      final settings = await _clientSettingsService.loadNetworkSettings();
      final accessModeChanged =
          ForumUrlResolver.usesWebVpn != settings.autoUseWebVpnProxy;
      if (accessModeChanged) {
        _invalidateForumRepositoryReloads();
      }
      ForumUrlResolver.configure(
        useWebVpn: settings.autoUseWebVpnProxy,
      );
      ForumImageHeaders.clearCache();
      if (!mounted) {
        return;
      }
      setState(() {
        _autoUseWebVpnProxy = settings.autoUseWebVpnProxy;
      });
    } on Object {
      // 网络设置读取失败时保留当前访问模式，不阻断首页加载。
    }
  }

  Future<void> _refreshForumReachabilityQuietly({bool force = false}) async {
    if (_checkingForumReachability) {
      return;
    }
    final lastCheck = _lastForumReachabilityCheck;
    if (!force &&
        lastCheck != null &&
        DateTime.now().difference(lastCheck) < const Duration(minutes: 5)) {
      return;
    }
    _checkingForumReachability = true;
    _lastForumReachabilityCheck = DateTime.now();
    try {
      final result =
          await _forumReachabilityService.checkDirectBbsReachability();
      if (!mounted || _forumNetworkUnavailable == result.isUnavailable) {
        return;
      }
      setState(() {
        _forumNetworkUnavailable = result.isUnavailable;
      });
    } on Object {
      // 未知检测错误不展示内网不可达提示，避免把证书等非网络问题误报。
    } finally {
      _checkingForumReachability = false;
    }
  }

  Future<void> _setAutoUseWebVpnProxy(bool value) async {
    final settings = await _clientSettingsService.loadNetworkSettings();
    if (settings.autoUseWebVpnProxy != value) {
      await _clientSettingsService.saveNetworkSettings(
        settings.copyWith(autoUseWebVpnProxy: value),
      );
    }
    final accessModeChanged =
        ForumUrlResolver.usesWebVpn != value || _autoUseWebVpnProxy != value;
    if (accessModeChanged) {
      _invalidateForumRepositoryReloads();
    }
    ForumUrlResolver.configure(useWebVpn: value);
    ForumImageHeaders.clearCache();
    if (mounted) {
      setState(() {
        _autoUseWebVpnProxy = value;
        if (accessModeChanged && _reloadingSession) {
          _reloadingSession = false;
        }
      });
    }
  }

  Future<void> _refreshScheduleSummaryQuietly() async {
    if (_loadingScheduleSummary || _syncingAcademicSchedule) {
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

  Future<void> _syncScheduleAfterWebVpnLogin() async {
    if (_syncingAcademicSchedule) {
      debugPrint('[LEHU_WEBVPN] schedule-sync skipped: already loading');
      return;
    }
    debugPrint('[LEHU_WEBVPN] schedule-sync start');
    _loadingScheduleSummary = true;
    _syncingAcademicSchedule = true;
    if (mounted) {
      setState(() => _scheduleSummaryText = '课表获取中...');
    }
    try {
      final prepared = await _prepareAcademicWebVpnSessionInBackground();
      debugPrint('[LEHU_WEBVPN] schedule-sync prepared=$prepared');
      if (!prepared) {
        final summary = await _scheduleRepository.homeSummary();
        if (mounted) {
          setState(() => _scheduleSummaryText = summary.text);
        }
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      debugPrint('[LEHU_WEBVPN] schedule-sync refreshSchedule');
      await _scheduleRepository.refreshSchedule();
      final summary = await _scheduleRepository.homeSummary();
      if (!mounted) {
        return;
      }
      setState(() => _scheduleSummaryText = summary.text);
      unawaited(_scheduleNotificationService.syncScheduleReminders());
      _showSnack('WebVPN已登录，课表已同步');
      debugPrint('[LEHU_WEBVPN] schedule-sync success');
    } on AcademicAuthException catch (error) {
      debugPrint('[LEHU_WEBVPN] schedule-sync auth-error: $error');
      if (mounted) {
        final summary = await _scheduleRepository.homeSummary();
        if (mounted) {
          setState(() => _scheduleSummaryText = summary.text);
        }
      }
    } on Object catch (error) {
      debugPrint('[LEHU_WEBVPN] schedule-sync error: $error');
      if (mounted) {
        final summary = await _scheduleRepository.homeSummary();
        if (mounted) {
          setState(() => _scheduleSummaryText = summary.text);
        }
      }
    } finally {
      _loadingScheduleSummary = false;
      if (mounted) {
        setState(() => _syncingAcademicSchedule = false);
      } else {
        _syncingAcademicSchedule = false;
      }
    }
  }

  Future<bool> _prepareAcademicWebVpnSessionInBackground() async {
    if (!AcademicUrlResolver.usesWebVpn) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    final completer = Completer<bool>();
    setState(() {
      _academicWebVpnPreloadCompleter = completer;
      _academicWebVpnPreloadToken++;
    });
    try {
      return await completer.future.timeout(
        const Duration(seconds: 75),
        onTimeout: () {
          debugPrint('[LEHU_WEBVPN] background academic preload timeout');
          return false;
        },
      );
    } finally {
      if (mounted && identical(_academicWebVpnPreloadCompleter, completer)) {
        setState(() => _academicWebVpnPreloadCompleter = null);
      }
    }
  }

  void _completeAcademicWebVpnPreload(bool success) {
    final completer = _academicWebVpnPreloadCompleter;
    debugPrint('[LEHU_WEBVPN] background academic preload complete=$success');
    if (completer != null && !completer.isCompleted) {
      completer.complete(success);
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
            forceRefresh: true,
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
            onOpenTopic: (topic) => unawaited(_openTopic(topic)),
            onOpenUser: (user) => _openUserProfile(user.username),
            canLoadMore: canLoadMore,
            isLoadingMore: isLoadingMore,
            onLoadMore: loadMore,
          ),
        );
      },
    );
  }

  void _resetFeedFuture({bool forceRefresh = false}) {
    _feedFuture = _repo.fetchTopicFeed(
      _feedQuery,
      forceRefresh: forceRefresh,
    );
    _loadingMoreFeed = false;
  }

  void _setFeedQuery(TopicFeedQuery query, {bool forceRefresh = false}) {
    setState(() {
      _feedQuery = query;
      _resetFeedFuture(forceRefresh: forceRefresh);
    });
  }

  Future<void> _refreshFeed() async {
    final future = _repo.fetchTopicFeed(_feedQuery, forceRefresh: true);
    setState(() {
      _feedFuture = future;
    });
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
      setState(() {
        _feedFuture = Future.value(topics);
      });
    } on Object catch (error) {
      await _handleOperationError(error, title: '加载更多失败');
    } finally {
      if (mounted) {
        setState(() => _loadingMoreFeed = false);
      }
    }
  }

  Future<void> _openTopic(TopicListItem topic) async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    if (!mounted) {
      return;
    }
    final deleted = await Navigator.of(context).push<bool>(
      lehuRoute(
        builder: (context) => TopicDetailPage(
          repository: _repo,
          topic: topic,
          onLoginRequired: _login,
          onSessionExpired: _clearExpiredLogin,
          onBookmarkChanged: _refreshProfileActivityCounts,
        ),
      ),
    );
    if (deleted == true && mounted) {
      await _refreshFeed();
    }
  }

  void _refreshProfileActivityCounts() {
    if (!mounted || !_repo.isOnline) {
      return;
    }
    setState(() {
      _activityCountsFuture = _repo.fetchActivityCounts(forceRefresh: true);
    });
  }

  Future<void> _openSearch() async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => ForumSearchPage(
          repository: _repo,
          onLoginRequired: _login,
          onBookmarkChanged: _refreshProfileActivityCounts,
          onSessionExpired: _clearExpiredLogin,
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
      lehuRoute(
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
      lehuRoute(
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

  Future<void> _openProfileActivity(ForumActivityKind kind) async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    final topic = await Navigator.of(context).push<TopicListItem>(
      lehuRoute(
        builder: (context) => ForumActivityPage(
          repository: _repo,
          kind: kind,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    _refreshProfileActivityCounts();
    if (topic != null) {
      await _openTopic(topic);
    }
  }

  Future<void> _openClientSettings() async {
    final previousAutoProxy = _autoUseWebVpnProxy;
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => ClientSettingsPage(
          settingsService: _clientSettingsService,
          scheduleNotificationService: _scheduleNotificationService,
          backendRepository: _clientBackendRepository,
          isOnline: _repo.isOnline,
          onLogout: _logout,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadNetworkSettings();
    if (!mounted || previousAutoProxy == _autoUseWebVpnProxy) {
      return;
    }
    await _reloadForumRepositoryAfterAccessModeChange();
  }

  Future<void> _openCreateTopic() async {
    if (!_repo.isOnline) {
      await _login();
      return;
    }
    final result = await Navigator.of(context).push<CreatedTopicResult>(
      lehuRoute(
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
    await _openTopic(
      TopicListItem(
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
      ),
    );
  }

  Future<void> _openNotifications() async {
    if (!_repo.isOnline) {
      _openProfileLoginTab();
      return;
    }
    unawaited(_markNotificationBadgeSeen());
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => NotificationsPage(
          repository: _repo,
          onLoginRequired: _login,
          onSessionExpired: _clearExpiredLogin,
          onBookmarkChanged: _refreshProfileActivityCounts,
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (_reloadingSession) {
      return;
    }
    final logged = await Navigator.of(context).push<bool>(
      lehuRoute(builder: (context) => const LoginWebViewPage()),
    );
    if (logged != true || !mounted) {
      return;
    }
    ForumImageHeaders.clearCache();
    setState(() => _reloadingSession = true);
    try {
      final nextRepository = await widget.reloadRepository();
      if (!mounted) {
        return;
      }
      setState(() {
        _repo = nextRepository;
        _reloadingSession = false;
        _activityCountsFuture = null;
        _resetFeedFuture();
      });
      unawaited(_loadLocalForumBadges());
      _showSnack('已加载论坛');
      unawaited(_checkClientBackendPrompts());
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
        _reloadingSession = false;
        _activityCountsFuture = null;
        _resetFeedFuture();
      });
      unawaited(_loadLocalForumBadges());
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
        _reloadingSession = false;
        _activityCountsFuture = null;
        _resetFeedFuture();
      });
      unawaited(_loadLocalForumBadges());
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

  Future<void> _handleOperationError(
    Object error, {
    required String title,
  }) async {
    if (error is ForumAuthException) {
      await _clearExpiredLogin();
      await _showErrorDialog(
        title: '登录已失效',
        message: '请试着重新登录后再操作。',
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
      _activityCountsFuture = null;
      _resetFeedFuture();
    });
    unawaited(_loadLocalForumBadges());
  }

  Future<void> _openAcademicSystem() async {
    await Navigator.of(context).push<void>(
      lehuRoute(
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
      lehuRoute(
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
      lehuRoute(
        builder: (context) => EmptyClassroomPage(
          repository: _classroomRepository,
        ),
      ),
    );
  }

  Future<void> _openWebVpnProxy() async {
    final navigator = Navigator.of(context);
    debugPrint('[LEHU_WEBVPN] open webvpn proxy');
    final completed = await navigator.push<bool>(
      lehuRoute(
        builder: (context) => const ForumWebViewPage(
          title: 'WebVPN',
          url: ForumUrlResolver.webVpnPortalUrl,
          autoCloseUrlPrefixes: [
            ForumUrlResolver.webVpnSiteNavUrl,
            ForumUrlResolver.webVpnSiteNavHomeUrl,
          ],
        ),
      ),
    );
    debugPrint('[LEHU_WEBVPN] webvpn page completed=$completed');
    if (!mounted || completed != true) {
      return;
    }
    try {
      await _setAutoUseWebVpnProxy(true);
    } on Object catch (error) {
      _showSnack('WebVPN代理设置失败：$error');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _tabIndex = 0;
    });
    unawaited(_refreshForumReachabilityQuietly(force: true));
    unawaited(_checkClientBackendPrompts());
    await _syncScheduleAfterWebVpnLogin();
  }

  Future<void> _openCourseRatings() async {
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => CourseRatingPage(
          repository: _courseRatingRepository,
        ),
      ),
    );
  }

  Future<void> _checkClientBackendPrompts() async {
    if (_checkingClientBackendPrompts) {
      return;
    }
    _checkingClientBackendPrompts = true;
    try {
      final bootstrap =
          await _clientBackendRepository.fetchBootstrap(forceRefresh: true);
      if (!mounted) {
        return;
      }
      final version = bootstrap.version;
      if (version.isNewerThan(ClientAppInfo.buildNumber)) {
        final shouldPrompt = await _clientBackendRepository.shouldPromptUpdate(
          version.latestBuild,
        );
        if (mounted && shouldPrompt) {
          final openDownload = await showClientUpdatePrompt(
            context,
            update: version,
          );
          await _clientBackendRepository.markUpdatePrompted(
            version.latestBuild,
          );
          if (openDownload == true && version.hasDownloadUrl && mounted) {
            await _openUpdateDownload(version.downloadUrl);
          }
          return;
        }
      }

      if (!mounted) {
        return;
      }
      final announcement = bootstrap.latestAnnouncement;
      if (announcement == null) {
        await _clientBackendRepository.ensureAnnouncementBaselineInitialized();
        return;
      }
      final shouldPrompt = await _clientBackendRepository
          .shouldPromptAnnouncement(announcement.id);
      if (!mounted || !shouldPrompt) {
        return;
      }
      await showInfoConfirmDialog(
        context,
        title: announcement.title,
        message: announcement.content,
        confirmText: '知道了',
      );
      await _clientBackendRepository.markAnnouncementPrompted(announcement.id);
    } on Object {
      // 后端检查失败时不影响主流程。
    } finally {
      _checkingClientBackendPrompts = false;
    }
  }

  Future<void> _openUpdateDownload(String url) async {
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => ForumWebViewPage(
          title: '下载更新',
          url: url,
        ),
      ),
    );
  }

  Future<void> _reloadForumRepositoryAfterAccessModeChange() async {
    if (_reloadingSession) {
      return;
    }
    final reloadToken = _nextForumRepositoryReloadToken();
    final accessMode = ForumUrlResolver.mode;
    setState(() => _reloadingSession = true);
    try {
      final nextRepository = await _loadForumRepositoryForAccessModeChange();
      if (!_isCurrentForumRepositoryReload(reloadToken, accessMode)) {
        return;
      }
      setState(() {
        _repo = nextRepository;
        _reloadingSession = false;
        _activityCountsFuture = null;
        _resetFeedFuture();
      });
      unawaited(_loadLocalForumBadges());
      if (nextRepository.isOnline) {
        _showSnack('已切换论坛访问方式');
      }
      unawaited(_checkClientBackendPrompts());
    } on Object catch (error) {
      if (!_isCurrentForumRepositoryReload(reloadToken, accessMode)) {
        return;
      }
      setState(() => _reloadingSession = false);
      await _showErrorDialog(
        title: '论坛重新加载失败',
        message: _friendlyError(error),
      );
    }
  }

  int _nextForumRepositoryReloadToken() {
    _forumRepositoryReloadToken++;
    return _forumRepositoryReloadToken;
  }

  void _invalidateForumRepositoryReloads() {
    _forumRepositoryReloadToken++;
  }

  bool _isCurrentForumRepositoryReload(
    int reloadToken,
    ForumAccessMode accessMode,
  ) {
    return mounted &&
        reloadToken == _forumRepositoryReloadToken &&
        ForumUrlResolver.mode == accessMode;
  }

  Future<ForumRepository> _loadForumRepositoryForAccessModeChange() {
    return ForumRepositoryFactory.load().timeout(
      _forumAccessModeReloadTimeout,
      onTimeout: () => FixtureForumRepository.load(),
    );
  }

  Future<void> _openAcademicLogin() async {
    if (AcademicUrlResolver.usesWebVpn) {
      await Navigator.of(context).push<void>(
        lehuRoute(
          builder: (context) => ForumWebViewPage(
            title: '教务系统',
            url: AcademicUrlResolver.entryUri.toString(),
            initialNoticeTitle: '教务系统说明',
            initialNoticeMessage:
                '当前已开启WebVPN代理。完成统一身份认证后，课表通常可以直接同步。\n\n本应用只读取课表数据，不会收集或保存你的账号密码。',
            initialNoticeDelay: const Duration(seconds: 5),
            debugLabel: 'ACADEMIC_MANUAL',
            showDebugInfo: true,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => ForumWebViewPage(
          title: '教务系统',
          url:
              '${AcademicUrlResolver.baseUrl}${AcademicConstants.scheduleIndexPath}',
          initialNoticeTitle: '教务系统登录',
          initialNoticeMessage:
              '教务系统为独立系统，需要你在网页中单独登录一次。\n\n本应用只读取课表数据，不会收集或保存你的账号密码。',
          initialNoticeDelay: const Duration(seconds: 5),
        ),
      ),
    );
  }

  void _showScheduleSyncingSnack() {
    _showSnack('正在获取课表，请稍后');
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
      return '还没有检测到登录态。请确认已在网页中登录成功，再点“完成”。';
    }
    if (error is ForumApiException) {
      return error.message;
    }
    return '登录态检测失败，请确认能访问校园网或使用 VPN。';
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

class _TabBadgeIcon extends StatelessWidget {
  const _TabBadgeIcon({
    required this.icon,
    required this.count,
  });

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return Icon(icon);
    }
    final label = count > 99 ? '99+' : '$count';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -10,
          top: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFE53935),
              borderRadius: BorderRadius.all(Radius.circular(9)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
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
