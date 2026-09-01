import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/forum_poll.dart';
import '../../data/services/html_text.dart';
import '../theme/shuyo_theme.dart';
import 'avatar.dart';
import 'forum_inline_image_layout.dart';
import 'forum_network_image.dart';

typedef ForumPollVoteCallback = Future<void> Function(
  ForumPoll poll,
  List<String> optionIds,
);

typedef ForumPollStatusCallback = Future<void> Function(
  ForumPoll poll,
  String status,
);

class ForumCookedContent extends StatelessWidget {
  const ForumCookedContent({
    super.key,
    required this.cooked,
    required this.textColor,
    required this.onOpenImage,
    this.onOpenUser,
    this.onOpenInternalTopic,
    this.polls = const [],
    this.canManagePolls = false,
    this.isPollBusy,
    this.onVotePoll,
    this.onTogglePollStatus,
    this.textSize = 16,
    this.textHeight = 1.46,
    this.textWeight = FontWeight.w400,
    this.textBottomSpacing = 8,
    this.imageBottomSpacing = 10,
    this.imageErrorHeight = 160,
    this.imageFit = BoxFit.contain,
    this.compactCards = false,
    this.privateImage = false,
  });

  final String cooked;
  final Color textColor;
  final void Function(List<String> urls, int initialIndex) onOpenImage;
  final ValueChanged<String>? onOpenUser;
  final ValueChanged<CookedLinkPreview>? onOpenInternalTopic;
  final List<ForumPoll> polls;
  final bool canManagePolls;
  final bool Function(ForumPoll poll)? isPollBusy;
  final ForumPollVoteCallback? onVotePoll;
  final ForumPollStatusCallback? onTogglePollStatus;
  final double textSize;
  final double textHeight;
  final FontWeight textWeight;
  final double textBottomSpacing;
  final double imageBottomSpacing;
  final double imageErrorHeight;
  final BoxFit imageFit;
  final bool compactCards;
  final bool privateImage;

