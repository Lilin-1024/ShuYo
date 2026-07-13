import 'common.dart';

class ForumCategory {
  const ForumCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.color,
    required this.textColor,
    this.position = 0,
    this.permission,
    this.readRestricted = false,
  });

  final int id;
  final String name;
  final String slug;
  final String color;
  final String textColor;
  final int position;
  final int? permission;
  final bool readRestricted;

  factory ForumCategory.fromJson(JsonMap json) {
    return ForumCategory(
      id: intValue(json['id']),
      name: stringValue(json['name']),
      slug: stringValue(json['slug']),
      color: stringValue(json['color'], '333333'),
      textColor: stringValue(json['text_color'], 'FFFFFF'),
      position: intValue(json['position']),
      permission: json['permission'] == null ? null : intValue(json['permission']),
      readRestricted: boolValue(json['read_restricted']),
    );
  }

  String get routeSlug => slug.isEmpty ? '$id-category' : slug;
}
