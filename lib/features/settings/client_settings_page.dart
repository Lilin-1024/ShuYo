import 'package:flutter/material.dart';

import '../../data/services/academic_schedule_notification_service.dart';
import '../../data/services/client_settings_service.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/widgets/empty_state.dart';

class ClientSettingsPage extends StatelessWidget {
  const ClientSettingsPage({
    super.key,
    required this.settingsService,
    required this.scheduleNotificationService,
    this.isOnline = false,
    this.onLogout,
  });

  final ClientSettingsService settingsService;
  final AcademicScheduleNotificationService scheduleNotificationService;
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
            onTap: () => _showSnack(context, '主题切换后续接入'),
          ),
          _SettingsRow(
            title: '功能反馈',
            onTap: () => _showSnack(context, '功能反馈后续接入'),
          ),
          if (isOnline && onLogout != null)
            _SettingsRow(
              title: '退出登录',
              onTap: () => _confirmLogout(context),
            ),
          _SettingsRow(
            title: '关于客户端',
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
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

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: '客户端',
      applicationVersion: '0.1.0',
      applicationLegalese: '用于浏览乐乎与校园服务的非官方客户端。',
      children: const [
        SizedBox(height: 8),
        Text('名称、主题和更多说明会在后续版本中完善。'),
      ],
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
                onPressed: () => setState(() => _future = _loadSettings()),
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
        setState(() => _future = _loadSettings());
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
                onPressed: () => setState(() => _future = _loadSettings()),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            );
          }
          final settings = _settings ?? snapshot.data!;
          return ListView(
            children: [
              _SettingsSwitchRow(
                title: '客户端通知',
                value: settings.enabled,
                enabled: true,
                onChanged: (value) => _save(
                  settings.copyWith(enabled: value),
                ),
              ),
              _SettingsSwitchRow(
                title: '课表通知',
                value: settings.scheduleEnabled,
                enabled: settings.enabled,
                onChanged: (value) => _save(
                  settings.copyWith(scheduleEnabled: value),
                ),
              ),
              _SettingsSwitchRow(
                title: '论坛消息通知',
                value: settings.forumEnabled,
                enabled: settings.enabled,
                onChanged: (value) => _save(
                  settings.copyWith(forumEnabled: value),
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
        requestPermission: saved.enabled && saved.scheduleEnabled,
      );
      if (!mounted) {
        return;
      }
      setState(() => _settings = saved);
    } on Object catch (error) {
      if (mounted) {
        _showSnack(context, '设置保存失败：$error');
        setState(() => _future = _loadSettings());
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
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? null : const Color(0xFF777777),
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
