import '../../core/forum_constants.dart';
import 'common.dart';
import 'discourse_user.dart';
import '../services/html_text.dart';

class UserProfile {
  const UserProfile({
    required this.user,
    this.bioExcerpt = '',
    this.bioRaw = '',
    this.profileBackgroundUploadUrl = '',
    this.cardBackgroundUploadUrl = '',
    this.systemAvatarTemplate = '',
    this.customAvatarTemplate = '',
    this.customAvatarUploadId,
    this.systemAvatarUploadId,
    this.hideProfile = false,
    this.timezone = 'Asia/Shanghai',
    this.defaultCalendar = 'none_selected',
    this.canSendPrivateMessage = false,
    this.canEdit = false,
    this.canUploadProfileHeader = false,
    this.admin = false,
    this.moderator = false,
    this.createdAt,
  });

  final DiscourseUser user;
  final String bioExcerpt;
  final String bioRaw;
  final String profileBackgroundUploadUrl;
  final String cardBackgroundUploadUrl;
  final String systemAvatarTemplate;
  final String customAvatarTemplate;
  final int? customAvatarUploadId;
  final int? systemAvatarUploadId;
  final bool hideProfile;
  final String timezone;
  final String defaultCalendar;
  final bool canSendPrivateMessage;
  final bool canEdit;
  final bool canUploadProfileHeader;
  final bool admin;
  final bool moderator;
  final DateTime? createdAt;

  int get id => user.id;
  String get username => user.username;
  String avatarUrl({int size = 96}) => user.avatarUrl(size: size);
  String profileBackgroundUrl() =>
      _absoluteUploadUrl(profileBackgroundUploadUrl);

  factory UserProfile.fromJson(JsonMap json) {
    final user = json['user'];
    final userJson = user is JsonMap ? user : const <String, dynamic>{};
    final userOption = userJson['user_option'];
    final optionJson =
        userOption is JsonMap ? userOption : const <String, dynamic>{};
    return UserProfile(
      user: DiscourseUser.fromJson(userJson),
      bioExcerpt: HtmlText.toPlainText(stringValue(userJson['bio_excerpt'])),
      bioRaw: stringValue(userJson['bio_raw']),
      profileBackgroundUploadUrl:
          stringValue(userJson['profile_background_upload_url']),
      cardBackgroundUploadUrl:
          stringValue(userJson['card_background_upload_url']),
      systemAvatarTemplate: stringValue(userJson['system_avatar_template']),
      customAvatarTemplate: stringValue(userJson['custom_avatar_template']),
      customAvatarUploadId: _nullableInt(userJson['custom_avatar_upload_id']),
      systemAvatarUploadId: _nullableInt(userJson['system_avatar_upload_id']),
      hideProfile: boolValue(optionJson['hide_profile']),
      timezone: stringValue(optionJson['timezone'], 'Asia/Shanghai'),
      defaultCalendar:
          stringValue(optionJson['default_calendar'], 'none_selected'),
      canSendPrivateMessage:
          boolValue(userJson['can_send_private_message_to_user']) ||
              boolValue(userJson['can_send_private_messages']),
      canEdit: boolValue(userJson['can_edit']),
      canUploadProfileHeader: boolValue(userJson['can_upload_profile_header']),
      admin: boolValue(userJson['admin']),
      moderator: boolValue(userJson['moderator']),
      createdAt: dateValue(userJson['created_at']),
    );
  }
}

class ProfileSettingsDraft {
  const ProfileSettingsDraft({
    required this.bioRaw,
    required this.hideProfile,
    required this.profileBackgroundUploadUrl,
    required this.cardBackgroundUploadUrl,
    required this.timezone,
    required this.defaultCalendar,
  });

  final String bioRaw;
  final bool hideProfile;
  final String profileBackgroundUploadUrl;
  final String cardBackgroundUploadUrl;
  final String timezone;
  final String defaultCalendar;

  factory ProfileSettingsDraft.fromProfile(UserProfile profile) {
    return ProfileSettingsDraft(
      bioRaw: profile.bioRaw,
      hideProfile: profile.hideProfile,
      profileBackgroundUploadUrl: profile.profileBackgroundUploadUrl,
      cardBackgroundUploadUrl: profile.cardBackgroundUploadUrl,
      timezone: profile.timezone,
      defaultCalendar: profile.defaultCalendar,
    );
  }
}

enum ProfileImageUploadType {
  avatar,
  profileBackground,
}

class ProfileImageUpload {
  const ProfileImageUpload({
    required this.id,
    required this.url,
    required this.filename,
    required this.width,
    required this.height,
  });

  final int id;
  final String url;
  final String filename;
  final int width;
  final int height;

  factory ProfileImageUpload.fromJson(JsonMap json) {
    return ProfileImageUpload(
      id: intValue(json['id']),
      url: stringValue(json['url']),
      filename: stringValue(json['original_filename']),
      width: intValue(json['width']),
      height: intValue(json['height']),
    );
  }
}

int? _nullableInt(Object? value) {
  final parsed = intValue(value, -1);
  return parsed < 0 ? null : parsed;
}

String _absoluteUploadUrl(String value) {
  if (value.isEmpty || value.startsWith('http')) {
    return value;
  }
  return '${ForumConstants.baseUrl}$value';
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
