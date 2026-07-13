import '../../core/forum_constants.dart';
import 'common.dart';

class DiscourseUser {
  const DiscourseUser({
    required this.id,
    required this.username,
    required this.avatarTemplate,
    this.trustLevel = 0,
  });

  final int id;
  final String username;
  final String avatarTemplate;
  final int trustLevel;

  factory DiscourseUser.fromJson(JsonMap json) {
    return DiscourseUser(
      id: intValue(json['id']),
      username: stringValue(json['username']),
      avatarTemplate: stringValue(json['avatar_template']),
      trustLevel: intValue(json['trust_level']),
    );
  }

  String avatarUrl({int size = 96}) {
    final resolved = avatarTemplate.replaceAll('{size}', '$size');
    if (resolved.startsWith('http')) {
      return resolved;
    }
    return '${ForumConstants.baseUrl}$resolved';
  }
}
