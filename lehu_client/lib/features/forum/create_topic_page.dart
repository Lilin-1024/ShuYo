import 'package:flutter/material.dart';

import '../../data/models/category.dart';
import '../../data/models/composer.dart';
import '../../data/models/post.dart';
import '../../data/repositories/forum_repository.dart';
import '../../data/services/local_image_picker.dart';
import '../../shared/widgets/emoji_picker.dart';

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
  final _openedAt = DateTime.now();
  final _images = <UploadedImage>[];
  int? _categoryId;
  bool _submitting = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId ??
        (widget.categories.isEmpty ? null : widget.categories.first.id);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _rawController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发帖'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
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
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
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
          TextField(
            controller: _rawController,
            minLines: 8,
            maxLines: 14,
            decoration: const InputDecoration(
              labelText: '正文',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final image in _images)
                InputChip(
                  label: Text(image.filename),
                  onDeleted: () => setState(() => _images.remove(image)),
                ),
              ActionChip(
                avatar: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.image_outlined, size: 18),
                label: const Text('添加图片'),
                onPressed: _uploading ? null : _pickAndUpload,
              ),
              ActionChip(
                avatar: const Icon(Icons.emoji_emotions_outlined, size: 18),
                label: const Text('Emoji'),
                onPressed: _submitting
                    ? null
                    : () => showEmojiPicker(
                          context: context,
                          controller: _rawController,
                        ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    setState(() => _uploading = true);
    try {
      final picked = await LocalImagePicker.pickImage();
      if (picked == null) {
        return;
      }
      final uploaded = await widget.repository.uploadImage(picked);
      _images.add(uploaded);
      final current = _rawController.text.trimRight();
      _rawController.text = current.isEmpty
          ? uploaded.markdown
          : '$current\n${uploaded.markdown}';
      _rawController.selection =
          TextSelection.collapsed(offset: _rawController.text.length);
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
    final title = _titleController.text.trim();
    final raw = _rawController.text.trim();
    final categoryId = _categoryId;
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
