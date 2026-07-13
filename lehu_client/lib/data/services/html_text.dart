import '../../core/forum_constants.dart';

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

  static final _imagePattern =
      RegExp(r'<img\b[^>]*\bsrc="([^"]+)"[^>]*>', caseSensitive: false);
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
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>|</h[1-6]>', caseSensitive: false), '\n')
        .replaceAll(_tagPattern, '')
        .replaceAll(_attachmentInfoPattern, '')
        .trim();
    return _decodeEntities(text).replaceAll(RegExp(r'\n{3,}'), '\n\n');
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
        .map((match) => match.group(1))
        .whereType<String>()
        .where((src) => !src.contains('/emoji/'))
        .map(_absoluteUrl)
        .toList(growable: false);
  }

  static List<CookedSegment> parseSegments(String html) {
    final segments = <CookedSegment>[];
    var cursor = 0;
    for (final match in _imagePattern.allMatches(html)) {
      final before = html.substring(cursor, match.start);
      final text = toPlainText(before);
      if (text.isNotEmpty) {
        segments.add(CookedSegment.text(text));
      }
      final src = match.group(1);
      if (src != null && !src.contains('/emoji/')) {
        segments.add(CookedSegment.image(_absoluteUrl(src)));
      }
      cursor = match.end;
    }
    final tail = toPlainText(html.substring(cursor));
    if (tail.isNotEmpty) {
      segments.add(CookedSegment.text(tail));
    }
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
