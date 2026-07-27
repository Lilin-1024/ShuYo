import 'dart:async';

import 'package:flutter/material.dart';

import '../core/client_app_info.dart';
import '../core/forum_url_resolver.dart';
import '../data/repositories/forum_repository.dart';
import '../data/services/client_settings_service.dart';
import '../features/webview/forum_webvpn_preloader.dart';
import 'app_shell.dart';
import '../shared/theme/lehu_theme.dart';

class LehuApp extends StatefulWidget {
  const LehuApp({super.key});

  @override
  State<LehuApp> createState() => _LehuAppState();
}

class _LehuAppState extends State<LehuApp> with WidgetsBindingObserver {
  final _settingsService = ClientSettingsService();
  late final Future<_StartupData> _startupFuture;
  ForumRepository? _startupRecoveredRepository;
  bool _startupWebVpnRecoveryDone = false;
  String _manualThemeId = LehuThemes.defaultId;
  bool _followSystemTheme = false;
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
          final repository = _startupRecoveredRepository ?? data.repository;
          if (!repository.isOnline &&
              data.autoUseWebVpnProxy &&
              !_startupWebVpnRecoveryDone) {
            return _StartupForumWebVpnRecovery(
              theme: theme,
              onFinished: _finishStartupWebVpnRecovery,
            );
          }
          return AppShell(
            repository: repository,
            reloadRepository: ForumRepositoryFactory.loadOnline,
            initialAutoUseWebVpnProxy: data.autoUseWebVpnProxy,
            selectedThemeId: theme.id,
            followSystemTheme: _followSystemTheme,
            onThemeChanged: _changeTheme,
            onFollowSystemThemeChanged: _changeFollowSystemTheme,
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
    await ClientAppInfo.load();
    final networkSettings = await _settingsService.loadNetworkSettings();
    ForumUrlResolver.configure(
      useWebVpn: networkSettings.autoUseWebVpnProxy,
    );
    final repository = await ForumRepositoryFactory.load();
    return _StartupData(
      repository: repository,
      autoUseWebVpnProxy: networkSettings.autoUseWebVpnProxy,
    );
  }

  void _finishStartupWebVpnRecovery(ForumRepository? repository) {
    if (!mounted || _startupWebVpnRecoveryDone) {
      return;
    }
    setState(() {
      _startupWebVpnRecoveryDone = true;
      _startupRecoveredRepository = repository;
    });
  }

  Future<void> _loadTheme() async {
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

class _StartupData {
  const _StartupData({
    required this.repository,
    required this.autoUseWebVpnProxy,
  });

  final ForumRepository repository;
  final bool autoUseWebVpnProxy;
}

class _StartupForumWebVpnRecovery extends StatefulWidget {
  const _StartupForumWebVpnRecovery({
    required this.theme,
    required this.onFinished,
  });

  final LehuThemeSpec theme;
  final ValueChanged<ForumRepository?> onFinished;

  @override
  State<_StartupForumWebVpnRecovery> createState() =>
      _StartupForumWebVpnRecoveryState();
}

class _StartupForumWebVpnRecoveryState
    extends State<_StartupForumWebVpnRecovery> {
  Timer? _preloadTimeout;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _preloadTimeout = Timer(
      const Duration(seconds: 30),
      () => _finish(null),
    );
  }

  @override
  void dispose() {
    _preloadTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _StartupLoading(theme: widget.theme),
        Positioned(
          left: 0,
          top: 0,
          child: ForumWebVpnPreloader(onComplete: _handlePreloadComplete),
        ),
      ],
    );
  }

  Future<void> _handlePreloadComplete(bool success) async {
    if (_finished) {
      return;
    }
    _preloadTimeout?.cancel();
    if (!success) {
      _finish(null);
      return;
    }
    try {
      final repository = await ForumRepositoryFactory.loadOnline().timeout(
        const Duration(seconds: 12),
      );
      _finish(repository);
    } on Object {
      _finish(null);
    }
  }

  void _finish(ForumRepository? repository) {
    if (_finished) {
      return;
    }
    _finished = true;
    _preloadTimeout?.cancel();
    if (mounted) {
      widget.onFinished(repository);
    }
  }
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
