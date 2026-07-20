import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/academic_constants.dart';
import '../core/academic_url_resolver.dart';
import '../core/client_app_info.dart';
import '../core/forum_url_resolver.dart';
import '../data/models/forum_activity.dart';
import '../data/models/forum_notification.dart';
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
import '../data/services/forum_badge_notification_service.dart';
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
import '../shared/theme/lehu_theme.dart';
import '../shared/widgets/client_update_prompt.dart';
import '../shared/widgets/info_confirm_dialog.dart';
import '../shared/widgets/app_header.dart';
import '../shared/widgets/empty_state.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    required this.reloadRepository,
    required this.selectedThemeId,
    required this.onThemeChanged,
  });

  final ForumRepository repository;
  final Future<ForumRepository> Function() reloadRepository;
  final String selectedThemeId;
  final Future<void> Function(String themeId) onThemeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _forumAccessModeReloadTimeout = Duration(seconds: 12);
  static const _forumBadgeRefreshInterval = Duration(seconds: 90);
  static const _backgroundForumBadgeRefreshInterval = Duration(minutes: 5);
  static const _feedLoadMoreThrottle = Duration(milliseconds: 900);

  int _tabIndex = 0;
  TopicFeedQuery _feedQuery = const TopicFeedQuery();
  bool _reloadingSession = false;
  bool _loadingMoreFeed = false;
  String? _loadMoreFeedError;
  DateTime? _lastLoadMoreFeedAttempt;
  final _feedSnapshots = <String, List<TopicListItem>>{};
  final _feedRequestTokens = <String, int>{};
  int _feedRequestSequence = 0;
  late ForumRepository _repo;
  late final AcademicScheduleRepository _scheduleRepository;
  late final AcademicScheduleNotificationService _scheduleNotificationService;
  late final ClientSettingsService _clientSettingsService;
  late final ForumBadgeNotificationService _forumBadgeNotificationService;
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
  bool _appInForeground = true;
  bool _forumNetworkUnavailable = false;
  bool _autoUseWebVpnProxy = ForumUrlResolver.usesWebVpn;
  int _seenNotificationBadgeCount = 0;
  int _seenMessageBadgeCount = 0;
  int _localNotificationBadgeCount = 0;
  int _messageRefreshSignal = 0;
  Set<String> _seenNotificationKeys = const {};
  bool _notificationSeenKeysInitialized = false;
  DateTime? _lastForumReachabilityCheck;
  String _scheduleSummaryText = '正在读取课表...';
  String _announcementSummaryText = '正在读取通知公告...';
  Completer<bool>? _academicWebVpnPreloadCompleter;
  int _academicWebVpnPreloadToken = 0;
  int _forumRepositoryReloadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repo = widget.repository;
    _scheduleRepository = AcademicScheduleRepository();
    _scheduleNotificationService = AcademicScheduleNotificationService(
      repository: _scheduleRepository,
    );
    _clientSettingsService = ClientSettingsService();
    _forumBadgeNotificationService = ForumBadgeNotificationService(
      settingsService: _clientSettingsService,
    );
    _clientBackendRepository = ClientBackendRepository();
    _forumReachabilityService = const ForumReachabilityService();
    _announcementRepository = AnnouncementRepository();
    _classroomRepository = ClassroomRepository();
    _courseRatingRepository = CourseRatingRepository();
    _resetFeedFuture();
    unawaited(_initializeForumBadges());
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
    _startForumBadgeRefreshTimer(_forumBadgeRefreshInterval);
    unawaited(_scheduleNotificationService.syncScheduleReminders());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkClientBackendPrompts());
    });
  }

  @override
  Widget build(BuildContext context) {
    final canOpenClientSettings = _tabIndex == 0 || _tabIndex == 3;
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
          final shouldRefreshMessages = index == 2 &&
              _repo.isOnline &&
              (index == _tabIndex || _messageBadgeCount > 0);
          setState(() {
            _tabIndex = index;
            if (shouldRefreshMessages) {
              _messageRefreshSignal++;
            }
          });
          if (index == 2) {
            unawaited(_markMessageBadgeSeen());
            unawaited(_refreshForumBadgesQuietly());
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      _startForumBadgeRefreshTimer(_forumBadgeRefreshInterval);
      unawaited(_refreshAfterAppResumed());
      return;
    }
    _appInForeground = false;
    _startForumBadgeRefreshTimer(_backgroundForumBadgeRefreshInterval);
  }

  void _startForumBadgeRefreshTimer(Duration interval) {
    _forumBadgeRefreshTimer?.cancel();
    _forumBadgeRefreshTimer = Timer.periodic(
      interval,
      (_) => unawaited(_refreshForumBadgesFromTimer()),
    );
  }

  Future<void> _refreshForumBadgesFromTimer() async {
    final notify = !_appInForeground;
    await _refreshForumBadgesQuietly(notify: notify);
    if (notify || !mounted || _tabIndex != 2 || !_repo.isOnline) {
      return;
    }
    setState(() => _messageRefreshSignal++);
  }

  Future<void> _refreshAfterAppResumed() async {
    await _refreshForumBadgesQuietly();
    if (!mounted || _tabIndex != 2 || !_repo.isOnline) {
      return;
    }
    setState(() => _messageRefreshSignal++);
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
    final sessionBadgeCount = count <= _seenNotificationBadgeCount
        ? 0
        : count - _seenNotificationBadgeCount;
    return sessionBadgeCount > _localNotificationBadgeCount
        ? sessionBadgeCount
        : _localNotificationBadgeCount;
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

  String _notificationFeedSeenKeysKey(String username) {
    return 'forum.badge.seen.notification_activity_keys.v2.$username';
  }

  String _messageBadgeSeenKey(String username) {
    return 'forum.badge.seen.messages.$username';
  }

  Future<void> _initializeForumBadges() async {
    await _loadLocalForumBadges();
    await _refreshForumBadgesQuietly();
  }

  Future<void> _loadLocalForumBadges() async {
    if (!_repo.isOnline) {
      if (mounted) {
        setState(() {
          _seenNotificationBadgeCount = 0;
          _seenMessageBadgeCount = 0;
          _localNotificationBadgeCount = 0;
          _seenNotificationKeys = const {};
          _notificationSeenKeysInitialized = false;
        });
      }
      return;
    }
    final username = _forumBadgeCacheUserKey;
    final prefs = await SharedPreferences.getInstance();
    final notificationCount =
        prefs.getInt(_notificationBadgeSeenKey(username)) ?? 0;
    final messageCount = prefs.getInt(_messageBadgeSeenKey(username)) ?? 0;
    final notificationKeys =
        prefs.getStringList(_notificationFeedSeenKeysKey(username));
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
      _localNotificationBadgeCount = 0;
      _seenNotificationKeys = notificationKeys?.toSet() ?? const {};
      _notificationSeenKeysInitialized = notificationKeys != null;
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
    Set<String>? notificationKeys;
    try {
      notificationKeys = await _fetchCurrentNotificationKeys();
    } on Object {
      notificationKeys = null;
    }
    if (!mounted || !_repo.isOnline || username != _forumBadgeCacheUserKey) {
      return;
    }
    setState(() {
      _seenNotificationBadgeCount = count;
      _localNotificationBadgeCount = 0;
      if (notificationKeys != null) {
        _seenNotificationKeys = notificationKeys;
        _notificationSeenKeysInitialized = true;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notificationBadgeSeenKey(username), count);
    if (notificationKeys != null) {
      await prefs.setStringList(
        _notificationFeedSeenKeysKey(username),
        _sortedNotificationKeys(notificationKeys),
      );
    }
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

  Future<void> _refreshForumBadgesQuietly({bool notify = false}) async {
    if (_refreshingForumBadges || _reloadingSession || !_repo.isOnline) {
      return;
    }
    _refreshingForumBadges = true;
    final username = _forumBadgeCacheUserKey;
    final previousNotificationCount = _repo.unreadNotificationCount;
    final previousMessageCount = _repo.unreadPrivateMessageCount;
    final previousLocalNotificationBadgeCount = _localNotificationBadgeCount;
    try {
      await _repo.refreshSession();
      if (!mounted || !_repo.isOnline || username != _forumBadgeCacheUserKey) {
        return;
      }
      final notificationFeedBadge = await _loadNotificationFeedBadge();
      if (!mounted || !_repo.isOnline || username != _forumBadgeCacheUserKey) {
        return;
      }
      final newNotificationCount = _positiveDelta(
        previousNotificationCount,
        _repo.unreadNotificationCount,
      );
      final newLocalNotificationCount = notificationFeedBadge == null
          ? 0
          : _positiveDelta(
              previousLocalNotificationBadgeCount,
              notificationFeedBadge.count,
            );
      final newMessageCount = _positiveDelta(
        previousMessageCount,
        _repo.unreadPrivateMessageCount,
      );
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
        if (notificationFeedBadge != null) {
          _localNotificationBadgeCount = notificationFeedBadge.count;
          if (notificationFeedBadge.baselineKeys != null) {
            _seenNotificationKeys = notificationFeedBadge.baselineKeys!;
            _notificationSeenKeysInitialized = true;
          }
        }
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
      final baselineKeys = notificationFeedBadge?.baselineKeys;
      if (baselineKeys != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
          _notificationFeedSeenKeysKey(username),
          _sortedNotificationKeys(baselineKeys),
        );
      }
      if (notify) {
        unawaited(
          _forumBadgeNotificationService.showBadgeSummary(
            newNotifications: newNotificationCount > newLocalNotificationCount
                ? newNotificationCount
                : newLocalNotificationCount,
            newMessages: newMessageCount,
          ),
        );
      }
    } on Object {
      // 后台刷新红点失败不打扰用户，下一轮会继续尝试。
    } finally {
      _refreshingForumBadges = false;
    }
  }

  int _positiveDelta(int previous, int current) {
    if (current <= previous) {
      return 0;
    }
    return current - previous;
  }

  Future<_NotificationFeedBadge?> _loadNotificationFeedBadge() async {
    final keys = await _fetchCurrentNotificationKeys();
    if (!_notificationSeenKeysInitialized) {
      return _NotificationFeedBadge(count: 0, baselineKeys: keys);
    }
    final count =
        keys.where((key) => !_seenNotificationKeys.contains(key)).length;
    return _NotificationFeedBadge(count: count);
  }

  Future<Set<String>> _fetchCurrentNotificationKeys() async {
    final notifications = await _repo.fetchNotifications(
      NotificationFeedFilter.all,
      forceRefresh: true,
    );
    return notifications.map(_notificationKey).toSet();
  }

  String _notificationKey(ForumNotification notification) {
    final createdAt = notification.createdAt?.millisecondsSinceEpoch ?? 0;
    return [
      notification.kind,
      notification.topicId ?? 0,
      notification.postNumber ?? 0,
      notification.id,
      createdAt,
    ].join(':');
  }

  List<String> _sortedNotificationKeys(Set<String> keys) {
    return keys.toList()..sort();
  }

  Widget _bodyForTab() {
    return IndexedStack(
      index: _tabIndex,
      children: [
        _homeBody(),
        _repo.isOnline
            ? _forumBody()
            : _LoginRequiredTab(
                icon: Icons.forum,
                title: '登录以查看论坛',
                message: '论坛需要登录后访问哦',
                onTap: _openProfileLoginTab,
              ),
        _repo.isOnline
            ? MessagesPage(
                repository: _repo,
                onLoginRequired: _openProfileLoginTab,
                refreshSignal: _messageRefreshSignal,
              )
            : _LoginRequiredTab(
                icon: Icons.chat_bubble,
                title: '登录后查看消息',
                message: '立即登录！查看论坛私信',
                onTap: _openProfileLoginTab,
              ),
        ProfilePage(
          profile: _repo.profile,
          summary: _repo.userSummary,
          isOnline: _repo.isOnline,
          isBusy: _reloadingSession,
          onLogin: _login,
          onEditProfile: _openProfileSettings,
          activityCountsFuture: _profileActivityCountsFuture,
          onOpenActivity: (kind) => unawaited(_openProfileActivity(kind)),
        ),
      ],
    );
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
      await _scheduleNotificationService.syncScheduleReminders(
        requestPermission: true,
      );
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
            loadMoreError: _loadMoreFeedError,
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
    required String? loadMoreError,
    required Future<void> Function() loadMore,
  }) {
    final cachedTopics = _feedSnapshots[_feedQuery.key];
    return FutureBuilder<List<TopicListItem>>(
      future: future,
      initialData: cachedTopics,
      builder: (context, snapshot) {
        final topics = snapshot.data ?? cachedTopics;
        if (topics == null &&
            snapshot.connectionState != ConnectionState.done) {
          return const _LoadingState(message: '正在加载列表...');
        }
        if (topics == null && snapshot.hasError) {
          return _ErrorState(
            title: '列表加载失败',
            message: snapshot.error.toString(),
            onRetry: () => refresh(),
          );
        }
        final visibleTopics = topics ?? const <TopicListItem>[];
        if (visibleTopics.isEmpty) {
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
            topics: visibleTopics,
            users: _repo.users,
            previewForTopic: _repo.fetchTopicPreview,
            categoryById: _repo.categoryById,
            onOpenTopic: (topic) => unawaited(_openTopic(topic)),
            onOpenUser: (user) => _openUserProfile(user.username),
            canLoadMore: canLoadMore,
            isLoadingMore: isLoadingMore,
            loadMoreError: loadMoreError,
            onLoadMore: loadMore,
          ),
        );
      },
    );
  }

  void _resetFeedFuture({bool forceRefresh = false}) {
    final query = _feedQuery;
    _feedFuture = _cacheFeedFuture(
      query.key,
      _repo.fetchTopicFeed(
        query,
        forceRefresh: forceRefresh,
      ),
    );
    _loadingMoreFeed = false;
    _loadMoreFeedError = null;
  }

  Future<List<TopicListItem>> _cacheFeedFuture(
    String queryKey,
    Future<List<TopicListItem>> future,
  ) {
    final token = ++_feedRequestSequence;
    _feedRequestTokens[queryKey] = token;
    return future.then((topics) {
      if (_feedRequestTokens[queryKey] == token) {
        _feedSnapshots[queryKey] = topics;
      }
      return topics;
    });
  }

  void _clearFeedSnapshots() {
    _feedSnapshots.clear();
    _feedRequestTokens.clear();
    _feedRequestSequence++;
  }

  void _setFeedQuery(TopicFeedQuery query, {bool forceRefresh = false}) {
    setState(() {
      _feedQuery = query;
      _resetFeedFuture(forceRefresh: forceRefresh);
    });
  }

  Future<void> _refreshFeed() async {
    final queryKey = _feedQuery.key;
    final future = _cacheFeedFuture(
      queryKey,
      _repo.fetchTopicFeed(_feedQuery, forceRefresh: true),
    );
    setState(() {
      _feedFuture = future;
      _loadMoreFeedError = null;
    });
    try {
      await future;
      if (mounted) {
        setState(() {});
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      if (_feedSnapshots[queryKey] != null) {
        _showSnack('列表刷新失败：${_friendlyError(error)}');
        setState(() {});
        return;
      }
      rethrow;
    }
  }

  Future<void> _loadMoreFeed() async {
    final query = _feedQuery;
    if (_loadingMoreFeed || !_repo.canLoadMoreFeed(query)) {
      return;
    }
    final now = DateTime.now();
    final lastAttempt = _lastLoadMoreFeedAttempt;
    if (_loadMoreFeedError == null &&
        lastAttempt != null &&
        now.difference(lastAttempt) < _feedLoadMoreThrottle) {
      return;
    }
    _lastLoadMoreFeedAttempt = now;
    final queryKey = query.key;
    setState(() {
      _loadingMoreFeed = true;
      _loadMoreFeedError = null;
    });
    try {
      final topics = await _repo.loadMoreTopicFeed(query);
      if (!mounted || queryKey != _feedQuery.key) {
        return;
      }
      setState(() {
        _feedSnapshots[queryKey] = topics;
        _feedFuture = Future.value(topics);
      });
    } on Object catch (error) {
      if (!mounted || queryKey != _feedQuery.key) {
        return;
      }
      setState(() => _loadMoreFeedError = _loadMoreFeedErrorText(error));
    } finally {
      if (mounted) {
        setState(() => _loadingMoreFeed = false);
      }
    }
  }

  String _loadMoreFeedErrorText(Object error) {
    if (error is ForumAuthException) {
      return '加载失败，登录状态可能已变化';
    }
    return '加载失败，点击重试';
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
          forumBadgeNotificationService: _forumBadgeNotificationService,
          backendRepository: _clientBackendRepository,
          selectedThemeId: widget.selectedThemeId,
          onThemeChanged: widget.onThemeChanged,
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
        _clearFeedSnapshots();
        _resetFeedFuture();
      });
      unawaited(_initializeForumBadges());
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
        _clearFeedSnapshots();
        _resetFeedFuture();
      });
      unawaited(_initializeForumBadges());
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
        _clearFeedSnapshots();
        _resetFeedFuture();
      });
      unawaited(_initializeForumBadges());
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
      _clearFeedSnapshots();
      _resetFeedFuture();
    });
    unawaited(_initializeForumBadges());
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
      } else {
        await _clientBackendRepository.ensureUpdateBaselineInitialized(
          version.latestBuild,
        );
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
        _clearFeedSnapshots();
        _resetFeedFuture();
      });
      unawaited(_initializeForumBadges());
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

class _NotificationFeedBadge {
  const _NotificationFeedBadge({
    required this.count,
    this.baselineKeys,
  });

  final int count;
  final Set<String>? baselineKeys;
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
    final colors = context.lehuColors;
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
            decoration: BoxDecoration(
              color: colors.danger,
              borderRadius: const BorderRadius.all(Radius.circular(9)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: colors.onDanger,
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
    final colors = context.lehuColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(message, style: TextStyle(color: colors.textSecondary)),
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
