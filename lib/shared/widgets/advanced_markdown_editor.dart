import 'package:flutter/material.dart';

import '../../core/forum_url_resolver.dart';
import '../../data/models/composer.dart';
import '../shuyo_text_styles.dart';
import '../theme/shuyo_theme.dart';
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
    this.onInsertPoll,
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
  final VoidCallback? onInsertPoll;
  final bool showPreviewInToolbar;
  final String hintText;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
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
              onInsertPoll: onInsertPoll,
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

  static void insertBlock(TextEditingController controller, String block) {
    final value = controller.value;
    final selection = value.selection;
    final text = value.text;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final before =
        start > 0 && !text.substring(0, start).endsWith('\n') ? '\n\n' : '';
    final after = end < text.length && !text.substring(end).startsWith('\n')
        ? '\n\n'
        : '';
    final inserted = '$before$block$after';
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
    var pollIndex = 0;

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

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
      final line = lines[lineIndex];
      final image = imageByMarkdown[line.trim()];
      if (image != null) {
        closeLists();
        buffer.write(_imageHtml(image));
        continue;
      }
      if (!inCode && line.trim().startsWith('[poll')) {
        final pollLines = <String>[];
        var endIndex = lineIndex;
        for (var i = lineIndex; i < lines.length; i += 1) {
          pollLines.add(lines[i]);
          if (lines[i].trim() == '[/poll]') {
            endIndex = i;
            break;
          }
        }
        if (pollLines.last.trim() == '[/poll]') {
          closeLists();
          pollIndex += 1;
          buffer.write(_pollHtml(pollLines, pollIndex));
          lineIndex = endIndex;
          continue;
        }
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

  static String _pollHtml(List<String> lines, int index) {
    final opening = lines.first.trim();
    final attrs = _pollAttributes(opening);
    final type = attrs['type'] ?? 'regular';
    final results = attrs['results'] ?? 'always';
    final public = attrs['public'] ?? 'true';
    final chartType = attrs['chartType'] ?? attrs['charttype'] ?? 'bar';
    final min = attrs['min'];
    final max = attrs['max'];
    String? title;
    for (final line in lines.skip(1).take(lines.length - 2)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        title = trimmed.substring(2).trim();
        break;
      }
    }
    final options = lines
        .skip(1)
        .take(lines.length - 2)
        .map((line) => RegExp(r'^\*\s+(.+)$').firstMatch(line.trim()))
        .whereType<RegExpMatch>()
        .map((match) => match.group(1)!.trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final name = index == 1 ? 'poll' : 'poll$index';
    final buffer = StringBuffer(
      '<div class="poll" data-poll-charttype="${_escapeHtml(chartType)}" '
      'data-poll-name="$name" data-poll-public="${_escapeHtml(public)}" '
      'data-poll-results="${_escapeHtml(results)}" data-poll-status="open" '
      'data-poll-type="${_escapeHtml(type)}"',
    );
    if (min != null) {
      buffer.write(' data-poll-min="${_escapeHtml(min)}"');
    }
    if (max != null) {
      buffer.write(' data-poll-max="${_escapeHtml(max)}"');
    }
    if (title != null && title.isNotEmpty) {
      buffer.write(' data-poll-title="${_escapeHtml(title)}"');
    }
    buffer.write('><div class="poll-container"><ul>');
    for (var optionIndex = 0; optionIndex < options.length; optionIndex += 1) {
      buffer.write(
        '<li data-poll-option-id="preview-$index-$optionIndex">'
        '${_inline(options[optionIndex])}</li>',
      );
    }
    buffer.write('</ul></div></div>');
    return buffer.toString();
  }

  static Map<String, String> _pollAttributes(String opening) {
    final content = opening
        .replaceFirst(RegExp(r'^\[poll\s*'), '')
        .replaceFirst(RegExp(r'\]$'), '');
    return {
      for (final match in RegExp(r'(\w+)=("[^"]*"|\S+)').allMatches(content))
        match.group(1)!:
            (match.group(2) ?? '').replaceAll(RegExp(r'^"|"$'), ''),
    };
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
    final colors = context.shuyoColors;
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
                      style: ShuYoTextStyles.title(
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

Future<String?> showPollMarkdownDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _PollMarkdownDialog(),
  );
}

enum _PollComposerType {
  regular('单选', 'regular'),
  multiple('多选', 'multiple');

  const _PollComposerType(this.label, this.value);

  final String label;
  final String value;
}

enum _PollResultMode {
  always('始终可见', 'always'),
  onVote('只在投票后', 'on_vote'),
  onClose('投票关闭后', 'on_close');

  const _PollResultMode(this.label, this.value);

  final String label;
  final String value;
}

enum _PollChartType {
  bar('柱状图', 'bar'),
  pie('饼状图', 'pie');

  const _PollChartType(this.label, this.value);

  final String label;
  final String value;
}

class _PollChoice<T> {
  const _PollChoice(this.label, this.value);

  final String label;
  final T value;
}

class _PollChoiceRow<T> extends StatelessWidget {
  const _PollChoiceRow({
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<_PollChoice<T>> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              ChoiceChip(
                label: Text(choice.label),
                selected: choice.value == value,
                showCheckmark: false,
                onSelected: (_) => onChanged(choice.value),
                selectedColor: colors.accentSoft,
                backgroundColor: colors.surfaceMuted,
                side: BorderSide(
                  color:
                      choice.value == value ? colors.accentSoft : colors.border,
                ),
                labelStyle: TextStyle(
                  color: choice.value == value
                      ? colors.onAccentSoft
                      : colors.textSecondary,
                  fontSize: 13,
                  fontWeight:
                      choice.value == value ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PollMarkdownDialog extends StatefulWidget {
  const _PollMarkdownDialog();

  @override
  State<_PollMarkdownDialog> createState() => _PollMarkdownDialogState();
}

class _PollMarkdownDialogState extends State<_PollMarkdownDialog> {
  final _titleController = TextEditingController();
  final _optionControllers = [
    TextEditingController(text: 'A'),
    TextEditingController(text: 'B'),
  ];
  _PollComposerType _type = _PollComposerType.regular;
  _PollResultMode _results = _PollResultMode.onVote;
  _PollChartType _chartType = _PollChartType.bar;
  bool _public = true;
  int _min = 1;
  int _max = 2;
  String? _errorText;

  @override
  void dispose() {
    _titleController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return AlertDialog(
      title: const Text('插入投票'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PollChoiceRow<_PollComposerType>(
                label: '类型',
                value: _type,
                choices: const [
                  _PollChoice('单选', _PollComposerType.regular),
                  _PollChoice('多选', _PollComposerType.multiple),
                ],
                onChanged: (value) {
                  setState(() {
                    _type = value;
                    _clampMinMax();
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '标题（可选）',
                ),
              ),
              const SizedBox(height: 10),
              _PollChoiceRow<_PollResultMode>(
                label: '结果显示',
                value: _results,
                choices: const [
                  _PollChoice('始终', _PollResultMode.always),
                  _PollChoice('投票后', _PollResultMode.onVote),
                  _PollChoice('关闭后', _PollResultMode.onClose),
                ],
                onChanged: (value) => setState(() => _results = value),
              ),
              const SizedBox(height: 10),
              _PollChoiceRow<_PollChartType>(
                label: '图表',
                value: _chartType,
                choices: const [
                  _PollChoice('柱状', _PollChartType.bar),
                  _PollChoice('饼图', _PollChartType.pie),
                ],
                onChanged: (value) => setState(() => _chartType = value),
              ),
              const SizedBox(height: 10),
              _PollChoiceRow<bool>(
                label: '投票人',
                value: _public,
                choices: const [
                  _PollChoice('显示', true),
                  _PollChoice('隐藏', false),
                ],
                onChanged: (value) => setState(() => _public = value),
              ),
              const SizedBox(height: 10),
              if (_type == _PollComposerType.multiple) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _min,
                        decoration: const InputDecoration(labelText: '最少'),
                        items: [
                          for (var i = 1; i <= _optionControllers.length; i++)
                            DropdownMenuItem(value: i, child: Text('$i')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _min = value;
                              _clampMinMax();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _max,
                        decoration: const InputDecoration(labelText: '最多'),
                        items: [
                          for (var i = 1; i <= _optionControllers.length; i++)
                            DropdownMenuItem(value: i, child: Text('$i')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _max = value;
                              _clampMinMax();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Text(
                '选项',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              for (var index = 0; index < _optionControllers.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _optionControllers[index],
                          decoration: InputDecoration(
                            labelText: '选项 ${index + 1}',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '删除选项',
                        onPressed: _optionControllers.length <= 2
                            ? null
                            : () => _removeOption(index),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add),
                label: const Text('添加选项'),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 4),
                Text(
                  _errorText!,
                  style: TextStyle(color: colors.danger, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('插入'),
        ),
      ],
    );
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
      _clampMinMax();
    });
  }

  void _removeOption(int index) {
    final controller = _optionControllers.removeAt(index);
    controller.dispose();
    setState(_clampMinMax);
  }

  void _clampMinMax() {
    final count = _optionControllers.length;
    _min = _min.clamp(1, count).toInt();
    _max = _max.clamp(_min, count).toInt();
  }

  void _submit() {
    final options = _optionControllers
        .map((controller) => controller.text.trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    if (options.length < 2) {
      setState(() => _errorText = '至少需要 2 个选项');
      return;
    }
    if (_type == _PollComposerType.multiple &&
        (_min < 1 || _max > options.length || _min > _max)) {
      setState(() => _errorText = '多选数量设置不正确');
      return;
    }
    Navigator.of(context).pop(_buildMarkdown(options));
  }

  String _buildMarkdown(List<String> options) {
    final attrs = [
      'type=${_type.value}',
      'results=${_results.value}',
      'public=$_public',
      'chartType=${_chartType.value}',
      if (_type == _PollComposerType.multiple) ...[
        'min=$_min',
        'max=$_max',
      ],
    ].join(' ');
    final buffer = StringBuffer('[poll $attrs]\n');
    final title = _titleController.text.trim();
    if (title.isNotEmpty) {
      buffer.writeln('# $title');
    }
    for (final option in options) {
      buffer.writeln('* $option');
    }
    buffer.write('[/poll]');
    return buffer.toString();
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
    required this.onInsertPoll,
    required this.showPreview,
  });

  final bool enabled;
  final bool uploading;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onUploadImage;
  final VoidCallback onPreview;
  final VoidCallback? onInsertPoll;
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
          _ToolButton(
            tooltip: '插入投票',
            icon: Icons.how_to_vote_outlined,
            enabled: enabled && onInsertPoll != null,
            onTap: onInsertPoll ?? () {},
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
