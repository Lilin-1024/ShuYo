enum ForumReportReason {
  offTopic(
    id: 3,
    label: '偏离话题',
    allowsTopicReport: false,
  ),
  inappropriate(
    id: 4,
    label: '不当言论',
  ),
  spam(
    id: 8,
    label: '垃圾信息',
  ),
  illegal(
    id: 10,
    label: '非法',
    requiresMessage: true,
  ),
  other(
    id: 7,
    label: '其他内容',
    requiresMessage: true,
  );

  const ForumReportReason({
    required this.id,
    required this.label,
    this.requiresMessage = false,
    this.allowsTopicReport = true,
  });

  final int id;
  final String label;
  final bool requiresMessage;
  final bool allowsTopicReport;

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
