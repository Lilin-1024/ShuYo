import '../../core/forum_constants.dart';
import '../../core/forum_url_resolver.dart';
import '../models/composer.dart';
import '../models/forum_report.dart';
import '../models/post.dart';
import '../models/topic.dart';
import '../models/user_profile.dart';

class ReplyDraft {
  const ReplyDraft({
    required this.topicId,
    required this.categoryId,
    required this.raw,
    this.replyToPostNumber,
    this.images = const [],
    this.archetype = 'regular',
    this.typingDurationMs = 1000,
    this.composerOpenDurationMs = 3000,
  });

  final int topicId;
  final int categoryId;
  final String raw;
  final int? replyToPostNumber;
  final List<UploadedImage> images;
  final String archetype;
  final int typingDurationMs;
  final int composerOpenDurationMs;
}

class RequestPayload {
  const RequestPayload({
    required this.method,
    required this.url,
    required this.body,
  });

  final String method;
  final String url;
  final String body;

  @override
  String toString() {
    return '$method $url\n\n$body';
  }
}

class PayloadFactory {
  const PayloadFactory._();

  static RequestPayload createReply(ReplyDraft draft) {
    final fields = <String, String>{
      'raw': draft.raw,
      'unlist_topic': 'false',
      'category': draft.categoryId <= 0 ? '' : '${draft.categoryId}',
      'topic_id': '${draft.topicId}',
      'is_warning': 'false',
      'archetype': draft.archetype,
      'typing_duration_msecs': '${draft.typingDurationMs}',
      'composer_open_duration_msecs': '${draft.composerOpenDurationMs}',
      'composer_version': '1',
      'featured_link': '',
      'shared_draft': 'false',
      'draft_key': 'topic_${draft.topicId}',
      'nested_post': 'true',
    };
    final replyTo = draft.replyToPostNumber;
    if (replyTo != null) {
      fields['reply_to_post_number'] = '$replyTo';
    }
    for (final image in draft.images) {
      fields['image_sizes[${image.url}][width]'] = '${image.width}';
      fields['image_sizes[${image.url}][height]'] = '${image.height}';
    }

    return RequestPayload(
      method: 'POST',
      url: ForumUrlResolver.resolve(ForumConstants.postsPath),
      body: _formEncode(fields),
    );
  }

  static RequestPayload createTopic(CreateTopicDraft draft) {
    final fields = <String, String>{
      'raw': draft.raw,
      'title': draft.title,
      'unlist_topic': 'false',
      'category': '${draft.categoryId}',
      'is_warning': 'false',
      'archetype': 'regular',
      'typing_duration_msecs': '${draft.typingDurationMs}',
      'composer_open_duration_msecs': '${draft.composerOpenDurationMs}',
      'composer_version': '1',
      'featured_link': '',
      'shared_draft': 'false',
      'draft_key': draft.draftKey,
      'nested_post': 'true',
    };
    for (final image in draft.images) {
      fields['image_sizes[${image.url}][width]'] = '${image.width}';
      fields['image_sizes[${image.url}][height]'] = '${image.height}';
    }
    return RequestPayload(
      method: 'POST',
      url: ForumUrlResolver.resolve(ForumConstants.postsPath),
      body: _formEncode(fields),
    );
  }

  static RequestPayload createPrivateMessage(PrivateMessageDraft draft) {
    return RequestPayload(
      method: 'POST',
      url: ForumUrlResolver.resolve(ForumConstants.postsPath),
      body: _formEncode({
        'raw': draft.raw,
        'title': draft.title,
        'unlist_topic': 'false',
        'category': '',
        'is_warning': 'false',
        'archetype': 'private_message',
        'target_recipients': draft.recipients,
        'typing_duration_msecs': '${draft.typingDurationMs}',
        'composer_open_duration_msecs': '${draft.composerOpenDurationMs}',
        'composer_version': '1',
        'featured_link': '',
        'shared_draft': 'false',
        'draft_key': draft.draftKey,
        'nested_post': 'true',
        for (final image in draft.images) ...{
          'image_sizes[${image.url}][width]': '${image.width}',
          'image_sizes[${image.url}][height]': '${image.height}',
        },
      }),
    );
  }

  static RequestPayload likePost(int postId) {
    return RequestPayload(
      method: 'POST',
      url: ForumUrlResolver.resolve(ForumConstants.postActionsPath),
      body: _formEncode({
        'id': '$postId',
        'post_action_type_id': '2',
        'flag_topic': 'false',
      }),
    );
  }

  static RequestPayload unlikePost(int postId) {
    return RequestPayload(
      method: 'DELETE',
      url: ForumUrlResolver.resolve('/post_actions/$postId'),
      body: _formEncode({
        'post_action_type_id': '2',
      }),
    );
  }

