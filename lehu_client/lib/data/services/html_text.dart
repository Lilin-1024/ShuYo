import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/forum_url_resolver.dart';
import 'emoji_text.dart';

enum CookedSegmentKind { text, image, link, onebox, quote }

class CookedLinkPreview {
  const CookedLinkPreview({
    required this.url,
    required this.title,
    this.source,
    this.excerpt,
    this.thumbnailUrl,
    this.siteIconUrl,
    this.topicId,
    this.postNumber,
    this.userUsername,
  });

  final String url;
  final String title;
  final String? source;
  final String? excerpt;
  final String? thumbnailUrl;
  final String? siteIconUrl;
  final int? topicId;
  final int? postNumber;
  final String? userUsername;

  bool get isInternalTopic => topicId != null;
  bool get isInternalUser => userUsername != null && userUsername!.isNotEmpty;
}

class CookedSegment {
  const CookedSegment.text(this.value)
      : kind = CookedSegmentKind.text,
        link = null,
        imageWidth = 0,
        imageHeight = 0;
  const CookedSegment.image(
    this.value, {
    this.imageWidth = 0,
    this.imageHeight = 0,
  })  : kind = CookedSegmentKind.image,
        link = null;
  const CookedSegment.link(this.link)
      : kind = CookedSegmentKind.link,
        value = '',
        imageWidth = 0,
        imageHeight = 0;
  const CookedSegment.onebox(this.link)
      : kind = CookedSegmentKind.onebox,
        value = '',
        imageWidth = 0,
        imageHeight = 0;
  const CookedSegment.quote(this.link)
      : kind = CookedSegmentKind.quote,
        value = '',
        imageWidth = 0,
        imageHeight = 0;

  final String value;
  final CookedSegmentKind kind;
  final CookedLinkPreview? link;
  final int imageWidth;
  final int imageHeight;

  bool get isImage => kind == CookedSegmentKind.image;
  bool get isText => kind == CookedSegmentKind.text;
  bool get isLink => kind == CookedSegmentKind.link;
  bool get isOnebox => kind == CookedSegmentKind.onebox;
  bool get isQuote => kind == CookedSegmentKind.quote;
}

class TopicPreview {
  const TopicPreview({
    required this.text,
    required this.images,
  });

  final String text;
  final List<TopicPreviewImage> images;

  bool get hasText => text.isNotEmpty;
  bool get hasImages => images.isNotEmpty;

  List<String> get imageUrls =>
      images.map((image) => image.url).toList(growable: false);
}

class TopicPreviewImage {
  const TopicPreviewImage({
    required this.url,
    required this.width,
    required this.height,
  });

  final String url;
  final int width;
  final int height;

