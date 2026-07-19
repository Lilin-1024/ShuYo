import 'package:flutter/material.dart';

import '../../core/forum_url_resolver.dart';
import '../../data/models/composer.dart';
import '../theme/lehu_theme.dart';
import 'forum_network_image.dart';

String composeRawWithImages(String text, List<UploadedImage> images) {
  final trimmed = text.trim();
  if (images.isEmpty) {
    return trimmed;
  }
  final imageMarkdown = images.map((image) => image.markdown).join('\n');
  if (trimmed.isEmpty) {
    return imageMarkdown;
  }
  return '$trimmed\n\n$imageMarkdown';
}

class ComposerAttachmentPreviewRow extends StatelessWidget {
  const ComposerAttachmentPreviewRow({
    super.key,
    required this.images,
    required this.onRemove,
  });

  final List<UploadedImage> images;
  final ValueChanged<UploadedImage>? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = images[index];
          return _AttachmentPreviewTile(
            image: image,
            onRemove: onRemove == null ? null : () => onRemove!(image),
          );
        },
      ),
    );
  }
}

class _AttachmentPreviewTile extends StatelessWidget {
  const _AttachmentPreviewTile({
    required this.image,
    required this.onRemove,
  });

  final UploadedImage image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = context.lehuColors;
    return SizedBox(
      width: 74,
      height: 74,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: colors.surfaceMuted,
                child: image.url.isEmpty
                    ? const _AttachmentImageFallback()
                    : ForumNetworkImage(
                        ForumUrlResolver.resolve(image.url),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const _AttachmentImageFallback();
                        },
                      ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.borderStrong),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: -6,
            child: IconButton.filled(
              tooltip: '移除图片',
              onPressed: onRemove,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(24),
                fixedSize: const Size.square(24),
                padding: EdgeInsets.zero,
                backgroundColor: colorScheme.surface,
                foregroundColor: colorScheme.onSurface,
                disabledBackgroundColor: colors.disabledFill,
                disabledForegroundColor: colors.textMuted,
              ),
              icon: const Icon(Icons.close, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentImageFallback extends StatelessWidget {
  const _AttachmentImageFallback();

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 26,
        color: colors.textTertiary,
      ),
    );
  }
}
