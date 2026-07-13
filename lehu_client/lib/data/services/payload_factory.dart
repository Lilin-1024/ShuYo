import '../../core/forum_constants.dart';
import '../models/composer.dart';
import '../models/post.dart';

class ReplyDraft {
  const ReplyDraft({
    required this.topicId,
    required this.categoryId,
    required this.raw,
    this.replyToPostNumber,
    this.archetype = 'regular',
    this.typingDurationMs = 1000,
    this.composerOpenDurationMs = 3000,
  });

  final int topicId;
  final int categoryId;
  final String raw;
  final int? replyToPostNumber;
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

    return RequestPayload(
      method: 'POST',
      url: '${ForumConstants.baseUrl}${ForumConstants.postsPath}',
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
      url: '${ForumConstants.baseUrl}${ForumConstants.postsPath}',
      body: _formEncode(fields),
    );
  }

  static RequestPayload createPrivateMessage(PrivateMessageDraft draft) {
    return RequestPayload(
      method: 'POST',
      url: '${ForumConstants.baseUrl}${ForumConstants.postsPath}',
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
      }),
    );
  }

  static RequestPayload likePost(int postId) {
    return RequestPayload(
      method: 'POST',
      url: '${ForumConstants.baseUrl}${ForumConstants.postActionsPath}',
      body: _formEncode({
        'id': '$postId',
        'post_action_type_id': '2',
        'flag_topic': 'false',
      }),
    );
  }

  static RequestPayload deletePost(Post post) {
    return RequestPayload(
      method: 'DELETE',
      url: '${ForumConstants.baseUrl}${ForumConstants.postsPath}/${post.id}',
      body: _formEncode({
        'context': '/t/topic/${post.topicId}/${post.postNumber}',
      }),
    );
  }

  static String _formEncode(Map<String, String> fields) {
    return fields.entries
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
