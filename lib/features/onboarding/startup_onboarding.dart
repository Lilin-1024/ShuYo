import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/client_settings_service.dart';
import '../auth/native_login_page.dart';

enum ForumAccountStatus {
  signedOut,
  connecting,
  loggedIn,
  connectionUnavailable,
  waitingForAcademicLogin,
  reauthenticationRequired,
  directLoginUnavailable,
}

class StartupOnboardingController extends ChangeNotifier {
  bool _academicLoggedIn = false;
  ForumAccountStatus _forumStatus = ForumAccountStatus.signedOut;
  VoidCallback? _onForumReconnect;
  Future<void> Function()? _onAcademicLogout;
  Future<void> Function()? _onForumLogout;
  int _openRequest = 0;
  bool _notificationScheduled = false;
  bool _disposed = false;

  bool get academicLoggedIn => _academicLoggedIn;
  ForumAccountStatus get forumStatus => _forumStatus;
  int get openRequest => _openRequest;

  void openAccountManager({
    required bool academicLoggedIn,
    required ForumAccountStatus forumStatus,
  }) {
    _academicLoggedIn = academicLoggedIn;
    _forumStatus = forumStatus;
    _openRequest++;
    _notifyListenersSafely();
  }

  void setForumReconnectHandler(VoidCallback? handler) {
    _onForumReconnect = handler;
  }

  void updateAccountStatus({
    required bool academicLoggedIn,
    required ForumAccountStatus forumStatus,
  }) {
    if (_academicLoggedIn == academicLoggedIn && _forumStatus == forumStatus) {
      return;
    }
    _academicLoggedIn = academicLoggedIn;
    _forumStatus = forumStatus;
    _notifyListenersSafely();
  }

  void reconnectForum() => _onForumReconnect?.call();

  void setAccountLogoutHandlers({
    Future<void> Function()? onAcademicLogout,
    Future<void> Function()? onForumLogout,
  }) {
    _onAcademicLogout = onAcademicLogout;
    _onForumLogout = onForumLogout;
  }

  Future<void> logoutAcademic() async => await _onAcademicLogout?.call();

  Future<void> logoutForum() async => await _onForumLogout?.call();

  bool get canLogoutAcademic => _onAcademicLogout != null;
  bool get canLogoutForum => _onForumLogout != null;

  void _notifyListenersSafely() {
    if (_disposed) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _onForumReconnect = null;
    _onAcademicLogout = null;
    _onForumLogout = null;
    super.dispose();
  }
}

class StartupOnboarding extends StatefulWidget {
  const StartupOnboarding({
    super.key,
    required this.child,
    required this.initiallyCompleted,
    required this.initialAcademicLoggedIn,
    required this.initialForumStatus,
    required this.onAcademicLoginCompleted,
    required this.onForumLoginCompleted,
    this.onAcademicLogout,
    this.onForumLogout,
    required this.controller,
    this.settingsService,
  });

  final Widget child;
  final bool initiallyCompleted;
  final bool initialAcademicLoggedIn;
  final ForumAccountStatus initialForumStatus;
  final VoidCallback onAcademicLoginCompleted;
  final VoidCallback onForumLoginCompleted;
  final Future<void> Function()? onAcademicLogout;
  final Future<void> Function()? onForumLogout;
  final StartupOnboardingController controller;
  final ClientSettingsService? settingsService;

  @override
  State<StartupOnboarding> createState() => _StartupOnboardingState();
}