  @override
  Widget build(BuildContext context) {
    final segments = HtmlText.parseSegments(cooked);
    if (segments.isEmpty) {
      return Text(' ', style: TextStyle(color: textColor));
    }
    final pollByName = {
      for (final poll in polls) poll.name: poll,
    };
    final imageUrls = [
      for (final segment in segments)
        if (segment.isImage) segment.resolvedImageFullUrl,
    ];
    final contentWidgets = <Widget>[];
    var imageIndex = 0;
    for (final segment in segments) {
      switch (segment.kind) {
        case CookedSegmentKind.text:
          contentWidgets.add(
            Padding(
              padding: EdgeInsets.only(bottom: textBottomSpacing),
              child: _CookedTextBlock(
                segment: segment,
                textColor: textColor,
                textSize: textSize,
                textHeight: textHeight,
                textWeight: textWeight,
                onOpenLink: (preview) => _openPreview(context, preview),
                privateImage: privateImage,
              ),
            ),
          );
        case CookedSegmentKind.image:
          final currentImageIndex = imageIndex++;
          contentWidgets.add(
            Padding(
              padding: EdgeInsets.only(bottom: imageBottomSpacing),
              child: GestureDetector(
                onTap: () => onOpenImage(imageUrls, currentImageIndex),
                child: _CookedImage(
                  url: segment.value,
                  width: segment.imageWidth,
                  height: segment.imageHeight,
                  fit: imageFit,
                  errorHeight: imageErrorHeight,
                  privateImage: privateImage,
                ),
              ),
            ),
          );
        case CookedSegmentKind.link:
          contentWidgets.add(
            Padding(
              padding: EdgeInsets.only(bottom: textBottomSpacing),
              child: _InlineLink(
                preview: segment.link!,
                onTap: () => _openPreview(context, segment.link!),
              ),
            ),
          );
        case CookedSegmentKind.onebox:
        case CookedSegmentKind.quote:
          contentWidgets.add(
            Padding(
              padding: EdgeInsets.only(bottom: textBottomSpacing + 2),
              child: _OneboxCard(
                preview: segment.link!,
                isQuote: segment.isQuote,
                compact: compactCards,
                onTap: () => _openPreview(context, segment.link!),
              ),
            ),
          );
        case CookedSegmentKind.poll:
          final parsedPoll = segment.poll;
          final poll = parsedPoll == null ? null : pollByName[parsedPoll.name];
          final displayPoll = poll ?? parsedPoll;
          if (displayPoll != null) {
            contentWidgets.add(
              Padding(
                padding: EdgeInsets.only(bottom: textBottomSpacing + 4),
                child: _ForumPollCard(
                  poll: displayPoll,
                  compact: compactCards,
                  canManage: canManagePolls,
                  busy: isPollBusy?.call(displayPoll) ?? false,
                  onVote: onVotePoll,
                  onToggleStatus: onTogglePollStatus,
                ),
              ),
            );
          }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: contentWidgets,
    );
  }

  Future<void> _openPreview(
    BuildContext context,
    CookedLinkPreview preview,
  ) async {
    final username = preview.userUsername;
    if (preview.isInternalUser && username != null && onOpenUser != null) {
      onOpenUser!(username);
      return;
    }
    if ((preview.isInternalTopic || preview.isInternalForumRoute) &&
        onOpenInternalTopic != null) {
      onOpenInternalTopic!(preview);
      return;
    }
    final uri = Uri.tryParse(preview.url);
    if (uri == null || !uri.hasScheme) {
      _showSnack(context, '链接无效');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('打开外部链接？'),
          content: Text('即将在浏览器中打开：\n${preview.url}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('打开'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _showSnack(context, '无法打开链接');
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

String _optionText(ForumPollOption option) {
  final plain = HtmlText.toPlainText(option.html).trim();
  return plain.isEmpty ? option.html : plain;
}

String _hiddenResultText(ForumPoll poll) {
  if (poll.results == 'on_vote') {
    return '投票后显示结果';
  }
  if (poll.results == 'on_close') {
    return '投票关闭后显示结果';
  }
  return '结果暂不可见';
}

String _pollMetaText(ForumPoll poll) {
  final parts = [
    poll.isMultiple ? '多选' : '单选',
    poll.isClosed ? '已关闭' : null,
    poll.voters <= 0 ? '暂无投票人' : '${poll.voters} 位投票人',
  ].whereType<String>();
  return parts.join(' · ');
}

bool _hasPreloadedVoters(ForumPoll poll) {
  return poll.preloadedVoters.values.any((list) => list.isNotEmpty);
}

enum _PollResultDisplay { count, percent }

String _pollOptionMetricText(
  ForumPoll poll,
  ForumPollOption option,
  _PollResultDisplay display,
) {
  if (display == _PollResultDisplay.percent) {
    final denominator = poll.resultDenominator;
    final percent = denominator <= 0 ? 0.0 : option.votes / denominator;
    return '${(percent * 100).round()}%';
  }
  return '${option.votes}人';
}

List<Color> _pollPalette(ShuYoColors colors) {
  return [
    colors.accent,
    colors.accentAlt,
    colors.success,
    colors.warning,
    colors.danger,
    colors.textTertiary,
  ];
}

class _CookedTextBlock extends StatelessWidget {
  const _CookedTextBlock({
    required this.segment,
    required this.textColor,
    required this.textSize,
    required this.textHeight,
    required this.textWeight,
    required this.onOpenLink,
    required this.privateImage,
  });

  final CookedSegment segment;
  final Color textColor;
  final double textSize;
  final double textHeight;
  final FontWeight textWeight;
  final ValueChanged<CookedLinkPreview> onOpenLink;
  final bool privateImage;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return switch (segment.textBlockKind) {
      CookedTextBlockKind.heading => _richText(
          context,
          _baseStyle(context).copyWith(
            fontSize: _headingSize,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      CookedTextBlockKind.blockquote => Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: BoxDecoration(
            color: colors.surfaceMuted.withValues(alpha: 0.58),
            border: Border(
              left: BorderSide(
                color: colors.borderStrong,
                width: 3,
              ),
            ),
          ),
          child: _richText(
            context,
            _baseStyle(context).copyWith(color: colors.textSecondary),
          ),
        ),
      CookedTextBlockKind.listItem => Padding(
          padding: EdgeInsets.only(left: (segment.listDepth * 14).toDouble()),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  segment.listIndex > 0 ? '${segment.listIndex}.' : '•',
                  style: _baseStyle(context).copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Expanded(child: _richText(context, _baseStyle(context))),
            ],
          ),
        ),
      CookedTextBlockKind.codeBlock => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceMuted.withValues(alpha: 0.7),
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _richText(
              context,
              _baseStyle(context).copyWith(
                fontFamily: 'monospace',
                fontSize: textSize * 0.9,
                height: 1.42,
              ),
              softWrap: false,
            ),
          ),
        ),
      CookedTextBlockKind.paragraph => _richText(context, _baseStyle(context)),
    };
  }

  double get _headingSize {
    return switch (segment.headingLevel) {
      1 => textSize + 3.5,
      2 => textSize + 2.4,
      3 => textSize + 1.4,
      _ => textSize + 0.8,
    };
  }

  TextStyle _baseStyle(BuildContext context) {
    return TextStyle(
      color: textColor,
      fontSize: textSize,
      height: textHeight,
      fontWeight: textWeight,
    );
  }

  Widget _richText(
    BuildContext context,
    TextStyle baseStyle, {
    bool softWrap = true,
  }) {
    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: _spans(context, baseStyle),
      ),
      softWrap: softWrap,
    );
  }

  List<InlineSpan> _spans(BuildContext context, TextStyle baseStyle) {
    final colors = context.shuyoColors;
    final runs =
        segment.runs.isEmpty ? [CookedTextRun(segment.value)] : segment.runs;
    return [
      for (final run in runs) _spanForRun(run, baseStyle, colors),
    ];
  }

  InlineSpan _spanForRun(
    CookedTextRun run,
    TextStyle baseStyle,
    ShuYoColors colors,
  ) {
    final style = baseStyle.copyWith(
      color: run.isLink ? colors.accent : baseStyle.color,
      fontWeight: run.bold ? FontWeight.w600 : baseStyle.fontWeight,
      fontStyle: run.italic ? FontStyle.italic : baseStyle.fontStyle,
      decoration:
          run.strikethrough ? TextDecoration.lineThrough : baseStyle.decoration,
      fontFamily: run.code ? 'monospace' : baseStyle.fontFamily,
      fontSize: run.code ? textSize * 0.92 : baseStyle.fontSize,
      backgroundColor:
          run.code ? colors.surfaceMuted.withValues(alpha: 0.82) : null,
    );
    final emojiUrl = run.inlineEmojiUrl;
    if (emojiUrl != null) {
      final size = (style.fontSize ?? textSize) * 1.12;
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _InlineEmoji(
          url: emojiUrl,
          fallback: run.text,
          size: size,
          fallbackStyle: style,
          onTap: run.link == null ? null : () => onOpenLink(run.link!),
          privateImage: privateImage,
        ),
      );
    }
    return TextSpan(
      text: run.text,
      style: style,
      recognizer: run.link == null
          ? null
          : (TapGestureRecognizer()..onTap = () => onOpenLink(run.link!)),
    );
  }
}

