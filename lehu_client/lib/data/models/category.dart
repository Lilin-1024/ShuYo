import 'common.dart';

class ForumCategory {
  const ForumCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.color,
    required this.textColor,
  });

  final int id;
  final String name;
  final String slug;
  final String color;
  final String textColor;

  factory ForumCategory.fromJson(JsonMap json) {
    return ForumCategory(
      id: intValue(json['id']),
      name: stringValue(json['name']),
      slug: stringValue(json['slug']),
      color: stringValue(json['color'], '333333'),
      textColor: stringValue(json['text_color'], 'FFFFFF'),
    );
  }
}