class _StartupOnboardingState extends State<StartupOnboarding>
    with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  late final ClientSettingsService _settingsService =
      widget.settingsService ?? ClientSettingsService();
  late final AnimationController _panelAnimationController;
  late final Animation<Offset> _panelSlideAnimation;
  late final Animation<double> _barrierOpacityAnimation;
  int _page = 0;
  late bool _visible = !widget.initiallyCompleted;
  bool _accountManagerMode = false;
  bool _showForumCampusAccountHint = false;
  bool _showForumDirectUnavailableHint = false;
  late bool _academicLoggedIn = widget.initialAcademicLoggedIn;
  late ForumAccountStatus _forumStatus = widget.initialForumStatus;
  late int _handledOpenRequest;

  @override
  void initState() {
    super.initState();
    _handledOpenRequest = widget.controller.openRequest;
    _panelAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 240),
    );
    final curvedAnimation = CurvedAnimation(
      parent: _panelAnimationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _panelSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(curvedAnimation);
    _barrierOpacityAnimation = CurvedAnimation(
      parent: _panelAnimationController,
      curve: const Interval(0, .72, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    widget.controller.addListener(_handleControllerChange);
    if (_visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _panelAnimationController.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant StartupOnboarding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_handleControllerChange);
      widget.controller.addListener(_handleControllerChange);
      _handledOpenRequest = widget.controller.openRequest;
    }
    if (widget.initialAcademicLoggedIn != oldWidget.initialAcademicLoggedIn) {
      _academicLoggedIn = widget.initialAcademicLoggedIn;
      if (_academicLoggedIn) _showForumCampusAccountHint = false;
    }
    if (widget.initialForumStatus != oldWidget.initialForumStatus) {
      _forumStatus = widget.initialForumStatus;
    }
  }

  void _handleControllerChange() {
    if (!mounted) return;
    final shouldOpen = _handledOpenRequest != widget.controller.openRequest;
    if (!shouldOpen) {
      setState(() {
        _academicLoggedIn = widget.controller.academicLoggedIn;
        _forumStatus = widget.controller.forumStatus;
        if (_academicLoggedIn) _showForumCampusAccountHint = false;
        if (_forumStatus != ForumAccountStatus.directLoginUnavailable) {
          _showForumDirectUnavailableHint = false;
        }
      });
      return;
    }
    _handledOpenRequest = widget.controller.openRequest;
    setState(() {
      _visible = true;
      _accountManagerMode = true;
      _page = 2;
      _academicLoggedIn = widget.controller.academicLoggedIn;
      _forumStatus = widget.controller.forumStatus;
      _showForumCampusAccountHint = false;
      _showForumDirectUnavailableHint = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(2);
      }
      if (mounted) _panelAnimationController.forward(from: 0);
    });
  }

  Future<void> _continue() async {
    if (_page == 1) await _requestNotifications();
    if (!mounted) return;
    if (_page < 2) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      if (mounted) setState(() => _page++);
      return;
    }
    if (_accountManagerMode) {
      await _complete();
      return;
    }
    if (_academicLoggedIn && _forumStatus == ForumAccountStatus.loggedIn) {
      await _complete();
    }
  }

  Future<void> _openAcademicLogin() async {
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NativeLoginPage()),
    );
    if (loggedIn != true || !mounted) return;
    setState(() {
      _academicLoggedIn = true;
      _showForumCampusAccountHint = false;
    });
    widget.onAcademicLoginCompleted();
  }

  Future<void> _logoutAcademic() async {
    final callback =
        widget.onAcademicLogout ?? widget.controller.logoutAcademic;
    final confirmed = await _confirmLogout(
      title: '退出上大校园账户？',
      message: '退出后课表和校园服务需要重新登录。论坛账户也需在登录校园账户后使用。',
    );
    if (!confirmed || !mounted) return;
    await callback();
  }

  Future<void> _openForumLogin() async {
    if (!_academicLoggedIn) {
      _showCampusAccountRequiredHint();
      return;
    }
    if (_showForumCampusAccountHint) {
      setState(() => _showForumCampusAccountHint = false);
    }
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NativeLoginPage.forum()),
    );
    if (loggedIn != true || !mounted) return;
    setState(() => _forumStatus = ForumAccountStatus.connecting);
    widget.onForumLoginCompleted();
  }

  Future<void> _logoutForum() async {
    final callback = widget.onForumLogout ?? widget.controller.logoutForum;
    final confirmed = await _confirmLogout(
      title: '退出乐乎论坛账户？',
      message: '退出后将清除论坛会话和本地账户数据，校园账户不会受影响。',
    );
    if (!confirmed || !mounted) return;
    await callback();
  }

  Future<bool> _confirmLogout({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('退出'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _reconnectForum() {
    if (!_academicLoggedIn) {
      _showCampusAccountRequiredHint();
      return;
    }
    if (_showForumCampusAccountHint) {
      setState(() => _showForumCampusAccountHint = false);
    }
    widget.controller.reconnectForum();
  }

  Future<void> _restoreForumAfterAcademicLogin() async {
    await _openAcademicLogin();
    if (!mounted || !_academicLoggedIn) return;
    setState(() => _forumStatus = ForumAccountStatus.connecting);
    widget.controller.reconnectForum();
  }

  void _showCampusAccountRequiredHint() {
    if (_showForumCampusAccountHint) return;
    setState(() => _showForumCampusAccountHint = true);
  }

  void _showDirectForumUnavailableHint() {
    if (_showForumDirectUnavailableHint) return;
    setState(() => _showForumDirectUnavailableHint = true);
  }

  Future<void> _complete() async {
    if (!_accountManagerMode) {
      await _settingsService.saveStartupOnboardingCompleted(true);
    }
    await _hidePanel();
  }

  Future<void> _goBack() async {
    if (_page <= 0) return;
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    if (mounted) setState(() => _page--);
  }

  Future<void> _closeAccountManager() async {
    if (_accountManagerMode) await _hidePanel();
  }

  void _handlePanelDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (delta == 0) return;
    final panelHeight = MediaQuery.sizeOf(context).height * .86;
    _panelAnimationController.value =
        (_panelAnimationController.value - delta / panelHeight).clamp(0, 1);
  }

  void _handlePanelDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 500 || _panelAnimationController.value < .8) {
      unawaited(_hidePanel());
      return;
    }
    unawaited(_panelAnimationController.forward());
  }

  Future<void> _hidePanel() async {
    if (!_visible) return;
    await _panelAnimationController.reverse();
    if (mounted) setState(() => _visible = false);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _panelAnimationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _requestNotifications() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } on Object {
      // 系统服务暂不可用时仍允许用户完成首次引导。
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_visible) ...[
          Positioned.fill(
            child: FadeTransition(
              opacity: _barrierOpacityAnimation,
              child: ModalBarrier(
                color: Colors.black.withValues(alpha: .32),
                dismissible: true,
                onDismiss: () => unawaited(_hidePanel()),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: _panelSlideAnimation,
              child: _panel(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _panel(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canSkip = !_accountManagerMode &&
        _page == 2 &&
        _academicLoggedIn &&
        _forumStatus != ForumAccountStatus.loggedIn;
    final showFooter = _accountManagerMode ||
        _page < 2 ||
        (_academicLoggedIn && _forumStatus == ForumAccountStatus.loggedIn);
    return Material(
      key: const ValueKey('startup-onboarding-panel'),
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.sizeOf(context).height * .86,
          child: Column(
            children: [
              GestureDetector(
                key: const ValueKey('startup-onboarding-drag-handle'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: _handlePanelDragUpdate,
                onVerticalDragEnd: _handlePanelDragEnd,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      if (_page > 0)
                        Positioned(
                          left: 8,
                          top: 4,
                          child: IconButton(
                            tooltip: '返回上一页',
                            onPressed: _goBack,
                            icon: const Icon(Icons.arrow_back),
                          ),
                        ),
                      if (canSkip)
                        Positioned(
                          right: 12,
                          top: 4,
                          child: TextButton(
                            onPressed: _complete,
                            child: const Text('跳过'),
                          ),
                        ),
                      if (_accountManagerMode)
                        Positioned(
                          right: 8,
                          top: 4,
                          child: IconButton(
                            tooltip: '关闭',
                            onPressed: _closeAccountManager,
                            icon: const Icon(Icons.close),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  key: const ValueKey('startup-onboarding-pages'),
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _welcome(context),
                    _notifications(context),
                    _login(context),
                  ],
                ),
              ),
              SizedBox(
                key: const ValueKey('startup-onboarding-footer'),
                height: 78,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                  child: showFooter
                      ? FilledButton(
                          onPressed: _continue,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _accountManagerMode && _page == 2
                                ? '完成'
                                : _page == 2
                                    ? '开始使用'
                                    : '继续',
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context) => _content(
        context,
        '欢迎使用ShuYo',
        null,
        [
          _feature(Icons.calendar_month, '课表与空教室', '快速查看课程安排和可用教室'),
          _feature(Icons.forum_outlined, '乐乎论坛', '浏览校园动态，参与讨论'),
          _feature(Icons.notifications_none, '重要提醒', '不错过课程和校园公告'),
        ],
        pageFooter: _terms(context),
      );

  Widget _notifications(BuildContext context) => _content(
        context,
        '开启通知权限',
        null,
        [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Text(
              'ShuYo 会发送上课提醒，请在下一步中授予我们推送通知权限，'
              '你可以随时在系统设置中关闭通知',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ),
        ],
      );

  Widget _login(BuildContext context) => _pageLayout(
        context,
        header: _pageHeader(
          context,
          title: '账号管理',
          subtitle: 'ShuYo 使用双账户系统，包括上大校园账户和乐乎账户。',
          subtitlePadding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        headerSpacing: 22,
        bottomChildren: [
          _accountTile(
            context,
            icon: Icons.school_outlined,
            title: '上大校园账户',
            description: '用于访问课程表、教室查询等校园服务',
            statusLabel: _academicLoggedIn ? '已登录' : null,
            onTap: _academicLoggedIn
                ? (widget.onAcademicLogout == null &&
                        !widget.controller.canLogoutAcademic
                    ? null
                    : _logoutAcademic)
                : _openAcademicLogin,
          ),
          _forumAccountTile(context),
          _forumCampusAccountHint(context),
          _forumDirectUnavailableHint(context),
        ],
      );

  Widget _forumCampusAccountHint(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: _showForumCampusAccountHint
          ? Padding(
              key: const ValueKey('forum-campus-account-hint'),
              padding: const EdgeInsets.fromLTRB(56, 0, 4, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: colors.error),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '请先登录上大校园账户',
                      style: TextStyle(
                        color: colors.error,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(
              key: ValueKey('forum-campus-account-hint-hidden'),
            ),
    );
  }

  Widget _forumDirectUnavailableHint(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: _showForumDirectUnavailableHint
          ? Padding(
              key: const ValueKey('forum-direct-unavailable-hint'),
              padding: const EdgeInsets.fromLTRB(56, 0, 4, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: colors.error),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '暂时无法直连登录校园论坛，信息办未续论坛证书',
                      style: TextStyle(
                        color: colors.error,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(key: ValueKey('forum-direct-unavailable-hidden')),
    );
  }

  Widget _forumAccountTile(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, color, busy, onTap) = switch (_forumStatus) {
      ForumAccountStatus.signedOut => (
          null,
          null,
          false,
          _openForumLogin as VoidCallback
        ),
      ForumAccountStatus.connecting => (
          '正在连接',
          colors.onSurfaceVariant,
          true,
          null
        ),
      ForumAccountStatus.loggedIn => (
          '已登录',
          colors.primary,
          false,
          widget.onForumLogout == null && !widget.controller.canLogoutForum
              ? null
              : _logoutForum,
        ),
      ForumAccountStatus.connectionUnavailable => (
          '连接异常',
          colors.error,
          false,
          _reconnectForum,
        ),
      ForumAccountStatus.waitingForAcademicLogin => (
          '等待校园账户登录',
          colors.error,
          false,
          _restoreForumAfterAcademicLogin as VoidCallback,
        ),
      ForumAccountStatus.reauthenticationRequired => (
          '登录已失效',
          colors.error,
          false,
          _openForumLogin as VoidCallback,
        ),
      ForumAccountStatus.directLoginUnavailable => (
          '暂不可登录',
          colors.error,
          false,
          _showDirectForumUnavailableHint,
        ),
    };
    return _accountTile(
      context,
      icon: Icons.forum_outlined,
      title: '乐乎账户',
      description: '用于访问上海大学校内论坛',
      statusLabel: label,
      statusColor: color,
      busy: busy,
      onTap: onTap,
    );
  }

  Widget _accountTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    String? statusLabel,
    Color? statusColor,
    bool busy = false,
    required VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 4, 20),
          child: Row(
            children: [
              Icon(icon, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (statusLabel != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor ?? colors.primary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ] else if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(
      BuildContext context, String title, String? subtitle, List<Widget> items,
      {Widget? pageFooter}) {
    return _pageLayout(
      context,
      header: _pageHeader(context, title: title, subtitle: subtitle),
      bottomChildren: items,
      pageFooter: pageFooter,
    );
  }

  Widget _pageLayout(
    BuildContext context, {
    required Widget header,
    required List<Widget> bottomChildren,
    Widget? pageFooter,
    double headerSpacing = 32,
  }) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                SizedBox(height: headerSpacing),
                ...bottomChildren,
              ],
            ),
          ),
        ),
        if (pageFooter != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: pageFooter,
          ),
      ],
    );
  }

  Widget _pageHeader(
    BuildContext context, {
    required String title,
    String? subtitle,
    EdgeInsets subtitlePadding = EdgeInsets.zero,
  }) {
    return Center(
      child: Column(
        children: [
          Image.asset(
            'assets/images/icon_clear_blue.png',
            width: 88,
            height: 88,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: subtitlePadding,
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _terms(BuildContext context) => Center(
        child: Text.rich(
          TextSpan(
            text: '继续即表示您已同意我们的',
            children: [
              _link(context, '使用条款', 'https://shuyo.work/doc/terms.html'),
              const TextSpan(text: '和'),
              _link(context, '隐私政策', 'https://shuyo.work/doc/privacy.html'),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      );

  InlineSpan _link(BuildContext context, String label, String url) => WidgetSpan(
        child: GestureDetector(
          onTap: () => launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );

  Widget _feature(
    IconData icon,
    String title,
    String description,
  ) =>
      Padding(
        padding: const EdgeInsets.only(left: 32, bottom: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 26),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      description,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
