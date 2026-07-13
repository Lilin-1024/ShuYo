import 'dart:typed_data';

class CreateTopicDraft {
  const CreateTopicDraft({
    required this.title,
    required this.raw,
    required this.categoryId,
    required this.draftKey,
    this.images = const [],
    this.typingDurationMs = 1000,
    this.composerOpenDurationMs = 3000,
  });

  final String title;
  final String raw;
  final int categoryId;
  final String draftKey;
  final List<UploadedImage> images;
  final int typingDurationMs;
  final int composerOpenDurationMs;
}

class PrivateMessageDraft {
  const PrivateMessageDraft({
    required this.title,
    required this.raw,
    required this.recipients,
    required this.draftKey,
    this.typingDurationMs = 1000,
    this.composerOpenDurationMs = 3000,
  });

  final String title;
  final String raw;
  final String recipients;
  final String draftKey;
  final int typingDurationMs;
  final int composerOpenDurationMs;
}

class UploadedImage {
  const UploadedImage({
    required this.url,
    required this.shortUrl,
    required this.filename,
    required this.width,
    required this.height,
    required this.thumbnailWidth,
    required this.thumbnailHeight,
  });

  final String url;
  final String shortUrl;
  final String filename;
  final int width;
  final int height;
  final int thumbnailWidth;
  final int thumbnailHeight;

  String get markdown {
    final displayWidth = thumbnailWidth == 0 ? width : thumbnailWidth;
    final displayHeight = thumbnailHeight == 0 ? height : thumbnailHeight;
    final size = displayWidth > 0 && displayHeight > 0
        ? '|${displayWidth}x$displayHeight'
        : '';
    return '![$filename$size]($shortUrl)';
  }
}

class PickedImage {
  const PickedImage({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}
