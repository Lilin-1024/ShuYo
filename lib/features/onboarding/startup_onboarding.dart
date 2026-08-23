import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/client_settings_service.dart';
import '../auth/native_login_page.dart';

class StartupOnboardingController extends ChangeNotifier {
  bool _academicLoggedIn = false;
  bool _forumLoggedIn = false;

  bool get academicLoggedIn => _academicLoggedIn;
  bool get forumLoggedIn => _forumLoggedIn;

  void openAccountManager({
    required bool academicLoggedIn,
    required bool forumLoggedIn,
  }) {
    _academicLoggedIn = academicLoggedIn;
    _forumLoggedIn = forumLoggedIn;
    notifyListeners();
  }
}

class StartupOnboarding extends StatefulWidget {
  const StartupOnboarding({
    super.key,
    required this.child,
    required this.initiallyCompleted,
    required this.initialAcademicLoggedIn,
    required this.initialForumLoggedIn,
    required this.onAcademicLoginCompleted,
    required this.onForumLoginCompleted,
    required this.controller,
    this.settingsService,
  });

  final Widget child;
  final bool initiallyCompleted;
  final bool initialAcademicLoggedIn;
  final bool initialForumLoggedIn;
  final VoidCallback onAcademicLoginCompleted;
  final VoidCallback onForumLoginCompleted;
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
  late bool _academicLoggedIn = widget.initialAcademicLoggedIn;
  late bool _forumLoggedIn = widget.initialForumLoggedIn;

  @override
  void initState() {
    super.initState();
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
    widget.controller.addListener(_openAccountManager);
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
      oldWidget.controller.removeListener(_openAccountManager);
      widget.controller.addListener(_openAccountManager);
    }
    if (widget.initialAcademicLoggedIn != oldWidget.initialAcademicLoggedIn) {
      _academicLoggedIn = widget.initialAcademicLoggedIn;
    }
    if (widget.initialForumLoggedIn != oldWidget.initialForumLoggedIn) {
      _forumLoggedIn = widget.initialForumLoggedIn;
    }
  }

  void _openAccountManager() {
    if (!mounted) return;
    setState(() {
      _visible = true;
      _accountManagerMode = true;
      _page = 2;
      _academicLoggedIn = widget.controller.academicLoggedIn;
      _forumLoggedIn = widget.controller.forumLoggedIn;
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
    if (_academicLoggedIn && _forumLoggedIn) await _complete();
  }

  Future<void> _openAcademicLogin() async {
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NativeLoginPage()),
    );
    if (loggedIn != true || !mounted) return;
    setState(() => _academicLoggedIn = true);
    widget.onAcademicLoginCompleted();
  }

  Future<void> _openForumLogin() async {
    if (!_academicLoggedIn) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('请先登录上大校园账户')),
        );
      return;
    }
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NativeLoginPage.forum()),
    );
    if (loggedIn != true || !mounted) return;
    setState(() => _forumLoggedIn = true);
    widget.onForumLoginCompleted();
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

  Future<void> _hidePanel() async {
    if (!_visible) return;
    await _panelAnimationController.reverse();
    if (mounted) setState(() => _visible = false);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_openAccountManager);
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
                dismissible: false,
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
        !_forumLoggedIn;
    final showFooter = _accountManagerMode ||
        _page < 2 ||
        (_academicLoggedIn && _forumLoggedIn);
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
              SizedBox(
                width: double.infinity,
                height: 48,
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
                        child: IconButton(
                          tooltip: '返回上一页',
                          onPressed: _goBack,
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                    if (canSkip)
                      Positioned(
                        right: 12,
                        child: TextButton(
                          onPressed: _complete,
                          child: const Text('跳过'),
                        ),
                      ),
                    if (_accountManagerMode)
                      Positioned(
                        right: 8,
                        child: IconButton(
                          tooltip: '关闭',
                          onPressed: _closeAccountManager,
                          icon: const Icon(Icons.close),
                        ),
                      ),
                  ],
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
                height: 112,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                  child: showFooter
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (_page == 0) ...[
                              _terms(context),
                              const SizedBox(height: 8),
                            ],
                            FilledButton(
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
                            ),
                          ],
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
        '欢迎使用 ShuYo',
        '让校园生活更简单',
        [
          _feature(Icons.calendar_month, '课表与空教室', '快速查看课程安排和可用教室'),
          _feature(Icons.forum_outlined, '乐乎论坛', '浏览校园动态，参与讨论'),
          _feature(Icons.notifications_none, '重要提醒', '不错过课程和校园通知'),
        ],
      );

  Widget _notifications(BuildContext context) => _content(
        context,
        '开启推送通知',
        '用于课程提醒',
        [
          _feature(
            Icons.notifications_active_outlined,
            'ShuYo会发送上课提醒，请在下一步中授予我们推送通知权限',
            '你可以随时在系统设置中关闭通知',
          ),
        ],
      );

  Widget _login(BuildContext context) => _pageLayout(
        context,
        header: _pageHeader(
          context,
          title: '登录',
          subtitle: 'ShuYo 使用双账户系统，包括上大校园账户和乐乎论坛账户。',
        ),
        bottomChildren: [
          _accountTile(
            context,
            icon: Icons.school_outlined,
            title: '上大校园账户',
            description: '用于访问课程表、教室查询等校园服务',
            loggedIn: _academicLoggedIn,
            onTap: _academicLoggedIn ? null : _openAcademicLogin,
          ),
          _accountTile(
            context,
            icon: Icons.forum_outlined,
            title: '乐乎账户',
            description: '用于访问上海大学校内论坛',
            loggedIn: _forumLoggedIn,
            onTap: _forumLoggedIn ? null : _openForumLogin,
          ),
        ],
      );

  Widget _accountTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required bool loggedIn,
    required VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
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
                        if (loggedIn) ...[
                          const SizedBox(width: 8),
                          Text(
                            '已登录',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
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
              if (onTap != null) ...[
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
    BuildContext context,
    String title,
    String subtitle,
    List<Widget> items,
  ) {
    return _pageLayout(
      context,
      header: _pageHeader(context, title: title, subtitle: subtitle),
      bottomChildren: items,
    );
  }

  Widget _pageLayout(
    BuildContext context, {
    required Widget header,
    required List<Widget> bottomChildren,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 32),
          ...bottomChildren,
        ],
      ),
    );
  }

  Widget _pageHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
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
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _terms(BuildContext context) => Center(
        child: Text.rich(
          TextSpan(
            text: '继续即表示您已同意我们的',
            children: [
              _link(context, '使用条款'),
              const TextSpan(text: '和'),
              _link(context, '隐私政策'),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      );

  InlineSpan _link(BuildContext context, String label) => WidgetSpan(
        child: GestureDetector(
          onTap: () => launchUrl(
            Uri.parse('https://example.com/$label'),
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

  Widget _feature(IconData icon, String title, String description) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
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
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(description, style: const TextStyle(height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
