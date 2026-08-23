import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/client_settings_service.dart';
import '../auth/native_login_page.dart';

class StartupOnboarding extends StatefulWidget {
  const StartupOnboarding({
    super.key,
    required this.child,
    required this.initiallyCompleted,
    required this.initialAcademicLoggedIn,
    required this.initialForumLoggedIn,
    required this.onAcademicLoginCompleted,
    this.settingsService,
  });

  final Widget child;
  final bool initiallyCompleted;
  final bool initialAcademicLoggedIn;
  final bool initialForumLoggedIn;
  final VoidCallback onAcademicLoginCompleted;
  final ClientSettingsService? settingsService;

  @override
  State<StartupOnboarding> createState() => _StartupOnboardingState();
}

class _StartupOnboardingState extends State<StartupOnboarding> {
  final _controller = PageController();
  late final ClientSettingsService _settingsService =
      widget.settingsService ?? ClientSettingsService();
  int _page = 0;
  late bool _visible = !widget.initiallyCompleted;
  late bool _academicLoggedIn = widget.initialAcademicLoggedIn;
  late bool _forumLoggedIn = widget.initialForumLoggedIn;

  @override
  void didUpdateWidget(covariant StartupOnboarding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAcademicLoggedIn != oldWidget.initialAcademicLoggedIn) {
      _academicLoggedIn = widget.initialAcademicLoggedIn;
    }
    if (widget.initialForumLoggedIn != oldWidget.initialForumLoggedIn) {
      _forumLoggedIn = widget.initialForumLoggedIn;
    }
  }

  Future<void> _continue() async {
    if (_page == 1) await _requestNotifications();
    if (!mounted) return;
    if (_page < 2) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      if (mounted) setState(() => _page++);
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

  void _openForumPlaceholder() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('乐乎论坛原生登录暂未接入')),
      );
  }

  Future<void> _complete() async {
    await _settingsService.saveStartupOnboardingCompleted(true);
    if (mounted) setState(() => _visible = false);
  }

  @override
  void dispose() {
    _controller.dispose();
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
            child: ModalBarrier(
              color: Colors.black.withValues(alpha: .32),
              dismissible: false,
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: _panel(context)),
        ],
      ],
    );
  }

  Widget _panel(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canSkip = _page == 2 && _academicLoggedIn && !_forumLoggedIn;
    final showFooter = _page < 2 || (_academicLoggedIn && _forumLoggedIn);
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
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
                    if (canSkip)
                      Positioned(
                        right: 12,
                        child: TextButton(
                          onPressed: _complete,
                          child: const Text('跳过'),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _welcome(context),
                    _notifications(context),
                    _login(context),
                  ],
                ),
              ),
              if (showFooter)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                  child: FilledButton(
                    onPressed: _continue,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(_page == 2 ? '开始使用' : '继续'),
                  ),
                )
              else
                const SizedBox(height: 18),
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
        showTerms: true,
      );

  Widget _notifications(BuildContext context) => _content(
        context,
        '开启通知',
        '用于提醒课表、课程变更和重要消息',
        [
          _feature(
            Icons.notifications_active_outlined,
            '及时收到提醒',
            '你可以随时在系统设置中关闭通知',
          ),
        ],
      );

  Widget _login(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/icon_clear_blue.png',
                    width: 64,
                    height: 64,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '登录',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'ShuYo 使用双账户系统，包括上大校园账户和乐乎论坛账户。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _accountTile(
              context,
              icon: Icons.school_outlined,
              title: '上大校园账户',
              description: '用于访问课程表、教室查询等校园服务',
              loggedIn: _academicLoggedIn,
              onTap: _openAcademicLogin,
            ),
            _accountTile(
              context,
              icon: Icons.forum_outlined,
              title: '乐乎账户',
              description: '用于访问上海大学校内论坛，首次使用需注册',
              loggedIn: _forumLoggedIn,
              onTap: _forumLoggedIn ? null : _openForumPlaceholder,
            ),
          ],
        ),
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
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 28),
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
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
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
    List<Widget> items, {
    bool showTerms = false,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Image.asset(
                  'assets/images/icon_clear_blue.png',
                  width: 72,
                  height: 72,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 28),
          ...items,
          if (showTerms)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(
                child: Text.rich(
                  TextSpan(
                    text: '使用本app即表示您已同意我们的',
                    children: [
                      _link(context, '使用条款'),
                      const TextSpan(text: '和'),
                      _link(context, '隐私政策'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
}
