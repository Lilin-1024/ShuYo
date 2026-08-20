import 'common.dart';

class ClientAnnouncement {
  const ClientAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String content;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ClientAnnouncement.fromJson(JsonMap json) {
    return ClientAnnouncement(
      id: stringValue(json['id']),
      title: stringValue(json['title']),
      content: stringValue(json['content']),
      active: boolValue(json['active'], true),
      createdAt: dateValue(json['createdAt']),
      updatedAt: dateValue(json['updatedAt']),
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'active': active,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

class ClientUpdateInfo {
  const ClientUpdateInfo({
    required this.appName,
    required this.latestVersion,
    required this.latestBuild,
    required this.forceUpdate,
    required this.updateTitle,
    required this.updateMessage,
    required this.downloadUrl,
    required this.noticeText,
    required this.publishedAt,
    required this.updatedAt,
    required this.announcement,
  });

  final String appName;
  final String latestVersion;
  final int latestBuild;
  final bool forceUpdate;
  final String updateTitle;
  final String updateMessage;
  final String downloadUrl;
  final String noticeText;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final ClientAnnouncement? announcement;

  bool isNewerThan(int buildNumber) => latestBuild > buildNumber;

  bool get hasDownloadUrl => downloadUrl.trim().isNotEmpty;

  factory ClientUpdateInfo.fromJson(JsonMap json) {
    final announcementJson = json['announcement'];
    return ClientUpdateInfo(
      appName: stringValue(json['appName'], 'ShuYo'),
      latestVersion: stringValue(json['latestVersion'], '0.1.0'),
      latestBuild: intValue(json['latestBuild'], 1),
      forceUpdate: boolValue(json['forceUpdate'], false),
      updateTitle: stringValue(json['updateTitle'], '发现新版本'),
      updateMessage: stringValue(json['updateMessage'], ''),
      downloadUrl: stringValue(json['downloadUrl'], ''),
      noticeText: stringValue(json['noticeText'], ''),
      publishedAt: dateValue(json['publishedAt']),
      updatedAt: dateValue(json['updatedAt']),
      announcement: announcementJson is JsonMap
          ? ClientAnnouncement.fromJson(announcementJson)
          : null,
    );
  }
}

class ClientBootstrapInfo {
  const ClientBootstrapInfo({
    required this.version,
    required this.latestAnnouncement,
  });

  final ClientUpdateInfo version;
  final ClientAnnouncement? latestAnnouncement;

  factory ClientBootstrapInfo.fromJson(JsonMap json) {
    final data = json['data'];
    final map = data is JsonMap ? data : const <String, dynamic>{};
    final announcementJson = map['latestAnnouncement'];
    return ClientBootstrapInfo(
      version: ClientUpdateInfo.fromJson(
        map['version'] is JsonMap ? map['version'] as JsonMap : map,
      ),
      latestAnnouncement: announcementJson is JsonMap
          ? ClientAnnouncement.fromJson(announcementJson)
          : null,
    );
  }
}

class ClientFeedbackReply {
  const ClientFeedbackReply({
    required this.id,
    required this.author,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String author;
  final String message;
  final DateTime? createdAt;

  factory ClientFeedbackReply.fromJson(JsonMap json) {
    return ClientFeedbackReply(
      id: stringValue(json['id']),
      author: stringValue(json['author'], 'admin'),
      message: stringValue(json['message']),
      createdAt: dateValue(json['createdAt']),
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'author': author,
      'message': message,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}

class ClientFeedbackSubmissionResult {
  const ClientFeedbackSubmissionResult({
    required this.id,
    required this.lookupToken,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String lookupToken;
  final String status;
  final DateTime? createdAt;

  factory ClientFeedbackSubmissionResult.fromJson(JsonMap json) {
    final data = json['data'];
    final map = data is JsonMap ? data : const <String, dynamic>{};
    return ClientFeedbackSubmissionResult(
      id: stringValue(map['id']),
      lookupToken: stringValue(map['lookupToken']),
      status: stringValue(map['status'], 'open'),
      createdAt: dateValue(map['createdAt']),
    );
  }
}

class ClientFeedbackDraft {
  const ClientFeedbackDraft({
    required this.title,
    required this.content,
    required this.contact,
    required this.deviceId,
    required this.appVersion,
    required this.platform,
  });

  final String title;
  final String content;
  final String contact;
  final String deviceId;
  final String appVersion;
  final String platform;

  JsonMap toJson() {
    return {
      'title': title,
      'content': content,
      'contact': contact,
      'deviceId': deviceId,
      'appVersion': appVersion,
      'platform': platform,
    };
  }
}

class ClientFeedbackTicket {
  const ClientFeedbackTicket({
    required this.id,
    required this.lookupToken,
    required this.title,
    required this.content,
    required this.contact,
    required this.deviceId,
    required this.appVersion,
    required this.platform,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.replies,
  });

  final String id;
  final String lookupToken;
  final String title;
  final String content;
  final String contact;
  final String deviceId;
  final String appVersion;
  final String platform;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ClientFeedbackReply> replies;

  bool get hasReplies => replies.isNotEmpty;

  ClientFeedbackReply? get latestReply => replies.isEmpty ? null : replies.last;

  ClientFeedbackTicket copyWith({
    String? id,
    String? lookupToken,
    String? title,
    String? content,
    String? contact,
    String? deviceId,
    String? appVersion,
    String? platform,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ClientFeedbackReply>? replies,
  }) {
    return ClientFeedbackTicket(
      id: id ?? this.id,
      lookupToken: lookupToken ?? this.lookupToken,
      title: title ?? this.title,
      content: content ?? this.content,
      contact: contact ?? this.contact,
      deviceId: deviceId ?? this.deviceId,
      appVersion: appVersion ?? this.appVersion,
      platform: platform ?? this.platform,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      replies: replies ?? this.replies,
    );
  }

  factory ClientFeedbackTicket.fromSubmission({
    required ClientFeedbackDraft draft,
    required ClientFeedbackSubmissionResult result,
  }) {
    return ClientFeedbackTicket(
      id: result.id,
      lookupToken: result.lookupToken,
      title: draft.title.isEmpty ? '未命名反馈' : draft.title,
      content: draft.content,
      contact: draft.contact,
      deviceId: draft.deviceId,
      appVersion: draft.appVersion,
      platform: draft.platform,
      status: result.status,
      createdAt: result.createdAt,
      updatedAt: result.createdAt,
      replies: const [],
    );
  }

  factory ClientFeedbackTicket.fromServerJson(
    JsonMap json, {
    String? lookupToken,
  }) {
    final replies = json['replies'];
    return ClientFeedbackTicket(
      id: stringValue(json['id']),
      lookupToken: lookupToken ?? stringValue(json['lookupToken']),
      title: stringValue(json['title'], '未命名反馈'),
      content: stringValue(json['content']),
      contact: stringValue(json['contact']),
      deviceId: stringValue(json['deviceId']),
      appVersion: stringValue(json['appVersion']),
      platform: stringValue(json['platform']),
      status: stringValue(json['status'], 'open'),
      createdAt: dateValue(json['createdAt']),
      updatedAt: dateValue(json['updatedAt']),
      replies: replies is List
          ? replies
              .whereType<JsonMap>()
              .map(ClientFeedbackReply.fromJson)
              .toList(growable: false)
          : const [],
    );
  }

  factory ClientFeedbackTicket.fromJson(JsonMap json) {
    final replies = json['replies'];
    return ClientFeedbackTicket(
      id: stringValue(json['id']),
      lookupToken: stringValue(json['lookupToken']),
      title: stringValue(json['title'], '未命名反馈'),
      content: stringValue(json['content']),
      contact: stringValue(json['contact']),
      deviceId: stringValue(json['deviceId']),
      appVersion: stringValue(json['appVersion']),
      platform: stringValue(json['platform']),
      status: stringValue(json['status'], 'open'),
      createdAt: dateValue(json['createdAt']),
      updatedAt: dateValue(json['updatedAt']),
      replies: replies is List
          ? replies
              .whereType<JsonMap>()
              .map(ClientFeedbackReply.fromJson)
              .toList(growable: false)
          : const [],
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'lookupToken': lookupToken,
      'title': title,
      'content': content,
      'contact': contact,
      'deviceId': deviceId,
      'appVersion': appVersion,
      'platform': platform,
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'replies': replies.map((reply) => reply.toJson()).toList(),
    };
  }
}
