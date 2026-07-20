import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/announcement.dart';
import 'http_timeout.dart';

class AnnouncementApiException implements Exception {
  const AnnouncementApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() {
    final code = statusCode;
    if (code == null) {
      return message;
    }
    return '$message ($code)';
  }
}

class AnnouncementApiClient {
  AnnouncementApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? IOClient(HttpClient());

  static const listUrl = 'https://www.shu.edu.cn/tzgg.htm';

  final http.Client _httpClient;

  Future<List<AnnouncementListItem>> fetchAnnouncements() async {
    final response = await HttpTimeout.request(
      _httpClient.get(
        Uri.parse(listUrl),
        headers: const {
          'accept': 'text/html,application/xhtml+xml',
          'user-agent':
              'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
        },
      ),
      message: '通知公告请求超时，请稍后再试',
    );
    _ensureSuccess(response);
    return parseAnnouncementList(_decodeHtml(response), baseUrl: listUrl);
  }

  Future<AnnouncementDetail> fetchDetail(AnnouncementListItem item) async {
    final response = await HttpTimeout.request(
      _httpClient.get(
        Uri.parse(item.url),
        headers: const {
          'accept': 'text/html,application/xhtml+xml',
          'user-agent':
              'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
        },
      ),
      message: '通知公告请求超时，请稍后再试',
    );
    _ensureSuccess(response);
    return parseAnnouncementDetail(
      _decodeHtml(response),
      url: item.url,
      fallbackTitle: item.title,
      fallbackDateText: item.dateText,
      fallbackPublishedAt: item.publishedAt,
    );
  }

  static List<AnnouncementListItem> parseAnnouncementList(
    String html, {
    required String baseUrl,
  }) {
    final document = html_parser.parse(html);
    final listRoot = document.querySelector('.ej_main .list');
    final anchors =
        listRoot?.querySelectorAll('ul > li > a') ?? const <dom.Element>[];
    return anchors
        .map((anchor) {
          final title = _cleanText(anchor.querySelector('.bt')?.text);
          final url = _resolveUrl(baseUrl, anchor.attributes['href'] ?? '');
          if (title.isEmpty || url.isEmpty) {
            return null;
          }
          final dateText = _cleanText(anchor.querySelector('.sj')?.text);
          return AnnouncementListItem(
            title: title,
            url: url,
            summary: _cleanText(anchor.querySelector('.zy')?.text),
            dateText: dateText,
            publishedAt: _parseDate(dateText),
          );
        })
        .whereType<AnnouncementListItem>()
        .toList(growable: false);
  }

  static AnnouncementDetail parseAnnouncementDetail(
    String html, {
    required String url,
    String fallbackTitle = '',
    String fallbackDateText = '',
    DateTime? fallbackPublishedAt,
  }) {
    final document = html_parser.parse(html);
    final root = document.querySelector('.nry');
    final title = _cleanText(root?.querySelector('h1')?.text);
    final metadata = _parseMetadata(root?.querySelector('.xx'));
    final dateText =
        metadata.dateText.isNotEmpty ? metadata.dateText : fallbackDateText;
    final contentRoot = root?.querySelector('.v_news_content');
    final blocks = contentRoot == null
        ? const <AnnouncementContentBlock>[]
        : _parseContentBlocks(contentRoot, baseUrl: url);
    return AnnouncementDetail(
      title: title.isNotEmpty ? title : fallbackTitle,
      url: url,
      dateText: dateText,
      publishedAt: _parseDate(dateText) ?? fallbackPublishedAt,
      author: metadata.author,
      department: metadata.department,
      blocks: blocks,
    );
  }

  static List<AnnouncementContentBlock> _parseContentBlocks(
    dom.Element root, {
    required String baseUrl,
  }) {
    final blocks = <AnnouncementContentBlock>[];
    final paragraphs = root.querySelectorAll('p');
    if (paragraphs.isEmpty) {
      final text = _cleanText(root.text);
      if (text.isNotEmpty) {
        blocks.add(AnnouncementContentBlock.text(text));
      }
      return blocks;
    }

    for (final paragraph in paragraphs) {
      final text = _cleanText(paragraph.text);
      if (text.isNotEmpty) {
        blocks.add(AnnouncementContentBlock.text(text));
      }
      for (final image in paragraph.querySelectorAll('img')) {
        final src = image.attributes['orisrc'] ??
            image.attributes['src'] ??
            image.attributes['vurl'] ??
            '';
        final imageUrl = _resolveUrl(baseUrl, src);
        if (imageUrl.isEmpty) {
          continue;
        }
        blocks.add(
          AnnouncementContentBlock.image(
            imageUrl,
            alt: _cleanText(
              image.attributes['alt'] ?? image.attributes['title'],
            ),
          ),
        );
      }
    }
    return blocks;
  }

  static _AnnouncementMetadata _parseMetadata(dom.Element? element) {
    var dateText = '';
    var author = '';
    var department = '';
    for (final span in element?.querySelectorAll('span') ?? const []) {
      final text = _cleanText(span.text);
      if (text.startsWith('发布时间：')) {
        dateText = text.substring('发布时间：'.length).trim();
      } else if (text.startsWith('投稿：')) {
        author = text.substring('投稿：'.length).trim();
      } else if (text.startsWith('部门：')) {
        department = text.substring('部门：'.length).trim();
      }
    }
    return _AnnouncementMetadata(
      dateText: dateText,
      author: author,
      department: department,
    );
  }

  static DateTime? _parseDate(String value) {
    final match =
        RegExp(r'(\d{4})[.\-/年](\d{1,2})[.\-/月](\d{1,2})').firstMatch(value);
    if (match == null) {
      return null;
    }
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  static String _resolveUrl(String baseUrl, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.startsWith('javascript:')) {
      return '';
    }
    return Uri.parse(baseUrl).resolve(trimmed).toString();
  }

  static String _cleanText(String? value) {
    return (value ?? '')
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnnouncementApiException(
        '通知公告请求失败',
        statusCode: response.statusCode,
      );
    }
  }

  static String _decodeHtml(http.Response response) {
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}

class _AnnouncementMetadata {
  const _AnnouncementMetadata({
    required this.dateText,
    required this.author,
    required this.department,
  });

  final String dateText;
  final String author;
  final String department;
}