class _InlineEmoji extends StatefulWidget {
  const _InlineEmoji({
    required this.url,
    required this.fallback,
    required this.size,
    required this.fallbackStyle,
    this.onTap,
    required this.privateImage,
  });

  final String url;
  final String fallback;
  final double size;
  final TextStyle fallbackStyle;
  final VoidCallback? onTap;
  final bool privateImage;

  @override
  State<_InlineEmoji> createState() => _InlineEmojiState();
}

class _InlineEmojiState extends State<_InlineEmoji> {
  var _failed = false;

  @override
  void didUpdateWidget(covariant _InlineEmoji oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _failed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _failed
        ? Text(widget.fallback, style: widget.fallbackStyle)
        : SizedBox(
            width: widget.size,
            height: widget.size,
            child: ForumNetworkImage(
              widget.url,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              privateImage: widget.privateImage,
              errorBuilder: (context, error, stackTrace) {
                _reportFailure();
                return const SizedBox.shrink();
              },
            ),
          );
    final tappable = widget.onTap == null
        ? child
        : GestureDetector(onTap: widget.onTap, child: child);
    return Semantics(label: widget.fallback, child: tappable);
  }

  void _reportFailure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_failed) {
        setState(() => _failed = true);
      }
    });
  }
}

class _CookedImage extends StatefulWidget {
  const _CookedImage({
    required this.url,
    required this.width,
    required this.height,
    required this.fit,
    required this.errorHeight,
    required this.privateImage,
  });

