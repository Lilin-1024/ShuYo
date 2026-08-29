import 'package:flutter/material.dart';

import '../core/client_app_info.dart';
import '../core/forum_url_resolver.dart';
import '../data/repositories/forum_repository.dart';
import '../data/services/academic_auth_service.dart';
import '../data/services/app_data_migration_service.dart';
import '../data/services/client_settings_service.dart';
import 'app_shell.dart';
import '../features/onboarding/startup_onboarding.dart';
import '../shared/theme/lehu_theme.dart';

class LehuApp extends StatefulWidget {
  const LehuApp({super.key});

  @override
  State<LehuApp> createState() => _LehuAppState();
}

class _LehuAppState extends State<LehuApp> with WidgetsBindingObserver {
  final _settingsService = ClientSettingsService();
  final _dataMigrationService = AppDataMigrationService();
  final _onboardingController = StartupOnboardingController();
  late final Future<_StartupData> _startupFuture;
  String _manualThemeId = LehuThemes.defaultId;
  bool _followSystemTheme = false;
  int _academicLoginSignal = 0;
  int _forumLoginSignal = 0;
  Brightness _systemBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startupFuture = _loadStartup();
    _loadTheme();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _onboardingController.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (brightness == _systemBrightness) {
      return;
    }
    _systemBrightness = brightness;
    if (_followSystemTheme) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _effectiveTheme;
    return MaterialApp(
      title: 'ShuYo',
      debugShowCheckedModeBanner: false,
      theme: theme.themeData(),
      home: FutureBuilder<_StartupData>(
        future: _startupFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StartupError(error: snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return _StartupLoading(theme: theme);
          }
          final data = snapshot.data!;
          return StartupOnboarding(
            initiallyCompleted: data.onboardingCompleted,
            initialAcademicLoggedIn: data.hasAcademicSession,
            initialForumStatus: _forumAccountStatus(data.repository),
            onAcademicLoginCompleted: () {
              setState(() => _academicLoginSignal++);
            },
            onForumLoginCompleted: () {
              setState(() => _forumLoginSignal++);
            },
            controller: _onboardingController,
            child: AppShell(
              repository: data.repository,
              reloadRepository: ForumRepositoryFactory.loadOnline,
              initialAutoUseWebVpnProxy: data.autoUseWebVpnProxy,
              selectedThemeId: theme.id,
              followSystemTheme: _followSystemTheme,
              onThemeChanged: _changeTheme,
              onFollowSystemThemeChanged: _changeFollowSystemTheme,
              academicLoginSignal: _academicLoginSignal,
              forumLoginSignal: _forumLoginSignal,
              initialHasAcademicSession: data.hasAcademicSession,
              onboardingController: _onboardingController,
            ),
          );
        },
      ),
    );
  }

  LehuThemeSpec get _effectiveTheme {
    final themeId = _followSystemTheme
        ? LehuThemes.systemThemeIdFor(_systemBrightness)
        : _manualThemeId;
    return LehuThemes.byId(themeId);
  }

  Future<_StartupData> _loadStartup() async {
    // This must run before any repository/auth service reads local state.  The
    // migration intentionally resets this major release to a fresh install.
    await _dataMigrationService.migrateIfNeeded();
    await ClientAppInfo.load();
    final networkSettings = await _settingsService.loadNetworkSettings();
    ForumUrlResolver.configure(
      useWebVpn: networkSettings.autoUseWebVpnProxy,
    );
    final repository = await ForumRepositoryFactory.load();
    final hasAcademicSession = await AcademicAuthService().hasAcademicSession();
    final onboardingCompleted =
        await _settingsService.loadStartupOnboardingCompleted();
    return _StartupData(
      repository: repository,
      autoUseWebVpnProxy: networkSettings.autoUseWebVpnProxy,
      hasAcademicSession: hasAcademicSession,
      onboardingCompleted: onboardingCompleted,
    );
  }

  Future<void> _loadTheme() async {
    // Theme preferences are part of the data reset.  Wait for startup (and
    // therefore the migration) before reading them, otherwise this parallel
    // task could briefly restore a legacy theme after an upgrade.
    try {
      await _startupFuture;
    } on Object {
      return;
    }
    final themeId = await _settingsService.loadThemeId();
    final followSystemTheme = await _settingsService.loadFollowSystemTheme();
    if (!mounted) {
      return;
    }
    setState(() {
      _manualThemeId = LehuThemes.byId(themeId).id;
      _followSystemTheme = followSystemTheme;
    });
  }

  Future<void> _changeTheme(String themeId) async {
    final theme = LehuThemes.byId(themeId);
    await _settingsService.saveThemeId(theme.id);
    await _settingsService.saveFollowSystemTheme(false);
    if (mounted) {
      setState(() {
        _manualThemeId = theme.id;
        _followSystemTheme = false;
      });
    }
  }

  Future<void> _changeFollowSystemTheme(bool enabled) async {
    if (enabled) {
      await _settingsService.saveFollowSystemTheme(true);
      if (mounted) {
        setState(() => _followSystemTheme = true);
      }
      return;
    }

    final currentThemeId = _effectiveTheme.id;
    await _settingsService.saveThemeId(currentThemeId);
    await _settingsService.saveFollowSystemTheme(false);
    if (mounted) {
      setState(() {
        _manualThemeId = currentThemeId;
        _followSystemTheme = false;
      });
    }
  }
}

ForumAccountStatus _forumAccountStatus(ForumRepository repository) {
  if (!ForumUrlResolver.usesWebVpn && !repository.isOnline) {
    return ForumAccountStatus.directLoginUnavailable;
  }
  return switch (repository.connectionState) {
    ForumConnectionState.firstUse => ForumUrlResolver.usesWebVpn
        ? ForumAccountStatus.signedOut
        : ForumAccountStatus.directLoginUnavailable,
    ForumConnectionState.cachedOffline =>
      ForumAccountStatus.connectionUnavailable,
    ForumConnectionState.reauthenticationRequired =>
      ForumAccountStatus.reauthenticationRequired,
    ForumConnectionState.online => ForumAccountStatus.loggedIn,
  };
}

class _StartupData {
  const _StartupData({
    required this.repository,
    required this.autoUseWebVpnProxy,
    required this.hasAcademicSession,
    required this.onboardingCompleted,
  });

  final ForumRepository repository;
  final bool autoUseWebVpnProxy;
  final bool hasAcademicSession;
  final bool onboardingCompleted;
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading({required this.theme});

  final LehuThemeSpec theme;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: theme.colors.background,
      body: Center(
        child: Image.asset(
          _iconAsset,
          width: 112,
          height: 112,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }

  String get _iconAsset {
    if (theme.id == LehuThemes.defaultId) {
      return 'assets/images/icon_clear_blue.png';
    }
    if (theme.colors.brightness == Brightness.light) {
      return 'assets/images/icon_clear_black.png';
    }
    return 'assets/images/icon_clear.png';
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '启动失败',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(error, style: TextStyle(color: colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
