import 'common.dart';

enum AnnouncementContentType {
  text,
  image,
}

class AnnouncementContentBlock {
  const AnnouncementContentBlock.text(this.value)
      : type = AnnouncementContentType.text,
        alt = '';

  const AnnouncementContentBlock.image(
    this.value, {
    this.alt = '',
  }) : type = AnnouncementContentType.image;

  final AnnouncementContentType type;
  final String value;
  final String alt;

  bool get isText => type == AnnouncementContentType.text;
  bool get isImage => type == AnnouncementContentType.image;

  JsonMap toJson() {
    return {
      'type': type.name,
      'value': value,
      'alt': alt,
    };
  }

  factory AnnouncementContentBlock.fromJson(JsonMap json) {
    final type = stringValue(json['type']);
    final value = stringValue(json['value']);
    if (type == AnnouncementContentType.image.name) {
      return AnnouncementContentBlock.image(
        value,
        alt: stringValue(json['alt']),
      );
    }
    return AnnouncementContentBlock.text(value);
  }
}

class AnnouncementListItem {
  const AnnouncementListItem({
    required this.title,
    required this.url,
    this.summary = '',
    this.dateText = '',
    this.publishedAt,
  });

  final String title;
  final String url;
  final String summary;
  final String dateText;
  final DateTime? publishedAt;

  JsonMap toJson() {
    return {
      'title': title,
      'url': url,
      'summary': summary,
      'dateText': dateText,
      'publishedAt': publishedAt?.toIso8601String(),
    };
  }

  factory AnnouncementListItem.fromJson(JsonMap json) {
    return AnnouncementListItem(
      title: stringValue(json['title']),
      url: stringValue(json['url']),
      summary: stringValue(json['summary']),
      dateText: stringValue(json['dateText']),
      publishedAt: dateValue(json['publishedAt']),
    );
  }
}

class AnnouncementDetail {
  const AnnouncementDetail({
    required this.title,
    required this.url,
    required this.blocks,
    this.dateText = '',
    this.publishedAt,
    this.author = '',
    this.department = '',
  });

  final String title;
  final String url;
  final List<AnnouncementContentBlock> blocks;
  final String dateText;
  final DateTime? publishedAt;
  final String author;
  final String department;

  bool get hasContent => blocks.isNotEmpty;
}
