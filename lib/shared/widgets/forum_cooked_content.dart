import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/html_text.dart';
import '../theme/lehu_theme.dart';
import 'forum_network_image.dart';

class ForumCookedContent extends StatelessWidget {
  const ForumCookedContent({
    super.key,
    required this.cooked,
    required this.textColor,
    required this.onOpenImage,
    this.onOpenUser,
    this.onOpenInternalTopic,
    this.textSize = 16,
    this.textHeight = 1.46,
    this.textWeight = FontWeight.w400,
    this.textBottomSpacing = 8,
    this.imageBottomSpacing = 10,
    this.imageErrorHeight = 160,
    this.imageFit = BoxFit.cover,
    this.compactCards = false,
  });

  final String cooked;
  final Color textColor;
  final void Function(List<String> urls, int initialIndex) onOpenImage;
  final ValueChanged<String>? onOpenUser;
  final ValueChanged<CookedLinkPreview>? onOpenInternalTopic;
  final double textSize;
  final double textHeight;
  final FontWeight textWeight;
  final double textBottomSpacing;
  final double imageBottomSpacing;
  final double imageErrorHeight;
  final BoxFit imageFit;
  final bool compactCards;

  @override
  Widget build(BuildContext context) {
    final segments = HtmlText.parseSegments(cooked);
    if (segments.isEmpty) {
      return Text(' ', style: TextStyle(color: textColor));
    }
    final imageUrls = [
      for (final segment in segments)
        if (segment.isImage) segment.value,
    ];
    final contentWidgets = <Widget>[];
    var imageIndex = 0;
    for (final segment in segments) {
      switch (segment.kind) {
        case CookedSegmentKind.text:
          contentWidgets.add(
            Padding(
              padding: EdgeInsets.only(bottom: textBottomSpacing),
              child: Text(
                segment.value,
                style: TextStyle(
                  color: textColor,
                  fontSize: textSize,
                  height: textHeight,
                  fontWeight: textWeight,
                ),
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
    if (preview.isInternalTopic && onOpenInternalTopic != null) {
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

class _CookedImage extends StatelessWidget {
  const _CookedImage({
    required this.url,
    required this.width,
    required this.height,
    required this.fit,
    required this.errorHeight,
  });

  final String url;
  final int width;
  final int height;
  final BoxFit fit;
  final double errorHeight;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = width > 0 && height > 0 ? width / height : null;
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: aspectRatio == null
          ? SizedBox(
              width: double.infinity,
              height: errorHeight,
              child: _NetworkImage(url: url, fit: fit),
            )
          : AspectRatio(
              aspectRatio: aspectRatio,
              child: _NetworkImage(url: url, fit: fit),
            ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      child: child,
    );
  }
}

class _NetworkImage extends StatelessWidget {
  const _NetworkImage({
    required this.url,
    required this.fit,
  });

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return ColoredBox(
      color: colors.surfaceMuted,
      child: ForumNetworkImage(
        url,
        width: double.infinity,
        height: double.infinity,
        fit: fit,
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

class _InlineLink extends StatelessWidget {
  const _InlineLink({
    required this.preview,
    required this.onTap,
  });

  final CookedLinkPreview preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
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
    final colors = context.lehuColors;
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
    final colors = context.lehuColors;
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
