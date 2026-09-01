import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/forum_url_resolver.dart';
import '../../core/forum_constants.dart';
import '../models/forum_poll.dart';
import 'emoji_text.dart';

enum CookedSegmentKind { text, image, link, onebox, quote, poll }

enum CookedTextBlockKind { paragraph, heading, blockquote, listItem, codeBlock }

class CookedTextRun {
  const CookedTextRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.code = false,
    this.link,
    this.inlineEmojiUrl,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool code;
  final CookedLinkPreview? link;
  final String? inlineEmojiUrl;

  bool hasSameStyle(CookedTextRun other) {
    if (isInlineEmoji || other.isInlineEmoji) {
      return false;
    }
    return bold == other.bold &&
        italic == other.italic &&
        strikethrough == other.strikethrough &&
        code == other.code &&
        _hasSameLink(other.link);
  }

  CookedTextRun copyWith({String? text}) {
    return CookedTextRun(
      text ?? this.text,
      bold: bold,
      italic: italic,
      strikethrough: strikethrough,
      code: code,
      link: link,
      inlineEmojiUrl: inlineEmojiUrl,
    );
  }

  bool get isLink => link != null;
  bool get isInlineEmoji => inlineEmojiUrl != null;

  bool _hasSameLink(CookedLinkPreview? other) {
    final current = link;
    if (current == null || other == null) {
      return current == other;
    }
    return current.url == other.url &&
        current.title == other.title &&
        current.topicId == other.topicId &&
        current.postNumber == other.postNumber &&
        current.userUsername == other.userUsername;
  }
}

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

  bool get isInternalForumRoute {
    final uri = Uri.tryParse(url);
    if (uri == null || !ForumUrlResolver.isKnownForumHost(uri.host)) {
      return false;
    }
    return uri.path == '/latest' ||
        uri.path == '/latest/' ||
        uri.path == '/faq' ||
        uri.path == '/faq/' ||
        uri.path == '/my/preferences/account' ||
        uri.path == '/my/preferences/account/';
  }

  bool get isInternalTopic => topicId != null;
  bool get isInternalUser => userUsername != null && userUsername!.isNotEmpty;
}

class CookedSegment {
  const CookedSegment.text(this.value)
      : kind = CookedSegmentKind.text,
        runs = const [],
        textBlockKind = CookedTextBlockKind.paragraph,
        headingLevel = 0,
        listIndex = 0,
        listDepth = 0,
        link = null,
        poll = null,
        imageFullUrl = null,
        imageWidth = 0,
        imageHeight = 0;
  const CookedSegment.richText(
    this.runs, {
    this.textBlockKind = CookedTextBlockKind.paragraph,
    this.headingLevel = 0,
    this.listIndex = 0,
    this.listDepth = 0,
  })  : kind = CookedSegmentKind.text,
        value = '',
        link = null,
        poll = null,
        imageFullUrl = null,
        imageWidth = 0,
        imageHeight = 0;
  const CookedSegment.image(
    this.value, {
    this.imageFullUrl,
    this.imageWidth = 0,
    this.imageHeight = 0,
  })  : kind = CookedSegmentKind.image,
        runs = const [],
        textBlockKind = CookedTextBlockKind.paragraph,
        headingLevel = 0,
        listIndex = 0,
        listDepth = 0,
        link = null,
        poll = null;
  const CookedSegment.link(this.link)
      : kind = CookedSegmentKind.link,
        value = '',
        runs = const [],
        textBlockKind = CookedTextBlockKind.paragraph,
        headingLevel = 0,
        listIndex = 0,
        listDepth = 0,
        poll = null,
        imageFullUrl = null,
        imageWidth = 0,
        imageHeight = 0;
  const CookedSegment.onebox(this.link)
      : kind = CookedSegmentKind.onebox,
        value = '',
        runs = const [],
        textBlockKind = CookedTextBlockKind.paragraph,
        headingLevel = 0,
        listIndex = 0,
        listDepth = 0,
        poll = null,
        imageFullUrl = null,
        imageWidth = 0,
        imageHeight = 0;
  const CookedSegment.quote(this.link)
      : kind = CookedSegmentKind.quote,
        value = '',
        runs = const [],
        textBlockKind = CookedTextBlockKind.paragraph,
        headingLevel = 0,
        listIndex = 0,
        listDepth = 0,
        poll = null,
        imageFullUrl = null,
        imageWidth = 0,
        imageHeight = 0;
  const CookedSegment.poll(this.poll)
      : kind = CookedSegmentKind.poll,
        value = '',
        runs = const [],
        textBlockKind = CookedTextBlockKind.paragraph,
        headingLevel = 0,
        listIndex = 0,
        listDepth = 0,
        link = null,
        imageFullUrl = null,
        imageWidth = 0,
        imageHeight = 0;

