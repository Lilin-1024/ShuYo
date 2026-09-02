import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/client_app_info.dart';
import '../../core/client_update_policy.dart';
import '../../data/repositories/client_backend_repository.dart';
import '../../data/services/academic_schedule_notification_service.dart';
import '../../data/services/app_store_version_service.dart';
import '../../data/services/client_settings_service.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
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
    required this.followSystemTheme,
    required this.onThemeChanged,
    required this.onFollowSystemThemeChanged,
    this.isOnline = false,
    this.loadForumCacheSize,
    this.onClearForumCache,
    this.isDemo = false,
    this.onExitDemo,
  });

  final ClientSettingsService settingsService;
  final AcademicScheduleNotificationService scheduleNotificationService;
  final ClientBackendRepository backendRepository;
  final String selectedThemeId;
  final bool followSystemTheme;
  final Future<void> Function(String themeId) onThemeChanged;
  final Future<void> Function(bool enabled) onFollowSystemThemeChanged;
  final bool isOnline;
  final Future<int> Function()? loadForumCacheSize;
  final Future<int> Function()? onClearForumCache;
  final bool isDemo;
  final Future<void> Function()? onExitDemo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _SettingsRow(
            title: '通知设置',
            onTap: () => Navigator.of(context).push<void>(
              shuyoRoute(
                builder: (context) => _NotificationSettingsPage(
                  settingsService: settingsService,
                  scheduleNotificationService: scheduleNotificationService,
                ),
              ),
            ),
          ),
          if (!isDemo)
            _SettingsRow(
              title: 'WebVPN代理',
              onTap: () => Navigator.of(context).push<void>(
                shuyoRoute(
                  builder: (context) => _NetworkSettingsPage(
                    settingsService: settingsService,
                  ),
                ),
              ),
            ),
          _SettingsRow(
            title: '主题切换',
            onTap: () => Navigator.of(context).push<void>(
              shuyoRoute(
                builder: (context) => _ThemeSettingsPage(
                  selectedThemeId: selectedThemeId,
                  followSystemTheme: followSystemTheme,
                  onThemeChanged: onThemeChanged,
                  onFollowSystemThemeChanged: onFollowSystemThemeChanged,
                ),
              ),
            ),
          ),
          if (!isDemo)
            _SettingsRow(
              title: '问题与反馈',
              onTap: () => Navigator.of(context).push<void>(
                shuyoRoute(
                  builder: (context) => ClientFeedbackPage(
                    repository: backendRepository,
                  ),
                ),
              ),
            ),
          _SettingsRow(
            title: '关于ShuYo',
            onTap: () => Navigator.of(context).push<void>(
              shuyoRoute(
                builder: (context) => const _AboutClientPage(),
              ),
            ),
          ),
          if (!isDemo)
            _SettingsRow(
              title: '检查更新',
              onTap: () => _checkForUpdate(context),
            ),
          if (isDemo && onExitDemo != null)
            _SettingsRow(
              title: '退出演示',
              onTap: () => _exitDemo(context),
            ),
          const SizedBox(height: 14),
          _ForumCacheRow(
            loadSize: loadForumCacheSize,
            onClear: onClearForumCache,
          ),
        ],
      ),
    );
  }

  Future<void> _exitDemo(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('退出演示模式？'),
            content: const Text('退出后将返回正常登录流程，并清除本地演示数据。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('退出演示'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await onExitDemo?.call();
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    try {
      if (ClientUpdatePolicy.source == ClientUpdateSource.appStore) {
        await _checkAppStoreForUpdate(context);
        return;
      }
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
    } on AppStoreVersionUnavailableException catch (error) {
      if (context.mounted) {
        _showSnack(context, error.message);
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showSnack(context, '检查更新失败：$error');
      }
    }
  }

  Future<void> _checkAppStoreForUpdate(BuildContext context) async {
    final update = await AppStoreVersionService().checkForUpdate();
    if (!context.mounted) {
      return;
    }
    if (update == null) {
      _showSnack(context, '已是最新版本');
      return;
    }
    final openAppStore = await showAppStoreUpdatePrompt(
      context,
      update: update,
    );
    if (!context.mounted || !openAppStore) {
      return;
    }
    await _openExternalDownload(context, update.productUrl);
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
}

class _ForumCacheRow extends StatefulWidget {
  const _ForumCacheRow({required this.loadSize, required this.onClear});

  final Future<int> Function()? loadSize;
  final Future<int> Function()? onClear;

  @override
  State<_ForumCacheRow> createState() => _ForumCacheRowState();
}

class _ForumCacheRowState extends State<_ForumCacheRow> {
  late Future<int> _sizeFuture;

  @override
  void initState() {
    super.initState();
    _sizeFuture = _loadSize();
  }

  @override
  void didUpdateWidget(covariant _ForumCacheRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadSize != widget.loadSize) {
      _sizeFuture = _loadSize();
    }
  }

  Future<int> _loadSize() => widget.loadSize?.call() ?? Future<int>.value(0);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _sizeFuture,
      builder: (context, snapshot) {
        return _SettingsRow(
          title: '清除缓存',
          onTap: widget.onClear == null ? null : () => _confirm(context),
        );
      },
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final size = await _sizeFuture;
    if (!context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: Text(
          '当前占用 ${_formatBytes(size)}。清除后将删除已缓存的帖子、私信、个人资料数据和图片，但不会退出登录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final released = await widget.onClear?.call() ?? 0;
    if (context.mounted) {
      setState(() => _sizeFuture = _loadSize());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已释放 ${_formatBytes(released)}')),
      );
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _AboutClientPage extends StatelessWidget {
  const _AboutClientPage();

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Scaffold(
      appBar: AppBar(title: const Text('关于ShuYo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            '关于ShuYo',
            style: ShuYoTextStyles.pageTitle(color: colors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            '版本 ${ClientAppInfo.version}',
            style: ShuYoTextStyles.meta(color: colors.textMuted),
          ),
          const SizedBox(height: 22),
          _AboutSection(
            title: '简介',
            body:
                '本应用是由学生开发的非官方开源工具，与上海大学、上海大学信息办无关，不属于官方软件。\n\n本应用仅作信息聚合展示。论坛相关功能遵守校内论坛的管理规则，用户在客户端产生的论坛内容，受论坛原有审核与管理制度约束。\n\n如果在客户端使用过程中出现问题，或是你希望有些新的功能，请通过“问题与反馈”联系开发者。～(∠・ω< )⌒☆',
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
    final colors = context.shuyoColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: ShuYoTextStyles.sectionTitle(color: colors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: ShuYoTextStyles.body(
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
    required this.followSystemTheme,
    required this.onThemeChanged,
    required this.onFollowSystemThemeChanged,
  });

  final String selectedThemeId;
  final bool followSystemTheme;
  final Future<void> Function(String themeId) onThemeChanged;
  final Future<void> Function(bool enabled) onFollowSystemThemeChanged;

  @override
  State<_ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<_ThemeSettingsPage> {
  late String _selectedThemeId;
  late bool _followSystemTheme;
  String? _savingThemeId;
  bool _savingFollowSystemTheme = false;

  @override
  void initState() {
    super.initState();
    _selectedThemeId = widget.selectedThemeId;
    _followSystemTheme = widget.followSystemTheme;
  }

  @override
  void didUpdateWidget(covariant _ThemeSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedThemeId != oldWidget.selectedThemeId &&
        _savingThemeId == null) {
      _selectedThemeId = widget.selectedThemeId;
    }
    if (widget.followSystemTheme != oldWidget.followSystemTheme &&
        !_savingFollowSystemTheme) {
      _followSystemTheme = widget.followSystemTheme;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Scaffold(
      appBar: AppBar(title: const Text('主题切换')),
      body: ListView.separated(
        itemCount: ShuYoThemes.all.length + 1,
        separatorBuilder: (context, index) => Divider(color: colors.border),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _SettingsSwitchRow(
              title: '跟随系统',
              value: _followSystemTheme,
              enabled: _savingThemeId == null && !_savingFollowSystemTheme,
              onChanged: _toggleFollowSystemTheme,
            );
          }
          final theme = ShuYoThemes.all[index - 1];
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

  Future<void> _selectTheme(ShuYoThemeSpec theme) async {
    if ((!_followSystemTheme && _selectedThemeId == theme.id) ||
        _savingThemeId != null ||
        _savingFollowSystemTheme) {
      return;
    }
    setState(() {
      _selectedThemeId = theme.id;
      _followSystemTheme = false;
      _savingThemeId = theme.id;
    });
    try {
      await widget.onThemeChanged(theme.id);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(context, '主题保存失败：$error');
      setState(() {
        _selectedThemeId = widget.selectedThemeId;
        _followSystemTheme = widget.followSystemTheme;
      });
    } finally {
      if (mounted) {
        setState(() => _savingThemeId = null);
      }
    }
  }

  Future<void> _toggleFollowSystemTheme(bool enabled) async {
    if (_savingFollowSystemTheme || _savingThemeId != null) {
      return;
    }
    setState(() {
      _followSystemTheme = enabled;
      _savingFollowSystemTheme = true;
    });
    try {
      await widget.onFollowSystemThemeChanged(enabled);
      if (mounted && enabled) {
        final brightness = MediaQuery.platformBrightnessOf(context);
        setState(() {
          _selectedThemeId = ShuYoThemes.systemThemeIdFor(brightness);
        });
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(context, '主题保存失败：$error');
      setState(() {
        _followSystemTheme = widget.followSystemTheme;
        _selectedThemeId = widget.selectedThemeId;
      });
    } finally {
      if (mounted) {
        setState(() => _savingFollowSystemTheme = false);
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

  final ShuYoThemeSpec theme;
  final bool selected;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return SizedBox(
      width: 126,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (saving)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 3),
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
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 3));
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
                enabled: !_saving,
                onChanged: (value) => _handleChanged(settings, value),
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

  Future<void> _handleChanged(
    ClientNetworkSettings settings,
    bool value,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.iOS && !value) {
      _showSnack(context, '暂不支持，待后续版本接入');
      return;
    }
    await _save(settings.copyWith(autoUseWebVpnProxy: value));
  }

  Future<void> _save(ClientNetworkSettings settings) async {
    if (_saving) {
      return;
    }
    final current = _settings;
    if (current?.autoUseWebVpnProxy == true && !settings.autoUseWebVpnProxy) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('关闭 WebVPN 代理？'),
          content: const Text(
            '关闭后，校园和论坛链接将改为直连，并且需要重新登录。直连服务通常只能在校园网或学校 VPN 中访问。\n\n当前版本的直连原生登录尚待接入。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('仍然关闭'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
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

  bool _alarmsSupported = false;
  AcademicScheduleAlarmSettings? _alarmSettings;
  bool _savingAlarm = false;

  @override
  void initState() {
    super.initState();
    _future = _loadSettings();
    _loadAlarmState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知设置')),
      body: FutureBuilder<ClientNotificationSettings>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 3));
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
          final alarmSettings = _alarmSettings;
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
              if (_alarmsSupported && alarmSettings != null) ...[
                _SettingsSwitchRow(
                  title: '早课闹钟',
                  subtitle: '每天仅为上午最早的一节课设置闹钟',
                  value: alarmSettings.enabled,
                  enabled: !_savingAlarm,
                  onChanged: (value) => _saveAlarm(
                    alarmSettings.copyWith(enabled: value),
                    requestPermission: value,
                  ),
                ),
                if (alarmSettings.enabled)
                  ListTile(
                    title: const Text('闹钟提前时间'),
                    trailing: Text('${alarmSettings.leadMinutes} 分钟'),
                    enabled: !_savingAlarm,
                    onTap: _savingAlarm
                        ? null
                        : () => _editAlarmLeadMinutes(alarmSettings),
                  ),
              ],
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

  Future<void> _loadAlarmState() async {
    final supported =
        await widget.scheduleNotificationService.supportsEarlyClassAlarms();
    final settings = supported
        ? await widget.scheduleNotificationService.loadAlarmSettings()
        : const AcademicScheduleAlarmSettings(
            enabled: false,
            leadMinutes: 20,
          );
    if (!mounted) return;
    setState(() {
      _alarmsSupported = supported;
      _alarmSettings = settings;
    });
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

  Future<void> _saveAlarm(
    AcademicScheduleAlarmSettings settings, {
    bool requestPermission = false,
  }) async {
    if (_savingAlarm) {
      return;
    }
    setState(() {
      _savingAlarm = true;
      _alarmSettings = settings;
    });
    try {
      final saved =
          await widget.scheduleNotificationService.saveAlarmSettingsAndSync(
        settings,
        requestPermission: requestPermission,
      );
      if (!mounted) {
        return;
      }
      setState(() => _alarmSettings = saved);
      if (settings.enabled && !saved.enabled) {
        _showSnack(context, '未获得闹钟权限，请在系统设置中允许 ShuYo 使用闹钟');
      }
    } on Object catch (error) {
      if (mounted) {
        _showSnack(context, '闹钟设置保存失败：$error');
        _loadAlarmState();
      }
    } finally {
      if (mounted) {
        setState(() => _savingAlarm = false);
      }
    }
  }

  Future<void> _editAlarmLeadMinutes(
    AcademicScheduleAlarmSettings settings,
  ) async {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController(
      text: settings.leadMinutes.toString(),
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('设置闹钟提前时间'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '提前分钟数',
              helperText: '可设置 1–120 分钟',
            ),
            validator: (text) {
              final minutes = int.tryParse(text ?? '');
              if (minutes == null || minutes < 1 || minutes > 120) {
                return '请输入 1–120 之间的整数';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(int.parse(controller.text));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && mounted) {
      await _saveAlarm(settings.copyWith(leadMinutes: value));
    }
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.onTap,
  });

  final String title;
  final VoidCallback? onTap;

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
    this.subtitle,
  });

  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String? subtitle;


  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? colors.textPrimary : colors.textMuted,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(color: colors.textMuted),
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