  double? get aspectRatio {
    if (width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
  }
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
      images: images(html),
    );
  }

  static List<String> imageUrls(String html) {
    return images(html).map((image) => image.url).toList(growable: false);
  }

  static List<TopicPreviewImage> images(String html) {
    return _imagePattern
        .allMatches(html)
        .map((match) => _HtmlImage.fromTag(match.group(0) ?? ''))
        .where((image) => image.shouldRenderAsImage)
        .map(
          (image) => TopicPreviewImage(
            url: _absoluteUrl(image.src),
            width: image.width,
            height: image.height,
          ),
        )
        .toList(growable: false);
  }

  static List<CookedSegment> parseSegments(String html) {
    final segments = <CookedSegment>[];
    void addText(String value) {
      if (value.isEmpty) {
        return;
      }
      if (segments.isNotEmpty && segments.last.isText) {
        segments[segments.length - 1] = CookedSegment.text(
          '${segments.last.value}$value',
        );
        return;
      }
      segments.add(CookedSegment.text(value));
    }

    void addBlockBreak() {
      addText('\n');
    }

    void appendNode(dom.Node node) {
      if (node is dom.Text) {
        addText(node.text);
        return;
      }
      if (node is! dom.Element) {
        for (final child in node.nodes) {
          appendNode(child);
        }
        return;
      }

      if (_hasOwnClass(node, 'meta')) {
        return;
      }
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'aside' && _hasClass(node, 'onebox')) {
        final preview = _oneboxPreview(node);
        if (preview != null) {
          segments.add(CookedSegment.onebox(preview));
        }
        return;
      }
      if (tag == 'aside' && _hasClass(node, 'quote')) {
        final preview = _quotePreview(node);
        if (preview != null) {
          segments.add(CookedSegment.quote(preview));
        }
        return;
      }
      if (tag == 'img') {
        final image = _HtmlImage.fromElement(node);
        if (image.shouldRenderAsImage) {
          segments.add(
            CookedSegment.image(
              _absoluteUrl(image.src),
              imageWidth: image.width,
              imageHeight: image.height,
            ),
          );
        } else if (image.inlineText.isNotEmpty) {
          addText(image.inlineText);
        }
        return;
      }
      if (tag == 'a') {
        if (_containsRenderableImage(node)) {
          for (final child in node.nodes) {
            appendNode(child);
          }
          return;
        }
        final preview = _linkPreview(node);
        if (preview != null) {
          segments.add(
            _hasClass(node, 'onebox')
                ? CookedSegment.onebox(preview)
                : CookedSegment.link(preview),
          );
          return;
        }
      }
      if (tag == 'br') {
        addBlockBreak();
        return;
      }

      for (final child in node.nodes) {
        appendNode(child);
      }
      if (_isBlockElement(tag)) {
        addBlockBreak();
      }
    }

    final document = html_parser.parse(
      '<!doctype html><html><body>${_withoutAttachmentMetadata(html)}</body></html>',
    );
    final nodes = document.body?.nodes ?? document.nodes;
    for (final node in nodes) {
      appendNode(node);
    }
    final normalized = _normalizeSegments(segments);
    segments
      ..clear()
      ..addAll(normalized);
    if (segments.isEmpty && html.contains('<img')) {
      segments.add(const CookedSegment.text('[图片]'));
    }
    return segments;
  }

  static String _withoutAttachmentMetadata(String html) {
    return html.replaceAll(_metadataPattern, '');
  }

  static String _absoluteUrl(String url) {
    return ForumUrlResolver.resolve(url);
  }

  static List<CookedSegment> _normalizeSegments(List<CookedSegment> segments) {
    final normalized = <CookedSegment>[];
    for (final segment in segments) {
      if (!segment.isText) {
        normalized.add(segment);
        continue;
      }
      final text = _normalizeDomText(segment.value);
      if (text.isEmpty) {
        continue;
      }
      if (normalized.isNotEmpty && normalized.last.isText) {
        normalized[normalized.length - 1] = CookedSegment.text(
          '${normalized.last.value}\n$text',
        );
      } else {
        normalized.add(CookedSegment.text(text));
      }
    }
    return normalized;
  }

  static CookedLinkPreview? _oneboxPreview(dom.Element aside) {
    final sourceAnchor = aside.querySelector('header.source a');
    final titleAnchor = aside.querySelector('article.onebox-body h3 a') ??
        aside.querySelector('h3 a') ??
        sourceAnchor;
    final rawUrl = aside.attributes['data-onebox-src'] ??
        titleAnchor?.attributes['href'] ??
        sourceAnchor?.attributes['href'] ??
        '';
    final url = _absoluteUrl(rawUrl);
    if (url.trim().isEmpty) {
      return null;
    }
    final title = _cleanInlineText(titleAnchor?.text);
    final excerpt = _cleanInlineText(
      aside.querySelector('article.onebox-body p')?.text,
    );
    final thumbnail =
        aside.querySelector('article.onebox-body img.thumbnail') ??
            aside.querySelector('article.onebox-body img');
    final siteIcon = aside.querySelector('header.source img.site-icon');
    return CookedLinkPreview(
      url: url,
      title: title.isNotEmpty ? title : url,
      source: _cleanInlineText(sourceAnchor?.text).ifEmpty(_hostForUrl(url)),
      excerpt: excerpt.isEmpty ? null : excerpt,
      thumbnailUrl: _imageSource(thumbnail),
      siteIconUrl: _imageSource(siteIcon),
      topicId: internalTopicIdFromUrl(url),
      postNumber: internalPostNumberFromUrl(url),
    );
  }

  static CookedLinkPreview? _quotePreview(dom.Element aside) {
    final titleAnchor = aside.querySelector('.title a[href*="/t/"]') ??
        aside.querySelector('a[href*="/t/"]');
    final rawUrl = titleAnchor?.attributes['href'] ?? '';
    final topicId = int.tryParse(aside.attributes['data-topic'] ?? '') ??
        internalTopicIdFromUrl(rawUrl);
    if (topicId == null) {
      return null;
    }
    final postNumber = int.tryParse(aside.attributes['data-post'] ?? '') ??
        internalPostNumberFromUrl(rawUrl);
    final title = _cleanInlineText(titleAnchor?.text);
    final excerpt = _cleanInlineText(aside.querySelector('blockquote')?.text);
    final url = rawUrl.trim().isEmpty ? '/t/topic/$topicId' : rawUrl;
    return CookedLinkPreview(
      url: _absoluteUrl(url),
      title: title.isNotEmpty ? title : '帖子 #$topicId',
      source: '乐乎帖子',
      excerpt: excerpt.isEmpty ? null : excerpt,
      topicId: topicId,
      postNumber: postNumber,
    );
  }

  static CookedLinkPreview? _linkPreview(dom.Element anchor) {
    final rawUrl = anchor.attributes['href'] ?? '';
    if (rawUrl.trim().isEmpty) {
      return null;
    }
    final url = _absoluteUrl(rawUrl);
    final title = _cleanInlineText(anchor.text);
    return CookedLinkPreview(
      url: url,
      title: title.isNotEmpty ? title : url,
      source: _hostForUrl(url),
      topicId: internalTopicIdFromUrl(url),
      postNumber: internalPostNumberFromUrl(url),
      userUsername: internalUsernameFromUrl(url),
    );
  }

  static bool _containsRenderableImage(dom.Element element) {
    return element
        .querySelectorAll('img')
        .map(_HtmlImage.fromElement)
        .any((image) => image.shouldRenderAsImage);
  }

  static int? internalTopicIdFromUrl(String value) {
    final uri = _uriForLink(value);
    if (uri == null || !ForumUrlResolver.isKnownForumHost(uri.host)) {
      return null;
    }
    final segments = uri.pathSegments;
    final topicIndex = segments.indexOf('t');
    if (topicIndex < 0 || topicIndex + 1 >= segments.length) {
      return null;
    }
    final direct = int.tryParse(segments[topicIndex + 1]);
    if (direct != null) {
      return direct;
    }
    if (topicIndex + 2 < segments.length) {
      return int.tryParse(segments[topicIndex + 2]);
    }
    return null;
  }

  static int? internalPostNumberFromUrl(String value) {
    final uri = _uriForLink(value);
    if (uri == null || !ForumUrlResolver.isKnownForumHost(uri.host)) {
      return null;
    }
    final topicId = internalTopicIdFromUrl(value);
    if (topicId == null) {
      return null;
    }
    final segments = uri.pathSegments;
    final topicIdIndex = segments.indexOf('$topicId');
    if (topicIdIndex < 0 || topicIdIndex + 1 >= segments.length) {
      return null;
    }
    return int.tryParse(segments[topicIdIndex + 1]);
  }

  static String? internalUsernameFromUrl(String value) {
    final uri = _uriForLink(value);
    if (uri == null || !ForumUrlResolver.isKnownForumHost(uri.host)) {
      return null;
    }
    final segments = uri.pathSegments;
    final userIndex = segments.indexOf('u');
    if (userIndex < 0 || userIndex + 1 >= segments.length) {
      return null;
    }
    var username = segments[userIndex + 1].trim();
    if (username.endsWith('.json')) {
      username = username.substring(0, username.length - 5);
    }
    return username.isEmpty ? null : Uri.decodeComponent(username);
  }

  static Uri? _uriForLink(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('/')) {
      return Uri.tryParse('${ForumUrlResolver.baseUrl}$trimmed');
    }
    return Uri.tryParse(ForumUrlResolver.resolve(trimmed));
  }

  static String? _imageSource(dom.Element? image) {
    final src = image?.attributes['src'] ?? '';
    if (src.trim().isEmpty) {
      return null;
    }
    return _absoluteUrl(src);
  }

  static bool _hasClass(dom.Element element, String className) {
    if (_hasOwnClass(element, className)) {
      return true;
    }
    final outerHtml = element.outerHtml;
    final openingEnd = outerHtml.indexOf('>');
    final openingTag =
        openingEnd < 0 ? outerHtml : outerHtml.substring(0, openingEnd + 1);
    return RegExp(
      r'''class\s*=\s*["'][^"']*\b''' +
          RegExp.escape(className) +
          r'''\b[^"']*["']''',
      caseSensitive: false,
    ).hasMatch(openingTag);
  }

  static bool _hasOwnClass(dom.Element element, String className) {
    final classes = element.attributes['class'] ?? '';
    return classes
        .split(RegExp(r'\s+'))
        .where((value) => value.isNotEmpty)
        .contains(className);
  }

  static bool _isBlockElement(String tag) {
    return const {
      'address',
      'article',
      'blockquote',
      'div',
      'footer',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'header',
      'li',
      'ol',
      'p',
      'pre',
      'section',
      'ul',
    }.contains(tag);
  }

  static String _hostForUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri?.host ?? '';
  }

  static String _cleanInlineText(String? value) {
    return EmojiText.render(
      (value ?? '')
          .replaceAll('\u00a0', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
  }

  static String _normalizeDomText(String value) {
    return EmojiText.render(
      value
          .replaceAll('\u00a0', ' ')
          .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
          .replaceAll(RegExp(r' *\n *'), '\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim(),
    );
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

  factory _HtmlImage.fromElement(dom.Element element) {
    return _HtmlImage(
      src: element.attributes['src'] ?? '',
      alt: element.attributes['alt'] ?? element.attributes['title'] ?? '',
      width: int.tryParse(element.attributes['width'] ?? '') ?? 0,
      height: int.tryParse(element.attributes['height'] ?? '') ?? 0,
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
