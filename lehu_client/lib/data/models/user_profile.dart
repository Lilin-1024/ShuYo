import 'common.dart';
import 'discourse_user.dart';

class UserProfile {
  const UserProfile({required this.user});

  final DiscourseUser user;

  int get id => user.id;
  String get username => user.username;
  String avatarUrl({int size = 96}) => user.avatarUrl(size: size);

  factory UserProfile.fromJson(JsonMap json) {
    final user = json['user'];
    return UserProfile(
      user: DiscourseUser.fromJson(user is JsonMap ? user : const {}),
    );
  }
}

class UserSummary {
  const UserSummary({
    required this.likesGiven,
    required this.likesReceived,
    required this.topicsEntered,
    required this.postsReadCount,
    required this.daysVisited,
    required this.topicCount,
    required this.postCount,
    required this.timeReadSeconds,
  });

  final int likesGiven;
  final int likesReceived;
  final int topicsEntered;
  final int postsReadCount;
  final int daysVisited;
  final int topicCount;
  final int postCount;
  final int timeReadSeconds;

  factory UserSummary.fromJson(JsonMap json) {
    final summary = json['user_summary'];
    final data = summary is JsonMap ? summary : const <String, dynamic>{};
    return UserSummary(
      likesGiven: intValue(data['likes_given']),
      likesReceived: intValue(data['likes_received']),
      topicsEntered: intValue(data['topics_entered']),
      postsReadCount: intValue(data['posts_read_count']),
      daysVisited: intValue(data['days_visited']),
      topicCount: intValue(data['topic_count']),
      postCount: intValue(data['post_count']),
      timeReadSeconds: intValue(data['time_read']),
    );
  }

  int get timeReadMinutes => (timeReadSeconds / 60).round();
}