  final String value;
  final CookedSegmentKind kind;
  final List<CookedTextRun> runs;
  final CookedTextBlockKind textBlockKind;
  final int headingLevel;
  final int listIndex;
  final int listDepth;
  final CookedLinkPreview? link;
  final ForumPoll? poll;
  final String? imageFullUrl;
  final int imageWidth;
  final int imageHeight;

  String get textValue {
    if (runs.isEmpty) {
      return value;
    }
    return runs.map((run) => run.text).join();
  }

  String get resolvedImageFullUrl => imageFullUrl ?? value;

  bool get isImage => kind == CookedSegmentKind.image;
  bool get isText => kind == CookedSegmentKind.text;
  bool get isLink => kind == CookedSegmentKind.link;
  bool get isOnebox => kind == CookedSegmentKind.onebox;
  bool get isQuote => kind == CookedSegmentKind.quote;
  bool get isPoll => kind == CookedSegmentKind.poll;
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

  static bool prefersPlainPrivateMessageText(String html) {
    final segments = parseSegments(html);
    if (segments.isEmpty || segments.any((segment) => !segment.isText)) {
      return false;
    }
    return segments.any((segment) {
      if (segment.textBlockKind != CookedTextBlockKind.paragraph) {
        return true;
      }
      return segment.runs.any((run) {
        return run.code || (run.link?.isInternalUser ?? false);
      });
    });
  }

  static TopicPreview topicPreview(String html, {int maxLength = 72}) {
    final text = _topicPreviewText(html, maxLength: maxLength);
    return TopicPreview(
      text: text,
      images: images(html),
    );
  }

  static List<String> imageUrls(String html) {
    return images(html).map((image) => image.url).toList(growable: false);
  }

