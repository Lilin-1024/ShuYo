import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/category.dart';
import '../../data/models/composer.dart';
import '../../data/models/post.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/forum_title_rules.dart';
import '../../data/services/local_image_picker.dart';
import '../../shared/theme/lehu_theme.dart';
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
  int? _categoryId;
  bool _submitting = false;
  bool _uploading = false;
  bool _showEmojiPanel = false;
  bool _normalizingTitle = false;
  bool _titleEmojiRejected = false;
  bool _lastTextFocusWasTitle = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId ??
        (widget.categories.isEmpty ? null : widget.categories.first.id);
    _titleController.addListener(_handleTitleChanged);
    _titleFocusNode.addListener(_handleTitleFocusChanged);
    _rawFocusNode.addListener(_handleRawFocusChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
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
        title: const Text('发帖'),
        actions: [
          TextButton(
            onPressed: _submitting || _uploading ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('发布'),
          ),
        ],
      ),
      body: ListView(
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
            onChanged: (value) => setState(() => _categoryId = value),
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
      ),
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
                    : (image) => setState(() => _images.remove(image)),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
      if (mounted) {
        setState(() {});
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

  Future<void> _submit() async {
    if (_uploading) {
      return;
    }
    final title = _titleController.text.trim();
    final raw = composeRawWithImages(_rawController.text, _images);
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

    setState(() => _submitting = true);
    try {
      final post = await widget.repository.createTopic(
        CreateTopicDraft(
          title: title,
          raw: raw,
          categoryId: categoryId,
          draftKey: 'new_topic_${DateTime.now().millisecondsSinceEpoch}',
          images: _images,
          composerOpenDurationMs:
              DateTime.now().difference(_openedAt).inMilliseconds,
        ),
      );
      if (!mounted) {
        return;
      }
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

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
