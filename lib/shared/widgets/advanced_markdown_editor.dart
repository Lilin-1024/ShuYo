import 'package:flutter/material.dart';

import '../../core/forum_url_resolver.dart';
import '../../data/models/composer.dart';
import '../lehu_text_styles.dart';
import '../theme/lehu_theme.dart';
import 'forum_cooked_content.dart';

class AdvancedMarkdownEditor extends StatelessWidget {
  const AdvancedMarkdownEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.uploading,
    required this.onUploadImage,
    required this.onPreview,
    this.showPreviewInToolbar = true,
    this.hintText = '正文',
    this.minLines = 12,
    this.maxLines = 24,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool uploading;
  final VoidCallback onUploadImage;
  final VoidCallback onPreview;
  final bool showPreviewInToolbar;
  final String hintText;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderStrong),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MarkdownToolbar(
              enabled: enabled,
              uploading: uploading,
              controller: controller,
              focusNode: focusNode,
              onUploadImage: onUploadImage,
              onPreview: onPreview,
              showPreview: showPreviewInToolbar,
            ),
            Divider(height: 1, color: colors.border),
            TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              minLines: minLines,
              maxLines: maxLines,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MarkdownEditing {
  const MarkdownEditing._();

  static void wrapSelection(
    TextEditingController controller, {
    required String prefix,
    required String suffix,
    required String placeholder,
  }) {
    final value = controller.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = start == end ? placeholder : text.substring(start, end);
    final inserted = '$prefix$selected$suffix';
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, inserted),
      selection: TextSelection(
        baseOffset: start + prefix.length,
        extentOffset: start + prefix.length + selected.length,
      ),
    );
  }

  static void prefixLines(
    TextEditingController controller, {
    required String prefix,
    required String placeholder,
  }) {
    final value = controller.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    if (start == end) {
      final insert = '$prefix$placeholder';
      controller.value = TextEditingValue(
        text: text.replaceRange(start, end, insert),
        selection: TextSelection(
          baseOffset: start + prefix.length,
          extentOffset: start + insert.length,
        ),
      );
      return;
    }
    final selected = text.substring(start, end);
    final lines = selected.split('\n');
    final inserted = lines.map((line) => '$prefix$line').join('\n');
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, inserted),
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + inserted.length,
      ),
    );
  }

  static void orderedList(TextEditingController controller) {
    final value = controller.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    if (start == end) {
      const insert = '1. 列表项';
      controller.value = TextEditingValue(
        text: text.replaceRange(start, end, insert),
        selection:
            const TextSelection(baseOffset: 3, extentOffset: 6).shift(start),
      );
      return;
    }
    final lines = text.substring(start, end).split('\n');
    final inserted = [
      for (var index = 0; index < lines.length; index += 1)
        '${index + 1}. ${lines[index]}',
    ].join('\n');
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, inserted),
      selection: TextSelection(
        baseOffset: start,
        extentOffset: start + inserted.length,
      ),
    );
  }

  static void insertImageMarkdown(
    TextEditingController controller,
    UploadedImage image,
  ) {
    final value = controller.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final before =
        start > 0 && !text.substring(0, start).endsWith('\n') ? '\n' : '';
    final after =
        end < text.length && !text.substring(end).startsWith('\n') ? '\n' : '';
    final inserted = '$before${image.markdown}$after';
    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, inserted),
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
  }

  static String previewCooked(String raw, List<UploadedImage> images) {
    final imageByMarkdown = {
      for (final image in images) image.markdown: image,
    };
    final lines =
        raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final buffer = StringBuffer();
    var inUl = false;
    var inOl = false;
    var inCode = false;

    void closeLists() {
      if (inUl) {
        buffer.write('</ul>');
        inUl = false;
      }
      if (inOl) {
        buffer.write('</ol>');
        inOl = false;
      }
    }

    for (final line in lines) {
      final image = imageByMarkdown[line.trim()];
      if (image != null) {
        closeLists();
        buffer.write(_imageHtml(image));
        continue;
      }
      if (line.trim().startsWith('```')) {
        closeLists();
        if (inCode) {
          buffer.write('</code></pre>');
        } else {
          buffer.write('<pre><code>');
        }
        inCode = !inCode;
        continue;
      }
      if (inCode) {
        buffer.write('${_escapeHtml(line)}\n');
        continue;
      }
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        closeLists();
        continue;
      }
      final heading = RegExp(r'^(#{1,2})\s+(.+)$').firstMatch(trimmed);
      if (heading != null) {
        closeLists();
        final level = heading.group(1)!.length;
        buffer.write('<h$level>${_inline(heading.group(2)!)}</h$level>');
        continue;
      }
      if (trimmed.startsWith('> ')) {
        closeLists();
        buffer.write(
            '<blockquote><p>${_inline(trimmed.substring(2))}</p></blockquote>');
        continue;
      }
      final ul = RegExp(r'^[-*]\s+(.+)$').firstMatch(trimmed);
      if (ul != null) {
        if (inOl) {
          buffer.write('</ol>');
          inOl = false;
        }
        if (!inUl) {
          buffer.write('<ul>');
          inUl = true;
        }
        buffer.write('<li>${_inline(ul.group(1)!)}</li>');
        continue;
      }
      final ol = RegExp(r'^\d+\.\s+(.+)$').firstMatch(trimmed);
      if (ol != null) {
        if (inUl) {
          buffer.write('</ul>');
          inUl = false;
        }
        if (!inOl) {
          buffer.write('<ol>');
          inOl = true;
        }
        buffer.write('<li>${_inline(ol.group(1)!)}</li>');
        continue;
      }
      closeLists();
      buffer.write('<p>${_inline(line)}</p>');
    }
    closeLists();
    if (inCode) {
      buffer.write('</code></pre>');
    }
    final cooked = buffer.toString().trim();
    return cooked.isEmpty ? '<p>暂无预览内容</p>' : cooked;
  }

  static String _imageHtml(UploadedImage image) {
    final width =
        image.thumbnailWidth == 0 ? image.width : image.thumbnailWidth;
    final height =
        image.thumbnailHeight == 0 ? image.height : image.thumbnailHeight;
    final size =
        width > 0 && height > 0 ? ' width="$width" height="$height"' : '';
    return '<p><img src="${_escapeHtml(ForumUrlResolver.resolve(image.url))}" '
        'alt="${_escapeHtml(image.filename)}"$size></p>';
  }

  static String _inline(String value) {
    var text = _escapeHtml(value);
    text = text.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (match) => '<code>${match.group(1)}</code>',
    );
    text = text.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'),
      (match) => '<strong>${match.group(1)}</strong>',
    );
    text = text.replaceAllMapped(
      RegExp(r'\*([^*]+)\*'),
      (match) => '<em>${match.group(1)}</em>',
    );
    return text;
  }

  static String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }
}