  final String url;
  final int width;
  final int height;
  final BoxFit fit;
  final double errorHeight;
  final bool privateImage;

  @override
  State<_CookedImage> createState() => _CookedImageState();
}

class _CookedImageState extends State<_CookedImage> {
  Size? _decodedSize;

  @override
  void didUpdateWidget(covariant _CookedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _decodedSize = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final metadataSize = widget.width > 0 && widget.height > 0
            ? Size(widget.width.toDouble(), widget.height.toDouble())
            : null;
        final displaySize = ForumInlineImageLayout.displaySize(
          availableWidth: availableWidth,
          sourceSize: metadataSize ?? _decodedSize,
          fallbackHeight: widget.errorHeight,
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: displaySize.width,
            height: displaySize.height,
            child: _NetworkImage(
              url: widget.url,
              fit: widget.fit,
              onImageSize: metadataSize == null ? _handleImageSize : null,
              privateImage: widget.privateImage,
            ),
          ),
        );
      },
    );
  }

  void _handleImageSize(Size size) {
    if (!mounted || _decodedSize == size) {
      return;
    }
    setState(() => _decodedSize = size);
  }
}

class _NetworkImage extends StatelessWidget {
  const _NetworkImage({
    required this.url,
    required this.fit,
    this.onImageSize,
    this.privateImage = false,
  });

  final String url;
  final BoxFit fit;
  final ValueChanged<Size>? onImageSize;
  final bool privateImage;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return ColoredBox(
      color: colors.surfaceMuted,
      child: ForumNetworkImage(
        url,
        width: double.infinity,
        height: double.infinity,
        fit: fit,
        onImageSize: onImageSize,
        privateImage: privateImage,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Text(
              '图片加载失败',
              style: TextStyle(color: colors.textSecondary),
            ),
          );
        },
      ),
    );
  }
}

class _ForumPollCard extends StatefulWidget {
  const _ForumPollCard({
    required this.poll,
    required this.compact,
    required this.canManage,
    required this.busy,
    required this.onVote,
    required this.onToggleStatus,
  });

  final ForumPoll poll;
  final bool compact;
  final bool canManage;
  final bool busy;
  final ForumPollVoteCallback? onVote;
  final ForumPollStatusCallback? onToggleStatus;

  @override
  State<_ForumPollCard> createState() => _ForumPollCardState();
}

class _ForumPollCardState extends State<_ForumPollCard> {
  late Set<String> _selected = widget.poll.ownVotes.toSet();
  var _resultDisplay = _PollResultDisplay.count;