  static RequestPayload votePoll({
    required int postId,
    required String pollName,
    required List<String> optionIds,
  }) {
    return RequestPayload(
      method: 'PUT',
      url: ForumUrlResolver.resolve('/polls/vote'),
      body: _formEncodeEntries([
        MapEntry('post_id', '$postId'),
        MapEntry('poll_name', pollName),
        for (final optionId in optionIds) MapEntry('options[]', optionId),
      ]),
    );
  }

  static RequestPayload togglePollStatus({
    required int postId,
    required String pollName,
    required String status,
  }) {
    return RequestPayload(
      method: 'PUT',
      url: ForumUrlResolver.resolve('/polls/toggle_status'),
      body: _formEncode({
        'post_id': '$postId',
        'poll_name': pollName,
        'status': status,
      }),
    );
  }

  static RequestPayload reportContent(ForumReportDraft draft) {
    final message = draft.message?.trim();
    return RequestPayload(
      method: 'POST',
      url: ForumUrlResolver.resolve(ForumConstants.postActionsPath),
      body: _formEncode({
        'id': '${draft.id}',
        'post_action_type_id': '${draft.reason.id}',
        if (message != null && message.isNotEmpty) 'message': message,
        'flag_topic': draft.flagTopic ? 'true' : 'false',
      }),
    );
  }

  static RequestPayload topicTiming({
    required int topicId,
    required int postNumber,
    required int topicTimeMs,
    Map<int, int>? postTimingsMs,
  }) {
    final timings = postTimingsMs == null || postTimingsMs.isEmpty
        ? <int, int>{postNumber: topicTimeMs}
        : postTimingsMs;
    return RequestPayload(
      method: 'POST',
      url: ForumUrlResolver.resolve('/topics/timings'),
      body: _formEncodeEntries([
        for (final entry in timings.entries)
          if (entry.key > 0 && entry.value > 0)
            MapEntry('timings[${entry.key}]', '${entry.value}'),
        MapEntry('topic_time', '$topicTimeMs'),
        MapEntry('topic_id', '$topicId'),
      ]),
    );
  }

  static RequestPayload deletePost(Post post) {
    return RequestPayload(
      method: 'DELETE',
      url: ForumUrlResolver.resolve('${ForumConstants.postsPath}/${post.id}'),
      body: _formEncode({
        'context': '/t/topic/${post.topicId}/${post.postNumber}',
      }),
    );
  }

  static RequestPayload deleteTopic(TopicListItem topic) {
    return RequestPayload(
      method: 'DELETE',
      url: ForumUrlResolver.resolve('/t/${topic.id}'),
      body: _formEncode({
        'context': '/t/topic/${topic.id}',
      }),
    );
  }

  static RequestPayload updateProfileSettings(
    String username,
    ProfileSettingsDraft draft,
  ) {
    final lower = username.toLowerCase();
    return RequestPayload(
      method: 'PUT',
      url: ForumUrlResolver.resolve('/u/$lower.json'),
      body: _formEncode({
        'bio_raw': draft.bioRaw,
        'profile_background_upload_url': draft.profileBackgroundUploadUrl,
        'card_background_upload_url': draft.cardBackgroundUploadUrl,
        'hide_profile': draft.hideProfile ? 'true' : 'false',
        'timezone': draft.timezone,
        'default_calendar': draft.defaultCalendar,
      }),
    );
  }

  static RequestPayload pickSystemAvatar(String username) {
    return RequestPayload(
      method: 'PUT',
      url: ForumUrlResolver.resolve(
        '/u/${username.toLowerCase()}/preferences/avatar/pick',
      ),
      body: _formEncode({
        'upload_id': '',
        'type': 'system',
      }),
    );
  }

  static RequestPayload pickCustomAvatar(String username, int uploadId) {
    return RequestPayload(
      method: 'PUT',
      url: ForumUrlResolver.resolve(
        '/u/${username.toLowerCase()}/preferences/avatar/pick',
      ),
      body: _formEncode({
        'upload_id': '$uploadId',
        'type': 'custom',
      }),
    );
  }

  static String _formEncode(Map<String, String> fields) {
    return _formEncodeEntries(fields.entries);
  }

  static String _formEncodeEntries(Iterable<MapEntry<String, String>> fields) {
    return fields
        .map((entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
  }

  static Map<String, String> decodeForm(String body) {
    return Map.fromEntries(
      body.split('&').where((part) => part.contains('=')).map((part) {
        final index = part.indexOf('=');
        return MapEntry(
          Uri.decodeQueryComponent(
              part.substring(0, index).replaceAll('+', ' ')),
          Uri.decodeQueryComponent(
              part.substring(index + 1).replaceAll('+', ' ')),
        );
      }),
    );
  }
}
