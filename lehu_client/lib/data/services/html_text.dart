import '../../core/forum_constants.dart';
import 'emoji_text.dart';

class CookedSegment {
  const CookedSegment.text(this.value) : isImage = false;
  const CookedSegment.image(this.value) : isImage = true;

  final String value;
  final bool isImage;
}

class TopicPreview {
  const TopicPreview({
    required this.text,
    required this.imageUrls,
  });

  final String text;
  final List<String> imageUrls;

  bool get hasText => text.isNotEmpty;
  bool get hasImages => imageUrls.isNotEmpty;
}

class HtmlText {
  const HtmlText._();

  static final _imagePattern = RegExp(r'<img\b[^>]*>', caseSensitive: false);
  static final _attributePattern = RegExp(
    r'([a-zA-Z_:][-a-zA-Z0-9_:.]*)="([^"]*)"',
    caseSensitive: false,
  );
  static final _metadataPattern = RegExp(
    r'<div\b[^>]*class="[^"]*\bmeta\b[^"]*"[^>]*>.*?</div>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _attachmentInfoPattern = RegExp(
    r'\b[\w.-]+\s*·\s*\d+\s*[×x]\s*\d+\s+\d+(?:\.\d+)?\s*(?:KB|MB|GB)\b',
    caseSensitive: false,
  );
  static final _tagPattern = RegExp(r'<[^>]+>');

  static String toPlainText(String html) {
    final text = _withoutAttachmentMetadata(html)
        .replaceAllMapped(_imagePattern, (match) {
          final image = _HtmlImage.fromTag(match.group(0) ?? '');
          return image.shouldRenderAsImage ? '' : image.inlineText;
        })
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>|</h[1-6]>', caseSensitive: false), '\n')
        .replaceAll(_tagPattern, '')
        .replaceAll(_attachmentInfoPattern, '')
        .trim();
    final decoded = _decodeEntities(text).replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return EmojiText.render(decoded);
  }

  static String preview(String html, {int maxLength = 72}) {
    final plain = toPlainText(html).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (plain.isEmpty) {
      return '[图片]';
    }
    if (plain.length <= maxLength) {
      return plain;
    }
    return '${plain.substring(0, maxLength)}...';
  }

  static TopicPreview topicPreview(String html, {int maxLength = 72}) {
    final text = toPlainText(html).replaceAll(RegExp(r'\s+'), ' ').trim();
    return TopicPreview(
      text: text.length <= maxLength
          ? text
          : '${text.substring(0, maxLength)}...',
      imageUrls: imageUrls(html),
    );
  }

  static List<String> imageUrls(String html) {
    return _imagePattern
        .allMatches(html)
        .map((match) => _HtmlImage.fromTag(match.group(0) ?? ''))
        .where((image) => image.shouldRenderAsImage)
        .map((image) => _absoluteUrl(image.src))
        .toList(growable: false);
  }

  static List<CookedSegment> parseSegments(String html) {
    final segments = <CookedSegment>[];
    void addText(String value) {
      if (value.isEmpty) {
        return;
      }
      if (segments.isNotEmpty && !segments.last.isImage) {
        segments[segments.length - 1] = CookedSegment.text(
          '${segments.last.value}$value',
        );
        return;
      }
      segments.add(CookedSegment.text(value));
    }

    var cursor = 0;
    for (final match in _imagePattern.allMatches(html)) {
      final before = html.substring(cursor, match.start);
      final text = toPlainText(before);
      addText(text);
      final image = _HtmlImage.fromTag(match.group(0) ?? '');
      if (image.shouldRenderAsImage) {
        segments.add(CookedSegment.image(_absoluteUrl(image.src)));
      } else if (image.inlineText.isNotEmpty) {
        addText(image.inlineText);
      }
      cursor = match.end;
    }
    final tail = toPlainText(html.substring(cursor));
    addText(tail);
    if (segments.isEmpty && html.contains('<img')) {
      segments.add(const CookedSegment.text('[图片]'));
    }
    return segments;
  }

  static String _withoutAttachmentMetadata(String html) {
    return html.replaceAll(_metadataPattern, '');
  }

  static String _absoluteUrl(String url) {
    if (url.startsWith('http')) {
      return url;
    }
    return '${ForumConstants.baseUrl}$url';
  }

  static String _decodeEntities(String value) {
    return value
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}

class _HtmlImage {
  const _HtmlImage({
    required this.src,
    required this.alt,
    required this.width,
    required this.height,
  });

  final String src;
  final String alt;
  final int width;
  final int height;

  bool get shouldRenderAsImage {
    if (src.isEmpty || src.contains('/emoji/')) {
      return false;
    }
    if (width > 0 && height > 0 && width <= 32 && height <= 32) {
      return false;
    }
    return true;
  }

  String get inlineText {
    if (alt.isEmpty) {
      return '';
    }
    return EmojiText.render(alt);
  }

  factory _HtmlImage.fromTag(String tag) {
    final attrs = <String, String>{};
    for (final match in HtmlText._attributePattern.allMatches(tag)) {
      attrs[(match.group(1) ?? '').toLowerCase()] = match.group(2) ?? '';
    }
    return _HtmlImage(
      src: attrs['src'] ?? '',
      alt: attrs['alt'] ?? attrs['title'] ?? '',
      width: int.tryParse(attrs['width'] ?? '') ?? 0,
      height: int.tryParse(attrs['height'] ?? '') ?? 0,
    );
  }
}
