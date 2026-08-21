import 'common.dart';
import 'discourse_user.dart';
import 'user_profile.dart';

class CurrentUserSession {
  const CurrentUserSession({
    required this.user,
    required this.unreadNotifications,
    required this.allUnreadNotifications,
    required this.newPersonalMessages,
    required this.canCreateTopic,
  });

  final DiscourseUser user;
  final int unreadNotifications;
  final int allUnreadNotifications;
  final int newPersonalMessages;
  final bool canCreateTopic;

  String get username => user.username;

  int get notificationBadgeCount {
    return unreadNotifications;
  }

  int get privateMessageBadgeCount => newPersonalMessages;

  UserProfile get profile => UserProfile(user: user);

  factory CurrentUserSession.fromJson(JsonMap json) {
    return CurrentUserSession(
      user: DiscourseUser.fromJson(json),
      unreadNotifications: intValue(json['unread_notifications']),
      allUnreadNotifications: intValue(json['all_unread_notifications_count']),
      newPersonalMessages:
          intValue(json['new_personal_messages_notifications_count']),
      canCreateTopic: boolValue(json['can_create_topic']),
    );
  }

  JsonMap toJson() {
    return {
      ...user.toJson(),
      'unread_notifications': unreadNotifications,
      'all_unread_notifications_count': allUnreadNotifications,
      'new_personal_messages_notifications_count': newPersonalMessages,
      'can_create_topic': canCreateTopic,
    };
  }
}