  static String _topicPreviewText(String html, {required int maxLength}) {
    final parts = <String>[];
    for (final segment in parseSegments(html)) {
      final part = _topicPreviewPart(segment);
      if (part.isNotEmpty) {
        parts.add(part);
      }
    }
    final text = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty || text.length <= maxLength) {
      return text;
    }
    return '${text.substring(0, maxLength)}...';
  }

  static String _topicPreviewPart(CookedSegment segment) {
    if (segment.isText) {
      return segment.textValue;
    }
    if (segment.isPoll) {
      final title = segment.poll?.title?.trim() ?? '';
      return title.isEmpty ? '[投票]' : '[投票] $title';
    }
    if (segment.isOnebox) {
      final title = segment.link?.title.trim() ?? '';
      return title.isEmpty ? '[链接]' : '[链接] $title';
    }
    if (segment.isQuote) {
      final title = segment.link?.title.trim() ?? '';
      return title.isEmpty ? '[引用]' : '[引用] $title';
    }
    if (segment.isLink) {
      final title = segment.link?.title.trim() ?? '';
      return title.isEmpty ? '[链接]' : title;
    }
    return '';
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
    var inlineRuns = <CookedTextRun>[];
    var blockState = const _CookedTextBlockState();

    void flushText() {
      final normalized = _normalizeRuns(inlineRuns);
      inlineRuns = [];
      if (normalized.isEmpty) {
        return;
      }
      segments.add(
        CookedSegment.richText(
          normalized,
          textBlockKind: blockState.kind,
          headingLevel: blockState.headingLevel,
          listIndex: blockState.listIndex,
          listDepth: blockState.listDepth,
        ),
      );
    }

    void addRun(String value, _InlineTextStyle style) {
      if (value.isEmpty) {
        return;
      }
      final run = CookedTextRun(
        value,
        bold: style.bold,
        italic: style.italic,
        strikethrough: style.strikethrough,
        code: style.code,
        link: style.link,
      );
      if (inlineRuns.isNotEmpty && inlineRuns.last.hasSameStyle(run)) {
        inlineRuns[inlineRuns.length - 1] = inlineRuns.last.copyWith(
          text: '${inlineRuns.last.text}${run.text}',
        );
      } else {
        inlineRuns.add(run);
      }
    }

    void addInlineEmoji(_HtmlImage image, _InlineTextStyle style) {
      final text = image.inlineText;
      if (text.isEmpty || image.src.isEmpty) {
        addRun(text, style);
        return;
      }
      inlineRuns.add(
        CookedTextRun(
          text,
          bold: style.bold,
          italic: style.italic,
          strikethrough: style.strikethrough,
          code: style.code,
          link: style.link,
          inlineEmojiUrl: _absoluteUrl(image.src),
        ),
      );
    }

    void withBlock(_CookedTextBlockState state, void Function() callback) {
      flushText();
      final previous = blockState;
      blockState = state;
      callback();
      flushText();
      blockState = previous;
    }

    void addImage(
      _HtmlImage image, {
      String? fullUrl,
      _InlineTextStyle style = const _InlineTextStyle(),
    }) {
      if (image.shouldRenderAsImage) {
        flushText();
        segments.add(
          CookedSegment.image(
            _absoluteUrl(image.src),
            imageFullUrl: _absoluteUrl(fullUrl ?? image.src),
            imageWidth: image.width,
            imageHeight: image.height,
          ),
        );
      } else if (image.isEmoji) {
        addInlineEmoji(image, style);
      } else if (image.inlineText.isNotEmpty) {
        addRun(image.inlineText, style);
      }
    }

    void appendImageAnchor(dom.Element anchor, String fullUrl) {
      for (final imageElement in anchor.querySelectorAll('img')) {
        addImage(
          _HtmlImage.fromElement(imageElement),
          fullUrl: fullUrl,
        );
      }
    }

    late void Function(dom.Node node, _InlineTextStyle style) appendNode;

    void appendChildren(dom.Node node, _InlineTextStyle style) {
      for (final child in node.nodes) {
        appendNode(child, style);
      }
    }

    void appendList(dom.Element list, _InlineTextStyle style, int depth) {
      flushText();
      final ordered = list.localName?.toLowerCase() == 'ol';
      var index = 1;
      for (final item in list.children.where(_isListItemElement)) {
        withBlock(
          _CookedTextBlockState(
            kind: CookedTextBlockKind.listItem,
            listIndex: ordered ? index : 0,
            listDepth: depth,
          ),
          () {
            for (final child in item.nodes) {
              if (child is dom.Element && _isListElement(child)) {
                continue;
              }
              if (child is dom.Element && _isParagraphLikeElement(child)) {
                appendChildren(child, style);
              } else {
                appendNode(child, style);
              }
            }
          },
        );
        for (final child in item.children.where(_isListElement)) {
          appendList(child, style, depth + 1);
        }
        index += 1;
      }
    }

    appendNode = (dom.Node node, _InlineTextStyle style) {
      if (node is dom.Text) {
        addRun(node.text, style);
        return;
      }
      if (node is! dom.Element) {
        appendChildren(node, style);
        return;
      }

      if (_hasOwnClass(node, 'meta')) {
        return;
      }
      final tag = node.localName?.toLowerCase() ?? '';
      if (tag == 'aside' && _hasClass(node, 'onebox')) {
        final preview = _oneboxPreview(node);
        if (preview != null) {
          flushText();
          segments.add(CookedSegment.onebox(preview));
        }
        return;
      }
      if (tag == 'aside' && _hasClass(node, 'quote')) {
        final preview = _quotePreview(node);
        if (preview != null) {
          flushText();
          segments.add(CookedSegment.quote(preview));
        }
        return;
      }
      if (tag == 'div' && _hasOwnClass(node, 'poll')) {
        final poll = _pollPreview(node);
        if (poll != null) {
          flushText();
          segments.add(CookedSegment.poll(poll));
        }
        return;
      }
      if (tag == 'pre') {
        flushText();
        final text = _normalizeCodeBlockText(node.text);
        if (text.isNotEmpty) {
          segments.add(
            CookedSegment.richText(
              [CookedTextRun(text, code: true)],
              textBlockKind: CookedTextBlockKind.codeBlock,
            ),
          );
        }
        return;
      }
      if (_isHeadingTag(tag)) {
        withBlock(
          _CookedTextBlockState(
            kind: CookedTextBlockKind.heading,
            headingLevel: int.tryParse(tag.substring(1)) ?? 3,
          ),
          () => appendChildren(node, style),
        );
        return;
      }
      if (tag == 'blockquote') {
        withBlock(
          const _CookedTextBlockState(kind: CookedTextBlockKind.blockquote),
          () => appendChildren(node, style),
        );
        return;
      }
      if (_isListElement(node)) {
        appendList(node, style, blockState.listDepth);
        return;
      }
      if (tag == 'img') {
        addImage(_HtmlImage.fromElement(node), style: style);
        return;
      }
      if (tag == 'a') {
        if (_containsRenderableImage(node)) {
          final fullUrl = _fullImageSource(node);
          if (fullUrl != null) {
            appendImageAnchor(node, fullUrl);
          } else {
            appendChildren(node, style);
          }
          return;
        }
        final rawHref = node.attributes['href'] ?? '';
        if (isBlockedLink(rawHref)) {
          // Keep the anchor's visible text, but deliberately discard its
          // destination so it cannot be opened from posts or messages.
          appendChildren(node, style);
          return;
        }
        final preview = _linkPreview(node);
        if (preview != null) {
          if (_hasClass(node, 'onebox')) {
            flushText();
            segments.add(CookedSegment.onebox(preview));
            return;
          }
          final previousRunCount = inlineRuns.length;
          appendChildren(node, style.copyWith(link: preview));
          if (inlineRuns.length == previousRunCount) {
            addRun(preview.title, style.copyWith(link: preview));
          }
          return;
        }
      }
      if (tag == 'br') {
        addRun('\n', style);
        return;
      }
      if (tag == 'strong' || tag == 'b') {
        appendChildren(node, style.copyWith(bold: true));
        return;
      }
      if (tag == 'em' || tag == 'i') {
        appendChildren(node, style.copyWith(italic: true));
        return;
      }
      if (tag == 's' || tag == 'del' || tag == 'strike') {
        appendChildren(node, style.copyWith(strikethrough: true));
        return;
      }
      if (tag == 'code') {
        appendChildren(node, style.copyWith(code: true));
        return;
      }
      if (_isParagraphLikeElement(node)) {
        withBlock(blockState, () => appendChildren(node, style));
        return;
      }

      appendChildren(node, style);
    };

    final document = html_parser.parse(
      '<!doctype html><html><body>${_withoutAttachmentMetadata(html)}</body></html>',
    );
    final nodes = document.body?.nodes ?? document.nodes;
    for (final node in nodes) {
      appendNode(node, const _InlineTextStyle());
    }
    flushText();
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

  /// Links that the forum renders as informational navigation but which are
  /// intentionally non-interactive in the app. The visible anchor text is
  /// still preserved by the HTML parser.
  static bool isBlockedLink(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final uri = _uriForLink(trimmed);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final path =
        uri.path == '/' ? '/' : uri.path.replaceFirst(RegExp(r'/$'), '');
    if ((host == ForumConstants.host || host == ForumUrlResolver.webVpnHost) &&
        (path == '/about' || path == '/badges')) {
      return true;
    }
    return host == 'blog.discourse.org' &&
        path == '/2018/06/understanding-discourse-trust-levels';
  }

  static List<CookedSegment> _normalizeSegments(List<CookedSegment> segments) {
    final normalized = <CookedSegment>[];
    for (final segment in segments) {
      if (!segment.isText) {
        normalized.add(segment);
        continue;
      }
      final runs = segment.textBlockKind == CookedTextBlockKind.codeBlock
          ? _normalizeCodeRuns(segment.runs)
          : segment.runs.isEmpty
              ? _normalizeRuns([CookedTextRun(segment.value)])
              : _normalizeRuns(segment.runs);
      if (runs.isEmpty) {
        continue;
      }
      normalized.add(
        CookedSegment.richText(
          runs,
          textBlockKind: segment.textBlockKind,
          headingLevel: segment.headingLevel,
          listIndex: segment.listIndex,
          listDepth: segment.listDepth,
        ),
      );
    }
    return normalized;
  }

  static List<CookedTextRun> _normalizeRuns(List<CookedTextRun> runs) {
    final normalized = <CookedTextRun>[];
    for (final run in runs) {
      final compacted = run.text
          .replaceAll('\u00a0', ' ')
          .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
          .replaceAll(RegExp(r' *\n *'), '\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n');
      final text = run.code ? compacted : EmojiText.render(compacted);
      if (text.isEmpty) {
        continue;
      }
      final next = run.copyWith(text: text);
      if (normalized.isNotEmpty && normalized.last.hasSameStyle(next)) {
        normalized[normalized.length - 1] = normalized.last.copyWith(
          text: '${normalized.last.text}${next.text}',
        );
      } else {
        normalized.add(next);
      }
    }
    if (normalized.isEmpty) {
      return const [];
    }
    normalized[0] = normalized.first.copyWith(
      text: normalized.first.text.trimLeft(),
    );
    normalized[normalized.length - 1] = normalized.last.copyWith(
      text: normalized.last.text.trimRight(),
    );
    return normalized.where((run) => run.text.isNotEmpty).toList();
  }

  static List<CookedTextRun> _normalizeCodeRuns(List<CookedTextRun> runs) {
    final normalized = <CookedTextRun>[];
    for (final run in runs) {
      final text = run.text;
      if (text.isEmpty) {
        continue;
      }
      final next = run.copyWith(text: text);
      if (normalized.isNotEmpty && normalized.last.hasSameStyle(next)) {
        normalized[normalized.length - 1] = normalized.last.copyWith(
          text: '${normalized.last.text}${next.text}',
        );
      } else {
        normalized.add(next);
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
    if (isBlockedLink(rawUrl)) {
      return null;
    }
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
    if (isBlockedLink(rawUrl)) {
      return null;
    }
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

  static ForumPoll? _pollPreview(dom.Element element) {
    final name = element.attributes['data-poll-name']?.trim() ?? '';
    if (name.isEmpty) {
      return null;
    }
    final title = _cleanInlineText(element.attributes['data-poll-title']);
    final options = <ForumPollOption>[];
    for (final option in element.querySelectorAll('li')) {
      final id = option.attributes['data-poll-option-id']?.trim() ?? '';
      if (id.isEmpty) {
        continue;
      }
      options.add(
        ForumPollOption(
          id: id,
          html: _cleanInlineText(option.text),
        ),
      );
    }
    return ForumPoll(
      id: 0,
      name: name,
      type: element.attributes['data-poll-type']?.trim() ?? 'regular',
      status: element.attributes['data-poll-status']?.trim() ?? 'open',
      public: _boolAttribute(element.attributes['data-poll-public']),
      results: element.attributes['data-poll-results']?.trim() ?? 'always',
      chartType: element.attributes['data-poll-charttype']?.trim() ?? 'bar',
      min: int.tryParse(element.attributes['data-poll-min'] ?? '') ?? 1,
      max: int.tryParse(element.attributes['data-poll-max'] ?? '') ?? 0,
      title: title.isEmpty ? null : title,
      options: options,
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

  static String? _fullImageSource(dom.Element anchor) {
    if (!_hasClass(anchor, 'lightbox')) {
      return null;
    }
    final href = anchor.attributes['href']?.trim() ?? '';
    if (_isForumUploadImageUrl(href)) {
      return href;
    }
    final downloadHref = anchor.attributes['data-download-href']?.trim() ?? '';
    if (_isForumUploadImageUrl(downloadHref)) {
      return downloadHref;
    }
    return null;
  }

  static bool _isForumUploadImageUrl(String value) {
    final uri = _uriForLink(value);
    if (uri == null || !ForumUrlResolver.isKnownForumHost(uri.host)) {
      return false;
    }
    return uri.pathSegments.contains('uploads');
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
    if (username.isEmpty) {
      return null;
    }
    try {
      return Uri.decodeComponent(username);
    } on Object {
      return username;
    }
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

  static bool _isHeadingTag(String tag) {
    return RegExp(r'^h[1-6]$').hasMatch(tag);
  }

  static bool _isListElement(dom.Element element) {
    final tag = element.localName?.toLowerCase();
    return tag == 'ul' || tag == 'ol';
  }

  static bool _isListItemElement(dom.Element element) {
    return element.localName?.toLowerCase() == 'li';
  }

  static bool _isParagraphLikeElement(dom.Element element) {
    final tag = element.localName?.toLowerCase();
    return tag == 'p' || tag == 'div' || tag == 'section' || tag == 'article';
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

  static bool _boolAttribute(String? value) {
    return value == 'true' || value == '1';
  }

  static String _normalizeCodeBlockText(String value) {
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n+$'), '');
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

class _InlineTextStyle {
  const _InlineTextStyle({
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.code = false,
    this.link,
  });

  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool code;
  final CookedLinkPreview? link;

  _InlineTextStyle copyWith({
    bool? bold,
    bool? italic,
    bool? strikethrough,
    bool? code,
    CookedLinkPreview? link,
  }) {
    return _InlineTextStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strikethrough: strikethrough ?? this.strikethrough,
      code: code ?? this.code,
      link: link ?? this.link,
    );
  }
}

class _CookedTextBlockState {
  const _CookedTextBlockState({
    this.kind = CookedTextBlockKind.paragraph,
    this.headingLevel = 0,
    this.listIndex = 0,
    this.listDepth = 0,
  });

  final CookedTextBlockKind kind;
  final int headingLevel;
  final int listIndex;
  final int listDepth;
}

class _HtmlImage {
  const _HtmlImage({
    required this.src,
    required this.alt,
    required this.width,
    required this.height,
    this.emoji = false,
  });

  final String src;
  final String alt;
  final int width;
  final int height;
  final bool emoji;

  bool get isEmoji => emoji || src.contains('/emoji/');

  bool get shouldRenderAsImage {
    if (src.isEmpty || isEmoji) {
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
      emoji: (attrs['class'] ?? '').split(RegExp(r'\s+')).contains('emoji'),
    );
  }

  factory _HtmlImage.fromElement(dom.Element element) {
    return _HtmlImage(
      src: element.attributes['src'] ?? '',
      alt: element.attributes['alt'] ?? element.attributes['title'] ?? '',
      width: int.tryParse(element.attributes['width'] ?? '') ?? 0,
      height: int.tryParse(element.attributes['height'] ?? '') ?? 0,
      emoji: element.classes.contains('emoji'),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
