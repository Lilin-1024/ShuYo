import 'package:flutter/material.dart';

import '../core/client_app_info.dart';
import '../data/repositories/forum_repository.dart';
import '../data/services/client_settings_service.dart';
import 'app_shell.dart';
import '../shared/theme/lehu_theme.dart';

class LehuApp extends StatefulWidget {
  const LehuApp({super.key});

  @override
  State<LehuApp> createState() => _LehuAppState();
}

class _LehuAppState extends State<LehuApp> {
  final _settingsService = ClientSettingsService();
  late final Future<ForumRepository> _startupFuture;
  LehuThemeSpec _theme = LehuThemes.byId(LehuThemes.defaultId);

  @override
  void initState() {
    super.initState();
    _startupFuture = _loadStartup();
    _loadTheme();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '乐乎',
      debugShowCheckedModeBanner: false,
      theme: _theme.themeData(),
      home: FutureBuilder<ForumRepository>(
        future: _startupFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StartupError(error: snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const _StartupLoading();
          }
          return AppShell(
            repository: snapshot.data!,
            reloadRepository: ForumRepositoryFactory.loadOnline,
            selectedThemeId: _theme.id,
            onThemeChanged: _changeTheme,
          );
        },
      ),
    );
  }

  Future<ForumRepository> _loadStartup() async {
    await ClientAppInfo.load();
    return ForumRepositoryFactory.load();
  }

  Future<void> _loadTheme() async {
    final themeId = await _settingsService.loadThemeId();
    if (!mounted) {
      return;
    }
    setState(() => _theme = LehuThemes.byId(themeId));
  }

  Future<void> _changeTheme(String themeId) async {
    final theme = LehuThemes.byId(themeId);
    await _settingsService.saveThemeId(theme.id);
    if (mounted) {
      setState(() => _theme = theme);
    }
  }
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
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
