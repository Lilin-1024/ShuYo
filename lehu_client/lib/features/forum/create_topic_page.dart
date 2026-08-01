import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/category.dart';
import '../../data/models/composer.dart';
import '../../data/models/post.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/forum_draft_store.dart';
import '../../data/services/forum_title_rules.dart';
import '../../data/services/local_image_picker.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/widgets/advanced_markdown_editor.dart';
import '../../shared/widgets/composer_attachments.dart';
import '../../shared/widgets/inline_emoji_panel.dart';

class CreatedTopicResult {
  const CreatedTopicResult({
    required this.post,
    required this.title,
    required this.categoryId,
  });

  final Post post;
  final String title;
  final int categoryId;
}

class CreateTopicPage extends StatefulWidget {
  const CreateTopicPage({
    super.key,
    required this.repository,
    required this.categories,
    required this.initialCategoryId,
  });

  final ForumRepository repository;
  final List<ForumCategory> categories;
  final int? initialCategoryId;

  @override
  State<CreateTopicPage> createState() => _CreateTopicPageState();
}

class _CreateTopicPageState extends State<CreateTopicPage> {
  final _titleController = TextEditingController();
  final _rawController = TextEditingController();
  final _titleFocusNode = FocusNode();
  final _rawFocusNode = FocusNode();
  final _openedAt = DateTime.now();
  final _images = <UploadedImage>[];
  Timer? _draftSaveTimer;
  int? _categoryId;
  bool _submitting = false;
  bool _uploading = false;
  bool _showEmojiPanel = false;
  bool _normalizingTitle = false;
  bool _titleEmojiRejected = false;
  bool _lastTextFocusWasTitle = false;
  bool _draftReady = false;
  bool _restoringDraft = false;
  _TopicComposerMode _mode = _TopicComposerMode.basic;

