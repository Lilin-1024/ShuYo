import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/client_app_info.dart';
import '../../data/repositories/client_backend_repository.dart';
import '../../data/services/academic_schedule_notification_service.dart';
import '../../data/services/client_settings_service.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/widgets/client_update_prompt.dart';
import '../../shared/widgets/empty_state.dart';
import 'client_feedback_page.dart';

class ClientSettingsPage extends StatelessWidget {
  const ClientSettingsPage({
    super.key,
    required this.settingsService,
    required this.scheduleNotificationService,
    required this.backendRepository,
    required this.selectedThemeId,
    required this.onThemeChanged,
    this.isOnline = false,
    this.onLogout,
  });

  final ClientSettingsService settingsService;
  final AcademicScheduleNotificationService scheduleNotificationService;
  final ClientBackendRepository backendRepository;
  final String selectedThemeId;
  final Future<void> Function(String themeId) onThemeChanged;
  final bool isOnline;
  final Future<void> Function()? onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _SettingsRow(
            title: '通知设置',
            onTap: () => Navigator.of(context).push<void>(
              lehuRoute(
                builder: (context) => _NotificationSettingsPage(
                  settingsService: settingsService,
                  scheduleNotificationService: scheduleNotificationService,
                ),
              ),
            ),
          ),
          _SettingsRow(
            title: 'WebVPN代理',
            onTap: () => Navigator.of(context).push<void>(
              lehuRoute(
                builder: (context) => _NetworkSettingsPage(
                  settingsService: settingsService,
                ),
              ),
            ),
          ),
          _SettingsRow(
            title: '主题切换',
            onTap: () => Navigator.of(context).push<void>(
              lehuRoute(
                builder: (context) => _ThemeSettingsPage(
                  selectedThemeId: selectedThemeId,
                  onThemeChanged: onThemeChanged,
                ),
              ),
            ),
          ),
          _SettingsRow(
            title: '问题与反馈',
            onTap: () => Navigator.of(context).push<void>(
              lehuRoute(
                builder: (context) => ClientFeedbackPage(
                  repository: backendRepository,
                ),
              ),
            ),
          ),
          _SettingsRow(
            title: '关于客户端',
            onTap: () => Navigator.of(context).push<void>(
              lehuRoute(
                builder: (context) => const _AboutClientPage(),
              ),
            ),
          ),
          _SettingsRow(
            title: '检查更新',
            onTap: () => _checkForUpdate(context),
          ),
          if (isOnline && onLogout != null) ...[
            const SizedBox(height: 14),
            _SettingsRow(
              title: '退出登录',
              onTap: () => _confirmLogout(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    try {
      final update = await backendRepository.checkForUpdate(forceRefresh: true);
      if (!context.mounted) {
        return;
      }
      if (update == null) {
        _showSnack(context, '已是最新版本');
        return;
      }
      final openDownload = await showClientUpdatePrompt(
        context,
        update: update,
      );
      if (!context.mounted || !openDownload || !update.hasDownloadUrl) {
        return;
      }
      await _openExternalDownload(context, update.downloadUrl);
    } on Object catch (error) {
      if (context.mounted) {
        _showSnack(context, '检查更新失败：$error');
      }
    }
  }

  Future<void> _openExternalDownload(BuildContext context, String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      _showSnack(context, '下载链接无效');
      return;
    }
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      _showSnack(context, '无法打开下载链接');
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('退出登录'),
          content: const Text('退出后论坛相关功能需要重新登录。'),
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
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await onLogout?.call();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _AboutClientPage extends StatelessWidget {
  const _AboutClientPage();

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Scaffold(
      appBar: AppBar(title: const Text('关于ShuYo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            'ShuYo客户端',
            style: LehuTextStyles.pageTitle(color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            '版本 ${ClientAppInfo.version}',
            style: LehuTextStyles.meta(color: colors.textMuted),
          ),
          const SizedBox(height: 22),
          _AboutSection(
            title: '简介',
            body:
                '这里应该写一些介绍，但是我还没有想好写些什么。\n\n总之，如果使用当中出现问题，或是你希望有些新的功能，可以通过“问题与反馈”提交给我。',
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: LehuTextStyles.sectionTitle(color: colors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: LehuTextStyles.body(
              color: colors.textSecondary,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSettingsPage extends StatefulWidget {
  const _ThemeSettingsPage({
    required this.selectedThemeId,
    required this.onThemeChanged,
  });

  final String selectedThemeId;
  final Future<void> Function(String themeId) onThemeChanged;

  @override
  State<_ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<_ThemeSettingsPage> {
  late String _selectedThemeId;
  String? _savingThemeId;

  @override
  void initState() {
    super.initState();
    _selectedThemeId = widget.selectedThemeId;
  }

  @override
  void didUpdateWidget(covariant _ThemeSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedThemeId != oldWidget.selectedThemeId &&
        _savingThemeId == null) {
      _selectedThemeId = widget.selectedThemeId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Scaffold(
      appBar: AppBar(title: const Text('主题切换')),
      body: ListView.separated(
        itemCount: LehuThemes.all.length,
        separatorBuilder: (context, index) => Divider(color: colors.border),
        itemBuilder: (context, index) {
          final theme = LehuThemes.all[index];
          final selected = theme.id == _selectedThemeId;
          return ListTile(
            selected: selected,
            selectedColor: colors.textPrimary,
            title: Text(
              theme.name,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            trailing: _ThemeSwatches(
              theme: theme,
              selected: selected,
              saving: _savingThemeId == theme.id,
            ),
            onTap: _savingThemeId == null ? () => _selectTheme(theme) : null,
          );
        },
      ),
    );
  }

  Future<void> _selectTheme(LehuThemeSpec theme) async {
    if (_selectedThemeId == theme.id || _savingThemeId != null) {
      return;
    }
    setState(() {
      _selectedThemeId = theme.id;
      _savingThemeId = theme.id;
    });
    try {
      await widget.onThemeChanged(theme.id);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(context, '主题保存失败：$error');
      setState(() => _selectedThemeId = widget.selectedThemeId);
    } finally {
      if (mounted) {
        setState(() => _savingThemeId = null);
      }
    }
  }
}

class _ThemeSwatches extends StatelessWidget {
  const _ThemeSwatches({
    required this.theme,
    required this.selected,
    required this.saving,
  });

  final LehuThemeSpec theme;
  final bool selected;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return SizedBox(
      width: 126,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (saving)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (selected)
            Icon(Icons.check, size: 20, color: colors.accent)
          else
            const SizedBox(width: 20),
          const SizedBox(width: 12),
          for (final color in theme.previewColors) ...[
            _ThemeSwatch(color: color),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: 16),
    );
  }
}

class _NetworkSettingsPage extends StatefulWidget {
  const _NetworkSettingsPage({
    required this.settingsService,
  });

  final ClientSettingsService settingsService;

  @override
  State<_NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<_NetworkSettingsPage> {
  late Future<ClientNetworkSettings> _future;
  ClientNetworkSettings? _settings;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebVPN代理')),
      body: FutureBuilder<ClientNetworkSettings>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.wifi_off,
              title: '设置加载失败',
              message: snapshot.error.toString(),
              action: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _future = _loadSettings();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            );
          }
          final settings = _settings ?? snapshot.data!;
          return ListView(
            children: [
              _SettingsSwitchRow(
                title: '自动使用WebVPN代理',
                value: settings.autoUseWebVpnProxy,
                enabled: true,
                onChanged: (value) => _save(
                  settings.copyWith(autoUseWebVpnProxy: value),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<ClientNetworkSettings> _loadSettings() async {
    final settings = await widget.settingsService.loadNetworkSettings();
    _settings = settings;
    return settings;
  }

  Future<void> _save(ClientNetworkSettings settings) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _settings = settings;
    });
    try {
      final saved = await widget.settingsService.saveNetworkSettings(settings);
      if (!mounted) {
        return;
      }
      setState(() => _settings = saved);
    } on Object catch (error) {
      if (mounted) {
        _showSnack(context, '设置保存失败：$error');
        setState(() {
          _future = _loadSettings();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _NotificationSettingsPage extends StatefulWidget {
  const _NotificationSettingsPage({
    required this.settingsService,
    required this.scheduleNotificationService,
  });

  final ClientSettingsService settingsService;
  final AcademicScheduleNotificationService scheduleNotificationService;

  @override
  State<_NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<_NotificationSettingsPage> {
  late Future<ClientNotificationSettings> _future;
  ClientNotificationSettings? _settings;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知设置')),
      body: FutureBuilder<ClientNotificationSettings>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.notifications_off,
              title: '设置加载失败',
              message: snapshot.error.toString(),
              action: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _future = _loadSettings();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            );
          }
          final settings = _settings ?? snapshot.data!;
          return ListView(
            children: [
              _SettingsSwitchRow(
                title: '课表提醒',
                value: settings.scheduleEnabled,
                enabled: true,
                onChanged: (value) => _save(
                  settings.copyWith(scheduleEnabled: value),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<ClientNotificationSettings> _loadSettings() async {
    final settings = await widget.settingsService.loadNotificationSettings();
    _settings = settings;
    return settings;
  }

  Future<void> _save(ClientNotificationSettings settings) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _settings = settings;
    });
    try {
      final saved =
          await widget.settingsService.saveNotificationSettings(settings);
      await widget.scheduleNotificationService.syncScheduleReminders(
        requestPermission: saved.scheduleEnabled,
      );
      if (!mounted) {
        return;
      }
      setState(() => _settings = saved);
    } on Object catch (error) {
      if (mounted) {
        _showSnack(context, '设置保存失败：$error');
        setState(() {
          _future = _loadSettings();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.onTap,
  });

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? colors.textPrimary : colors.textMuted,
        ),
      ),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
