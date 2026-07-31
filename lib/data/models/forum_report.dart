enum ForumReportReason {
  offTopic(
    id: 3,
    label: '偏离话题',
    postDescription: '该评论与当前讨论无关。',
    allowsTopicReport: false,
  ),
  inappropriate(
    id: 4,
    label: '不当言论',
    postDescription: '该评论包含的内容会被一个有理性的人认为具有冒犯性、侮辱性。',
    topicDescription: '该帖包含的内容会被一个有理性的人认为具有冒犯性、侮辱性。',
  ),
  spam(
    id: 8,
    label: '垃圾信息',
    postDescription: '该评论是广告或者蓄意破坏讨论。评论没有价值或者与当前话题无关。',
    topicDescription: '该帖是一个广告。它对本论坛没有用或不相关。',
  ),
  illegal(
    id: 10,
    label: '非法',
    postDescription: '该评论需要工作人员注意，因为我认为其中包含非法内容。（请确保描述内容准确且完整。）',
    topicDescription: '该帖需要管理人员关注，因为我认为其中包含非法内容。',
    requiresMessage: true,
  ),
  other(
    id: 7,
    label: '其他内容',
    postDescription: '由于上面未列出的另一个原因，该评论需要管理人员注意。',
    topicDescription: '由于上面未列出的另一个原因，该帖需要管理人员注意。',
    requiresMessage: true,
  );

  const ForumReportReason({
    required this.id,
    required this.label,
    required this.postDescription,
    this.topicDescription,
    this.requiresMessage = false,
    this.allowsTopicReport = true,
  });

  final int id;
  final String label;
  final String postDescription;
  final String? topicDescription;
  final bool requiresMessage;
  final bool allowsTopicReport;

  String description({required bool flagTopic}) {
    return flagTopic ? topicDescription ?? postDescription : postDescription;
  }

  static List<ForumReportReason> optionsForTopic() {
    return values.where((reason) => reason.allowsTopicReport).toList();
  }

  static List<ForumReportReason> optionsForPost() {
    return values;
  }
}

class ForumReportDraft {
  const ForumReportDraft({
    required this.id,
    required this.reason,
    required this.flagTopic,
    this.message,
  });

  final int id;
  final ForumReportReason reason;
  final bool flagTopic;
  final String? message;
}
