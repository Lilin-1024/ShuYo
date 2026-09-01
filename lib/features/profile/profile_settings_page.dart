import 'package:flutter/material.dart';

import '../../core/forum_url_resolver.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/local_image_picker.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/widgets/empty_state.dart';
import 'profile_header.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({
    super.key,
    required this.repository,
  });

  final ForumRepository repository;

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  final _bioController = TextEditingController();
  late Future<void> _loadFuture;
  UserProfile? _profile;
  String _profileBackgroundUrl = '';
  bool _hideProfile = false;
  bool _loadingAvatar = false;
  bool _uploadingBackground = false;
  bool _saving = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadProfile();
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving && !_loadingAvatar && !_uploadingBackground,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _saving || _loadingAvatar || _uploadingBackground) {
          return;
        }
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('个人资料设置'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
        body: FutureBuilder<void>(
          future: _loadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                  child: CircularProgressIndicator(strokeWidth: 3));
            }
            if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.manage_accounts_outlined,
                title: '资料加载失败',
                message: snapshot.error.toString(),
                action: TextButton.icon(
                  onPressed: () =>
                      setState(() => _loadFuture = _loadProfile(force: true)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              );
            }
            final profile = _profile;
            if (profile == null) {
              return const EmptyState(
                icon: Icons.person_outline,
                title: '没有资料',
                message: '论坛没有返回当前用户资料。',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
              children: [
                ProfileHeader(
                  profile: profile,
                  title: profile.username,
                  subtitle: _hideProfile ? '个人资料不公开' : '个人资料公开',
                  backgroundUrl: _absoluteUrl(_profileBackgroundUrl),
                ),
                const SizedBox(height: 18),
                _SectionTitle('头像'),
                const SizedBox(height: 8),
                _AvatarControls(
                  busy: _loadingAvatar,
                  onPickCustom: _pickCustomAvatar,
                  onUseSystem: _useSystemAvatar,
                ),
                const SizedBox(height: 22),
                _SectionTitle('个性签名'),
                const SizedBox(height: 8),
                TextField(
                  controller: _bioController,
                  minLines: 3,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '写一句个人介绍',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('公开个人资料'),
                  subtitle: const Text('关闭后隐藏个人资料'),
                  value: !_hideProfile,
                  onChanged: (value) {
                    setState(() => _hideProfile = !value);
                  },
                ),
                const SizedBox(height: 18),
                _SectionTitle('个人资料标题'),
                const SizedBox(height: 8),
                _BackgroundControls(
                  busy: _uploadingBackground,
                  onPick: _pickProfileBackground,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _loadProfile({bool force = false}) async {
    final profile =
        await widget.repository.fetchCurrentUserProfile(forceRefresh: force);
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = profile;
      _bioController.text = profile.bioRaw;
      _profileBackgroundUrl = profile.profileBackgroundUploadUrl;
      _hideProfile = profile.hideProfile;
    });
  }

  Future<void> _pickCustomAvatar() async {
    if (_loadingAvatar) {
      return;
    }
    setState(() => _loadingAvatar = true);
    try {
      final picked = await LocalImagePicker.pickImage();
      if (picked == null) {
        return;
      }
      final upload = await widget.repository.uploadProfileImage(
        picked,
        ProfileImageUploadType.avatar,
      );
      final profile = await widget.repository.useCustomAvatar(upload.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _changed = true;
      });
      _showSnack('头像已更新');
    } on Object catch (error) {
      if (mounted) {
        _showSnack('头像更新失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _loadingAvatar = false);
      }
    }
  }

  Future<void> _useSystemAvatar() async {
    if (_loadingAvatar) {
      return;
    }
    setState(() => _loadingAvatar = true);
    try {
      final profile = await widget.repository.useSystemAvatar();
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _changed = true;
      });
      _showSnack('已切换为系统头像');
    } on Object catch (error) {
      if (mounted) {
        _showSnack('头像更新失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _loadingAvatar = false);
      }
    }
  }

  Future<void> _pickProfileBackground() async {
    if (_uploadingBackground) {
      return;
    }
    setState(() => _uploadingBackground = true);
    try {
      final picked = await LocalImagePicker.pickImage();
      if (picked == null) {
        return;
      }
      final upload = await widget.repository.uploadProfileImage(
        picked,
        ProfileImageUploadType.profileBackground,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _profileBackgroundUrl = upload.url;
      });
      _showSnack('背景图已选择，保存后生效');
    } on Object catch (error) {
      if (mounted) {
        _showSnack('背景图上传失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingBackground = false);
      }
    }
  }

  Future<void> _save() async {
    final profile = _profile;
    if (profile == null || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await widget.repository.updateProfileSettings(
        ProfileSettingsDraft(
          bioRaw: _bioController.text.trim(),
          hideProfile: _hideProfile,
          profileBackgroundUploadUrl: _profileBackgroundUrl,
          cardBackgroundUploadUrl: profile.cardBackgroundUploadUrl,
          timezone: profile.timezone,
          defaultCalendar: profile.defaultCalendar,
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = updated;
        _profileBackgroundUrl = updated.profileBackgroundUploadUrl;
        _hideProfile = updated.hideProfile;
        _bioController.text = updated.bioRaw;
        _changed = true;
      });
      _showSnack('资料已保存');
    } on Object catch (error) {
      if (mounted) {
        _showSnack('保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _absoluteUrl(String value) {
    return ForumUrlResolver.resolve(value);
  }
}

class _AvatarControls extends StatelessWidget {
  const _AvatarControls({
    required this.busy,
    required this.onPickCustom,
    required this.onUseSystem,
  });

  final bool busy;
  final VoidCallback onPickCustom;
  final VoidCallback onUseSystem;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: busy ? null : onPickCustom,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Icon(Icons.image),
            label: const Text('自定义图片'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy ? null : onUseSystem,
            icon: const Icon(Icons.account_circle),
            label: const Text('系统分配'),
          ),
        ),
      ],
    );
  }
}

class _BackgroundControls extends StatelessWidget {
  const _BackgroundControls({
    required this.busy,
    required this.onPick,
  });

  final bool busy;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onPick,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : const Icon(Icons.landscape),
        label: const Text('选择背景图片'),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: ShuYoTextStyles.sectionTitle(),
    );
  }
}