  String get _draftKey {
    return ForumDraftStore.newTopicKey(widget.repository.profile.username);
  }

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId ??
        (widget.categories.isEmpty ? null : widget.categories.first.id);
    _titleController.addListener(_handleTitleChanged);
    _rawController.addListener(_handleDraftChanged);
    _titleFocusNode.addListener(_handleTitleFocusChanged);
    _rawFocusNode.addListener(_handleRawFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadDraft());
    });
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    unawaited(_saveDraftNow());
    _titleController.removeListener(_handleTitleChanged);
    _rawController.removeListener(_handleDraftChanged);
    _titleFocusNode.removeListener(_handleTitleFocusChanged);
    _rawFocusNode.removeListener(_handleRawFocusChanged);
    _titleController.dispose();
    _rawController.dispose();
    _titleFocusNode.dispose();
    _rawFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _ComposerModeMenu(
          mode: _mode,
          onChanged: _setMode,
        ),
        actions: [
          if (_mode == _TopicComposerMode.advanced)
            TextButton(
              onPressed: _submitting ? null : _showPreview,
              child: const Text('预览'),
            ),
          TextButton(
            onPressed: _submitting || _uploading ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Text('发布'),
          ),
        ],
      ),
      body: _mode == _TopicComposerMode.basic
          ? _basicBody(context)
          : _advancedBody(context),
    );
  }

  Widget _basicBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          controller: _titleController,
          focusNode: _titleFocusNode,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: '标题',
            border: const OutlineInputBorder(),
            errorText: _titleEmojiRejected
                ? ForumTitleRules.disallowedEmojiMessage
                : null,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _categoryId,
          decoration: const InputDecoration(
            labelText: '分区',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final category in widget.categories)
              DropdownMenuItem(
                value: category.id,
                child: Text(category.name),
              ),
          ],
          onChanged: (value) {
            setState(() => _categoryId = value);
            _scheduleDraftSave();
          },
        ),
        const SizedBox(height: 12),
        _rawComposer(context),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _showEmojiPanel
              ? InlineEmojiPanel(
                  key: const ValueKey('emoji-panel'),
                  controller: _rawController,
                )
              : const SizedBox.shrink(
                  key: ValueKey('emoji-empty'),
                ),
        ),
      ],
    );
  }

  Widget _advancedBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        TextField(
          controller: _titleController,
          focusNode: _titleFocusNode,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: '标题',
            border: const OutlineInputBorder(),
            errorText: _titleEmojiRejected
                ? ForumTitleRules.disallowedEmojiMessage
                : null,
          ),
        ),
        const SizedBox(height: 12),
        AdvancedMarkdownEditor(
          controller: _rawController,
          focusNode: _rawFocusNode,
          enabled: !_submitting,
          uploading: _uploading,
          onUploadImage: _pickAndUpload,
          onPreview: _showPreview,
          onInsertPoll: _insertPoll,
          showPreviewInToolbar: false,
          minLines: 13,
          maxLines: 28,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _categoryId,
          decoration: const InputDecoration(
            labelText: '分区',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final category in widget.categories)
              DropdownMenuItem(
                value: category.id,
                child: Text(category.name),
              ),
          ],
          onChanged: (value) {
            setState(() => _categoryId = value);
            _scheduleDraftSave();
          },
        ),
      ],
    );
  }

  void _handleTitleChanged() {
    if (_normalizingTitle) {
      return;
    }
    final value = _titleController.value;
    final sanitized = ForumTitleRules.sanitizeEditingValue(value);
    final rejected = sanitized.text != value.text;
    if (rejected) {
      _normalizingTitle = true;
      _titleController.value = sanitized;
      _normalizingTitle = false;
    }
    if (mounted && _titleEmojiRejected != rejected) {
      setState(() => _titleEmojiRejected = rejected);
    }
    _scheduleDraftSave();
  }

  void _handleTitleFocusChanged() {
    if (_titleFocusNode.hasFocus) {
      _lastTextFocusWasTitle = true;
    }
  }

  Widget _rawComposer(BuildContext context) {
    final focused = _rawFocusNode.hasFocus || _showEmojiPanel;
    final borderColor = focused
        ? Theme.of(context).colorScheme.primary
        : context.lehuColors.borderStrong;
    final enabled = !_submitting && !_uploading;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: focused ? 1.4 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _rawController,
            focusNode: _rawFocusNode,
            minLines: 8,
            maxLines: 14,
            readOnly: _submitting,
            textInputAction: TextInputAction.newline,
            onTap: _handleRawTap,
            decoration: const InputDecoration(
              hintText: '正文',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 8),
            ),
          ),
          if (_images.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ComposerAttachmentPreviewRow(
                images: _images,
                onRemove: _submitting || _uploading
                    ? null
                    : (image) {
                        setState(() => _images.remove(image));
                        _scheduleDraftSave();
                      },
              ),
            ),
          ],
          SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '添加图片',
                  onPressed: enabled ? _pickAndUpload : null,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        )
                      : const Icon(Icons.image_outlined),
                ),
                IconButton(
                  tooltip: 'Emoji',
                  onPressed: enabled ? _toggleEmojiPanel : null,
                  icon: Icon(
                    _showEmojiPanel
                        ? Icons.keyboard_alt_outlined
                        : Icons.emoji_emotions_outlined,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleRawFocusChanged() {
    if (!mounted) {
      return;
    }
    if (_rawFocusNode.hasFocus) {
      _lastTextFocusWasTitle = false;
    }
    if (_rawFocusNode.hasFocus && _showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
      return;
    }
    setState(() {});
  }

  void _handleRawTap() {
    if (_showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
    }
  }

  void _setMode(_TopicComposerMode mode) {
    if (mode == _mode) {
      return;
    }
    setState(() {
      if (_mode == _TopicComposerMode.basic &&
          mode == _TopicComposerMode.advanced) {
        _discardDetachedImages();
      }
      _mode = mode;
      _showEmojiPanel = false;
    });
    _scheduleDraftSave();
  }

  void _discardDetachedImages() {
    final raw = _rawController.text;
    _images.removeWhere((image) => !isComposerImageReferenced(raw, image));
  }

  void _toggleEmojiPanel() {
    if (_showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
      _rawFocusNode.requestFocus();
      return;
    }
    final shouldGuideTitleEmoji =
        _titleFocusNode.hasFocus || _lastTextFocusWasTitle;
    _lastTextFocusWasTitle = false;
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    setState(() {
      _showEmojiPanel = true;
      if (shouldGuideTitleEmoji) {
        _titleEmojiRejected = true;
      }
    });
  }

  Future<void> _pickAndUpload() async {
    setState(() {
      _uploading = true;
      _showEmojiPanel = false;
    });
    try {
      final picked = await LocalImagePicker.pickImage();
      if (picked == null) {
        return;
      }
      final uploaded = await widget.repository.uploadImage(picked);
      _images.add(uploaded);
      if (_mode == _TopicComposerMode.advanced) {
        MarkdownEditing.insertImageMarkdown(_rawController, uploaded);
      }
      if (mounted) {
        setState(() {});
        _scheduleDraftSave();
      }
    } on Object catch (error) {
      if (mounted) {
        _showSnack('图片上传失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _insertPoll() async {
    final markdown = await showPollMarkdownDialog(context);
    if (markdown == null || !mounted) {
      return;
    }
    MarkdownEditing.insertBlock(_rawController, markdown);
    _rawFocusNode.requestFocus();
    _scheduleDraftSave();
  }

  Future<void> _submit() async {
    if (_uploading) {
      return;
    }
    final title = _titleController.text.trim();
    final raw = _composeRawForMode();
    final images = _imagesForMode();
    final categoryId = _categoryId;
    if (ForumTitleRules.containsDisallowedEmoji(title)) {
      _titleController.value = ForumTitleRules.sanitizeEditingValue(
        _titleController.value,
      );
      setState(() => _titleEmojiRejected = true);
      return;
    }
    if (title.length < 6) {
      _showSnack('标题至少 6 个字');
      return;
    }
    if (raw.length < 8) {
      _showSnack('正文至少 8 个字');
      return;
    }
    if (categoryId == null) {
      _showSnack('请选择分区');
      return;
    }
    final confirmed = await _confirmSubmit();
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _submitting = true);
    try {
      final post = await widget.repository.createTopic(
        CreateTopicDraft(
          title: title,
          raw: raw,
          categoryId: categoryId,
          draftKey: 'new_topic_${DateTime.now().millisecondsSinceEpoch}',
          images: images,
          composerOpenDurationMs:
              DateTime.now().difference(_openedAt).inMilliseconds,
        ),
      );
      if (!mounted) {
        return;
      }
      await ForumDraftStore.remove(_draftKey);
      if (!mounted) {
        return;
      }
      _draftReady = false;
      Navigator.of(context).pop(
        CreatedTopicResult(
          post: post,
          title: title,
          categoryId: categoryId,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        _showSnack('发布失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<bool?> _confirmSubmit() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认发布帖子'),
          content: const Text('是否确认发布？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('发布'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPreview() async {
    final categoryName = _selectedCategoryName();
    await Navigator.of(context).push<void>(
      lehuRoute(
        builder: (context) => MarkdownPreviewPage(
          appBarTitle: '预览主题',
          heading: _titleController.text.trim().isEmpty
              ? '未填写标题'
              : _titleController.text.trim(),
          meta: categoryName == null ? '新主题' : '新主题 / $categoryName',
          raw: _composeRawForMode(),
          images: _imagesForMode(),
        ),
      ),
    );
  }

  String _composeRawForMode() {
    if (_mode == _TopicComposerMode.advanced) {
      return _rawController.text.trim();
    }
    return composeRawWithImages(_rawController.text, _images);
  }

  List<UploadedImage> _imagesForMode() {
    if (_mode == _TopicComposerMode.advanced) {
      return referencedComposerImages(_rawController.text, _images);
    }
    return List<UploadedImage>.of(_images);
  }

  String? _selectedCategoryName() {
    for (final category in widget.categories) {
      if (category.id == _categoryId) {
        return category.name;
      }
    }
    return null;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadDraft() async {
    final draft = await ForumDraftStore.load(_draftKey);
    if (!mounted) {
      return;
    }
    if (draft == null) {
      _draftReady = true;
      return;
    }
    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('恢复草稿？'),
          content: const Text('发现一份未发布的帖子草稿，是否继续编辑？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('丢弃'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('恢复'),
            ),
          ],
        );
      },
    );
    if (!mounted) {
      return;
    }
    if (shouldRestore == true) {
      _restoreDraft(draft);
      _draftReady = true;
      return;
    }
    await ForumDraftStore.remove(_draftKey);
    _draftReady = true;
  }

  void _restoreDraft(ForumComposerDraft draft) {
    _restoringDraft = true;
    _titleController.text = draft.title;
    _rawController.text = draft.raw;
    final draftCategoryId = draft.categoryId;
    final hasDraftCategory = widget.categories.any(
      (category) => category.id == draftCategoryId,
    );
    setState(() {
      if (hasDraftCategory) {
        _categoryId = draftCategoryId;
      }
      _images
        ..clear()
        ..addAll(draft.images);
    });
    _restoringDraft = false;
  }

  void _handleDraftChanged() {
    _scheduleDraftSave();
  }

  void _scheduleDraftSave() {
    if (!_draftReady || _restoringDraft || _submitting) {
      return;
    }
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_saveDraftNow()),
    );
  }

  Future<void> _saveDraftNow() async {
    if (!_draftReady || _restoringDraft || _submitting) {
      return;
    }
    await ForumDraftStore.save(
      _draftKey,
      ForumComposerDraft(
        title: _titleController.text,
        raw: _rawController.text,
        categoryId: _categoryId,
        images: List<UploadedImage>.of(_images),
      ),
    );
  }
}

enum _TopicComposerMode {
  basic('基础'),
  advanced('进阶');

  const _TopicComposerMode(this.label);

  final String label;
}

class _ComposerModeMenu extends StatelessWidget {
  const _ComposerModeMenu({
    required this.mode,
    required this.onChanged,
  });

  final _TopicComposerMode mode;
  final ValueChanged<_TopicComposerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TopicComposerMode>(
      tooltip: '选择编辑模式',
      onSelected: onChanged,
      itemBuilder: (context) {
        return [
          for (final item in _TopicComposerMode.values)
            PopupMenuItem(
              value: item,
              child: Row(
                children: [
                  Expanded(child: Text(item.label)),
                  if (item == mode) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ];
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mode.label),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    );
  }
}
