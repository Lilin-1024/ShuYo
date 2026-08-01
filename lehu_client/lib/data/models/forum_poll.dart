import '../../core/forum_url_resolver.dart';
import 'common.dart';

class ForumPoll {
  const ForumPoll({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.public,
    required this.results,
    required this.chartType,
    required this.options,
    this.voters = 0,
    this.min = 1,
    this.max = 0,
    this.title,
    this.preloadedVoters = const {},
    this.ownVotes = const [],
  });

  final int id;
  final String name;
  final String type;
  final String status;
  final bool public;
  final String results;
  final String chartType;
  final int voters;
  final int min;
  final int max;
  final String? title;
  final List<ForumPollOption> options;
  final Map<String, List<ForumPollVoter>> preloadedVoters;
  final List<String> ownVotes;

  bool get isMultiple => type == 'multiple';
  bool get isRegular => type == 'regular';
  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';
  bool get hasVoted => ownVotes.isNotEmpty;
  int get effectiveMin => isMultiple ? min.clamp(1, options.length).toInt() : 1;
  int get effectiveMax {
    if (!isMultiple) {
      return 1;
    }
    final fallback = options.length;
    return (max <= 0 ? fallback : max)
        .clamp(effectiveMin, options.length)
        .toInt();
  }

  int get totalOptionVotes {
    return options.fold(0, (sum, option) => sum + option.votes);
  }

  int get resultDenominator {
    if (voters > 0) {
      return voters;
    }
    return totalOptionVotes;
  }

  bool get canShowResults {
    if (results == 'always') {
      return true;
    }
    if (results == 'on_vote') {
      return hasVoted || isClosed;
    }
    if (results == 'on_close') {
      return isClosed;
    }
    return false;
  }

  List<ForumPollVoter> votersForOption(String optionId) {
    return preloadedVoters[optionId] ?? const [];
  }

  ForumPoll copyWith({
    String? status,
    List<ForumPollOption>? options,
    int? voters,
    Map<String, List<ForumPollVoter>>? preloadedVoters,
    List<String>? ownVotes,
  }) {
    return ForumPoll(
      id: id,
      name: name,
      type: type,
      status: status ?? this.status,
      public: public,
      results: results,
      chartType: chartType,
      options: options ?? this.options,
      voters: voters ?? this.voters,
      min: min,
      max: max,
      title: title,
      preloadedVoters: preloadedVoters ?? this.preloadedVoters,
      ownVotes: ownVotes ?? this.ownVotes,
    );
  }

  factory ForumPoll.fromJson(
    JsonMap json, {
    List<String> ownVotes = const [],
  }) {
    final optionsJson = json['options'];
    return ForumPoll(
      id: intValue(json['id']),
      name: stringValue(json['name'], 'poll'),
      type: stringValue(json['type'], 'regular'),
      status: stringValue(json['status'], 'open'),
      public: boolValue(json['public']),
      results: stringValue(json['results'], 'always'),
      chartType: stringValue(json['chart_type'] ?? json['chartType'], 'bar'),
      voters: intValue(json['voters']),
      min: intValue(json['min'], 1),
      max: intValue(json['max']),
      title: _nullableString(json['title']),
      options: optionsJson is List
          ? optionsJson
              .whereType<JsonMap>()
              .map(ForumPollOption.fromJson)
              .toList()
          : const [],
      preloadedVoters: _preloadedVoters(json['preloaded_voters']),
      ownVotes: List.unmodifiable(ownVotes),
    );
  }

  static String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Map<String, List<ForumPollVoter>> _preloadedVoters(Object? value) {
    if (value is! JsonMap) {
      return const {};
    }
    return {
      for (final entry in value.entries)
        entry.key: entry.value is List
            ? (entry.value as List)
                .whereType<JsonMap>()
                .map(ForumPollVoter.fromJson)
                .toList(growable: false)
            : const <ForumPollVoter>[],
    };
  }
}

class ForumPollOption {
  const ForumPollOption({
    required this.id,
    required this.html,
    this.votes = 0,
    this.chosen = false,
  });

  final String id;
  final String html;
  final int votes;
  final bool chosen;

  factory ForumPollOption.fromJson(JsonMap json) {
    return ForumPollOption(
      id: stringValue(json['id']),
      html: stringValue(json['html']),
      votes: intValue(json['votes']),
      chosen: boolValue(json['chosen']),
    );
  }
}

class ForumPollVoter {
  const ForumPollVoter({
    required this.id,
    required this.username,
    required this.avatarTemplate,
    this.title,
  });

  final int id;
  final String username;
  final String avatarTemplate;
  final String? title;

  factory ForumPollVoter.fromJson(JsonMap json) {
    return ForumPollVoter(
      id: intValue(json['id']),
      username: stringValue(json['username']),
      avatarTemplate: stringValue(json['avatar_template']),
      title: ForumPoll._nullableString(json['title']),
    );
  }

  String avatarUrl({int size = 72}) {
    final resolved = avatarTemplate.replaceAll('{size}', '$size');
    return ForumUrlResolver.resolve(resolved);
  }
}

class ForumPollVoteResult {
  const ForumPollVoteResult({
    required this.poll,
    required this.vote,
  });

  final ForumPoll poll;
  final List<String> vote;

  factory ForumPollVoteResult.fromJson(JsonMap json) {
    final voteJson = json['vote'];
    final vote = voteJson is List
        ? voteJson.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
    final pollJson = json['poll'];
    return ForumPollVoteResult(
      poll: pollJson is JsonMap
          ? ForumPoll.fromJson(pollJson, ownVotes: vote)
          : ForumPoll.fromJson(const <String, dynamic>{}, ownVotes: vote),
      vote: vote,
    );
  }
}