  @override
  void didUpdateWidget(covariant _ForumPollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poll.name != widget.poll.name ||
        oldWidget.poll.ownVotes.join('\u0001') !=
            widget.poll.ownVotes.join('\u0001')) {
      _selected = widget.poll.ownVotes.toSet();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final poll = widget.poll;
    final title = poll.title?.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _showDetails,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(12, widget.compact ? 10 : 12, 12, 12),
          decoration: BoxDecoration(
            border: Border.all(color: colors.borderStrong),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title == null || title.isEmpty ? '投票' : title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: widget.compact ? 14.5 : 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _PollResultToggle(
                    value: _resultDisplay,
                    onChanged: (value) {
                      setState(() => _resultDisplay = value);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                _pollMetaText(poll),
                style: TextStyle(color: colors.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              for (final option in poll.options) ...[
                _PollOptionRow(
                  poll: poll,
                  option: option,
                  selected: _selected.contains(option.id),
                  enabled: true,
                  showResults: poll.canShowResults,
                  resultDisplay: _resultDisplay,
                  dense: true,
                  showSelectedMark: false,
                  onTap: _showDetails,
                ),
                const SizedBox(height: 6),
              ],
              if (!poll.canShowResults)
                Text(
                  _hiddenResultText(poll),
                  style: TextStyle(color: colors.textMuted, fontSize: 12.5),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (context) {
        return _PollDetailSheet(
          poll: widget.poll,
          compact: widget.compact,
          canManage: widget.canManage,
          busy: widget.busy,
          onVote: widget.onVote,
          onToggleStatus: widget.onToggleStatus,
        );
      },
    );
  }
}

class _PollDetailSheet extends StatefulWidget {
  const _PollDetailSheet({
    required this.poll,
    required this.compact,
    required this.canManage,
    required this.busy,
    required this.onVote,
    required this.onToggleStatus,
  });

  final ForumPoll poll;
  final bool compact;
  final bool canManage;
  final bool busy;
  final ForumPollVoteCallback? onVote;
  final ForumPollStatusCallback? onToggleStatus;

  @override
  State<_PollDetailSheet> createState() => _PollDetailSheetState();
}

class _PollDetailSheetState extends State<_PollDetailSheet> {
  late final Set<String> _selected = widget.poll.ownVotes.toSet();
  bool _busy = false;

  bool get _isBusy => widget.busy || _busy;
  bool get _selectionChanged {
    final original = widget.poll.ownVotes.toSet();
    if (_selected.length != original.length) {
      return true;
    }
    return _selected.any((optionId) => !original.contains(optionId));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final poll = widget.poll;
    final title = poll.title?.trim();
    final canVote = poll.isOpen && widget.onVote != null && !_isBusy;
    final canSubmitVote = canVote &&
        (!poll.hasVoted || _selectionChanged) &&
        _selected.isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.how_to_vote_outlined,
                    size: 19, color: colors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title == null || title.isEmpty ? '投票' : title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _PollStatusChip(poll: poll),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _pollMetaText(poll),
              style: TextStyle(color: colors.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (poll.canShowResults && poll.chartType == 'pie') ...[
                    _PollPieResult(poll: poll),
                    const SizedBox(height: 12),
                  ],
                  for (final option in poll.options) ...[
                    _PollOptionRow(
                      poll: poll,
                      option: option,
                      selected: _selected.contains(option.id),
                      enabled: canVote,
                      showResults: poll.canShowResults,
                      resultDisplay: _PollResultDisplay.count,
                      onTap: () => _toggleOption(option),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (!poll.canShowResults) ...[
                    const SizedBox(height: 2),
                    Text(
                      _hiddenResultText(poll),
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  if (poll.isOpen) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            poll.isMultiple
                                ? '请选择 ${poll.effectiveMin}-${poll.effectiveMax} 项'
                                : '请选择 1 项',
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        FilledButton(
                          onPressed: canSubmitVote ? _submitVote : null,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(76, 34),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: _isBusy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : Text(poll.hasVoted ? '改票' : '投票'),
                        ),
                      ],
                    ),
                  ],
                  if (poll.public && _hasPreloadedVoters(poll)) ...[
                    const SizedBox(height: 16),
                    Text(
                      '投票人',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    for (final option in poll.options)
                      if (poll.votersForOption(option.id).isNotEmpty)
                        _PollVoterGroup(
                          option: option,
                          voters: poll.votersForOption(option.id),
                        ),
                  ],
                  if (widget.canManage && widget.onToggleStatus != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isBusy ? null : _toggleStatus,
                        child: Text(poll.isOpen ? '关闭投票' : '开启投票'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleOption(ForumPollOption option) {
    final poll = widget.poll;
    if (!poll.isOpen || _isBusy || widget.onVote == null) {
      return;
    }
    if (poll.isRegular) {
      setState(() {
        _selected
          ..clear()
          ..add(option.id);
      });
      return;
    }
    setState(() {
      if (_selected.contains(option.id)) {
        _selected.remove(option.id);
        return;
      }
      if (_selected.length >= poll.effectiveMax) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('最多选择 ${poll.effectiveMax} 项')),
        );
        return;
      }
      _selected.add(option.id);
    });
  }

  Future<void> _submitVote() async {
    final poll = widget.poll;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择投票选项')),
      );
      return;
    }
    if (_selected.length < poll.effectiveMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('至少选择 ${poll.effectiveMin} 项')),
      );
      return;
    }
    if (_selected.length > poll.effectiveMax) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('最多选择 ${poll.effectiveMax} 项')),
      );
      return;
    }
    setState(() => _busy = true);
    await widget.onVote?.call(poll, _selected.toList(growable: false));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _toggleStatus() async {
    final poll = widget.poll;
    final nextStatus = poll.isOpen ? 'closed' : 'open';
    final confirmed = await _confirm(
      context,
      title: poll.isOpen ? '关闭投票？' : '重新开启投票？',
      message: poll.isOpen ? '关闭后用户将无法继续投票。' : '开启后用户可以继续投票。',
      actionText: poll.isOpen ? '关闭' : '开启',
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    await widget.onToggleStatus?.call(poll, nextStatus);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  static Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String actionText,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(actionText),
            ),
          ],
        );
      },
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.poll,
    required this.option,
    required this.selected,
    required this.enabled,
    required this.showResults,
    required this.resultDisplay,
    required this.onTap,
    this.dense = false,
    this.showSelectedMark = true,
  });

  final ForumPoll poll;
  final ForumPollOption option;
  final bool selected;
  final bool enabled;
  final bool showResults;
  final _PollResultDisplay resultDisplay;
  final VoidCallback onTap;
  final bool dense;
  final bool showSelectedMark;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final denominator = poll.resultDenominator;
    final percent = denominator <= 0 ? 0.0 : option.votes / denominator;
    final optionText = _optionText(option);
    final metricText = _pollOptionMetricText(poll, option, resultDisplay);
    final background = selected ? colors.accentSoft : colors.surfaceMuted;
    final fillColor = selected
        ? colors.accent.withValues(alpha: 0.18)
        : colors.accentSoft.withValues(alpha: 0.64);
    final radius = BorderRadius.circular(6);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: enabled ? onTap : null,
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: background),
              ),
              if (showResults && poll.chartType != 'pie')
                Positioned.fill(
                  child: FractionallySizedBox(
                    widthFactor: percent.clamp(0, 1).toDouble(),
                    alignment: Alignment.centerLeft,
                    child: ColoredBox(color: fillColor),
                  ),
                ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: dense ? 10 : 12,
                  vertical: dense ? 7 : 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        optionText,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: dense ? 13.5 : 14.5,
                          height: 1.25,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (showResults) ...[
                      const SizedBox(width: 8),
                      Text(
                        metricText,
                        style: TextStyle(
                          color: selected ? colors.accent : colors.textMuted,
                          fontSize: dense ? 11.5 : 12.5,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                    if (showSelectedMark && selected) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check, size: 18, color: colors.accent),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PollPieResult extends StatelessWidget {
  const _PollPieResult({required this.poll});

  final ForumPoll poll;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 88,
          child: CustomPaint(
            painter: _PollPiePainter(
              poll: poll,
              colors: _pollPalette(colors),
              emptyColor: colors.surfaceMuted,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < poll.options.length; index += 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _pollPalette(
                              colors)[index % _pollPalette(colors).length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _optionText(poll.options[index]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PollPiePainter extends CustomPainter {
  const _PollPiePainter({
    required this.poll,
    required this.colors,
    required this.emptyColor,
  });

  final ForumPoll poll;
  final List<Color> colors;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final total = poll.totalOptionVotes;
    final paint = Paint()..style = PaintingStyle.fill;
    if (total <= 0) {
      paint.color = emptyColor;
      canvas.drawArc(rect, 0, math.pi * 2, true, paint);
      return;
    }
    var start = -math.pi / 2;
    for (var index = 0; index < poll.options.length; index += 1) {
      final option = poll.options[index];
      if (option.votes <= 0) {
        continue;
      }
      final sweep = math.pi * 2 * option.votes / total;
      paint.color = colors[index % colors.length];
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PollPiePainter oldDelegate) {
    return oldDelegate.poll != poll ||
        oldDelegate.colors != colors ||
        oldDelegate.emptyColor != emptyColor;
  }
}

class _PollStatusChip extends StatelessWidget {
  const _PollStatusChip({required this.poll});

  final ForumPoll poll;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: poll.isOpen ? colors.accentSoft : colors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        poll.isOpen ? (poll.isMultiple ? '多选' : '单选') : '已关闭',
        style: TextStyle(
          color: poll.isOpen ? colors.onAccentSoft : colors.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PollResultToggle extends StatelessWidget {
  const _PollResultToggle({
    required this.value,
    required this.onChanged,
  });

  final _PollResultDisplay value;
  final ValueChanged<_PollResultDisplay> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final showingCount = value == _PollResultDisplay.count;
    return Tooltip(
      message: showingCount ? '显示人数' : '显示百分比',
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: () {
          onChanged(
            showingCount
                ? _PollResultDisplay.percent
                : _PollResultDisplay.count,
          );
        },
        child: SizedBox(
          width: 35,
          height: 33,
          child: Icon(
            showingCount ? Icons.person_outline : Icons.percent,
            size: 17,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PollVoterGroup extends StatelessWidget {
  const _PollVoterGroup({
    required this.option,
    required this.voters,
  });

  final ForumPollOption option;
  final List<ForumPollVoter> voters;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _optionText(option),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          for (final voter in voters)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  ForumAvatar(url: voter.avatarUrl(), size: 28),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      voter.username,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InlineLink extends StatelessWidget {
  const _InlineLink({
    required this.preview,
    required this.onTap,
  });

  final CookedLinkPreview preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    if (preview.isInternalUser) {
      return InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            preview.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.accent,
              fontSize: 14.5,
              height: 1.32,
            ),
          ),
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.link, size: 17, color: colors.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                preview.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 14.5,
                  height: 1.32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OneboxCard extends StatelessWidget {
  const _OneboxCard({
    required this.preview,
    required this.isQuote,
    required this.compact,
    required this.onTap,
  });

  final CookedLinkPreview preview;
  final bool isQuote;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final thumbnailUrl = preview.thumbnailUrl;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.borderStrong),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 9 : 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (thumbnailUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: compact ? 92 : 112,
                    width: double.infinity,
                    child: ForumNetworkImage(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: colors.surfaceMuted,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: colors.textMuted,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 9),
              ],
              _SourceLine(preview: preview, isQuote: isQuote),
              const SizedBox(height: 6),
              Text(
                preview.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: compact ? 14.5 : 15,
                  height: 1.28,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (preview.excerpt != null) ...[
                const SizedBox(height: 5),
                Text(
                  preview.excerpt!,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: compact ? 13 : 13.5,
                    height: 1.36,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({
    required this.preview,
    required this.isQuote,
  });

  final CookedLinkPreview preview;
  final bool isQuote;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final iconUrl = preview.siteIconUrl;
    return Row(
      children: [
        if (iconUrl == null)
          Icon(
            isQuote ? Icons.forum_outlined : Icons.public,
            size: 16,
            color: colors.textMuted,
          )
        else
          ClipOval(
            child: SizedBox.square(
              dimension: 16,
              child: ForumNetworkImage(
                iconUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(Icons.public, size: 16, color: colors.textMuted);
                },
              ),
            ),
          ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            preview.source?.isNotEmpty == true ? preview.source! : preview.url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12.5,
              height: 1.2,
            ),
          ),
        ),
        Icon(Icons.open_in_new, size: 14, color: colors.textMuted),
      ],
    );
  }
}