class MarkdownPreviewPage extends StatelessWidget {
  const MarkdownPreviewPage({
    super.key,
    required this.appBarTitle,
    this.heading,
    this.meta,
    required this.raw,
    required this.images,
  });

  final String appBarTitle;
  final String? heading;
  final String? meta;
  final String raw;
  final List<UploadedImage> images;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final hasHeading = (heading ?? '').isNotEmpty;
    final hasMeta = (meta ?? '').isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          if (hasHeading || hasMeta) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasHeading)
                    Text(
                      heading!,
                      style: LehuTextStyles.title(
                        color: colors.textPrimary,
                        size: 20.5,
                        height: 1.2,
                        weight: FontWeight.w500,
                      ),
                    ),
                  if (hasMeta) ...[
                    const SizedBox(height: 10),
                    Text(
                      meta!,
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 14),
          ],
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: ForumCookedContent(
              cooked: MarkdownEditing.previewCooked(raw, images),
              textColor: colors.textPrimary,
              onOpenImage: (_, __) {},
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkdownToolbar extends StatelessWidget {
  const _MarkdownToolbar({
    required this.enabled,
    required this.uploading,
    required this.controller,
    required this.focusNode,
    required this.onUploadImage,
    required this.onPreview,
    required this.showPreview,
  });

  final bool enabled;
  final bool uploading;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onUploadImage;
  final VoidCallback onPreview;
  final bool showPreview;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: [
          _ToolButton(
            tooltip: '粗体',
            icon: Icons.format_bold,
            enabled: enabled,
            onTap: () => _wrap('**', '**', '粗体'),
          ),
          _ToolButton(
            tooltip: '斜体',
            icon: Icons.format_italic,
            enabled: enabled,
            onTap: () => _wrap('*', '*', '斜体'),
          ),
          _ToolButton(
            tooltip: '一级标题',
            label: 'H1',
            enabled: enabled,
            onTap: () => _prefix('# ', '一级标题'),
          ),
          _ToolButton(
            tooltip: '二级标题',
            label: 'H2',
            enabled: enabled,
            onTap: () => _prefix('## ', '二级标题'),
          ),
          _ToolButton(
            tooltip: '引用',
            icon: Icons.format_quote,
            enabled: enabled,
            onTap: () => _prefix('> ', '引用内容'),
          ),
          _ToolButton(
            tooltip: '无序列表',
            icon: Icons.format_list_bulleted,
            enabled: enabled,
            onTap: () => _prefix('- ', '列表项'),
          ),
          _ToolButton(
            tooltip: '有序列表',
            icon: Icons.format_list_numbered,
            enabled: enabled,
            onTap: () {
              MarkdownEditing.orderedList(controller);
              focusNode.requestFocus();
            },
          ),
          _ToolButton(
            tooltip: '插入图片',
            icon: Icons.image_outlined,
            enabled: enabled && !uploading,
            loading: uploading,
            onTap: onUploadImage,
          ),
          if (showPreview)
            _ToolButton(
              tooltip: '预览',
              icon: Icons.visibility_outlined,
              enabled: true,
              onTap: onPreview,
            ),
        ],
      ),
    );
  }

  void _wrap(String prefix, String suffix, String placeholder) {
    MarkdownEditing.wrapSelection(
      controller,
      prefix: prefix,
      suffix: suffix,
      placeholder: placeholder,
    );
    focusNode.requestFocus();
  }

  void _prefix(String prefix, String placeholder) {
    MarkdownEditing.prefixLines(
      controller,
      prefix: prefix,
      placeholder: placeholder,
    );
    focusNode.requestFocus();
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.icon,
    this.label,
    this.loading = false,
  });

  final String tooltip;
  final IconData? icon;
  final String? label;
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 3),
          )
        : icon == null
            ? Text(
                label ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            : Icon(icon);
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      icon: child,
      visualDensity: VisualDensity.compact,
    );
  }
}

extension on TextSelection {
  TextSelection shift(int offset) {
    return TextSelection(
      baseOffset: baseOffset + offset,
      extentOffset: extentOffset + offset,
    );
  }
}
