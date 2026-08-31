import 'package:flutter/material.dart';

import '../../shared/theme/lehu_theme.dart';
import '../../shared/widgets/app_header.dart';

class ForumFaqPage extends StatelessWidget {
  const ForumFaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: '论坛指南',
              showBack: true,
              onBack: () => Navigator.of(context).pop(),
              onNotification: () {},
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  _section(context, '这里是文明的公开讨论场所', [
                    '请像对待公园一样对待本论坛。我们也是共享的社区资源，在这里，可以通过持续对话分享技能、知识和兴趣。',
                    '这些不是硬性规定，而是帮助人们对我们社区做出判断的指导方针，使这里成为友好、文明的公共话语场所。',
                  ]),
                  _section(context, '改善讨论', [
                    '不管多小，始终在讨论中添加一些积极的内容，帮助我们让这里成为出色的讨论场所。如果您不确定您的帖子是否能增添对话内容，请想想您要说什么，然后再试一试。',
                    '改善讨论的一种方式是发现已经发生的问题。在回复或开始自己的话题讨论之前，花点时间浏览一下这里的话题，您会有更好的机会遇见兴趣相投的人。',
                    '这里讨论的话题对我们很重要，我们希望您能表现出它们对您也很重要。尊重话题和讨论这些话题的人，即使您并不赞同他们的观点。',
                  ]),
                  _section(context, '即使不赞同，也要心平气和', [
                    '您可能希望给出相反的意见。这很好。但要记住“对事不对人”。请避免：',
                  ], bullets: const ['谩骂', '人身攻击', '回应帖子的语气而不是实际内容', '未加思索地反驳'], tail: '相反，您应该提供深思熟虑的见解来改善对话。'),
                  _section(context, '您的参与很重要', [
                    '我们在这里的对话为每位新访客定下了基调。选择参与使这个论坛成为有趣地方的讨论，帮助我们影响这个社区的未来 — 避开那些不会使论坛向好发展的讨论。',
                    '我们提供了一些工具，使社区能够整体识别最佳（和最差）贡献：书签数、赞数、举报数、回复数、编辑数、关注数、免打扰数等。请使用这些工具来改善您自己和其他人的体验。',
                    '让我们的社区变得越来越美好。',
                  ]),
                  _section(context, '如果您发现问题，请举报', [
                    '版主拥有特殊权限；他们对这个论坛负责。您也一样。在您的帮助下，版主可以成为社区推动者，而不仅仅是看门人或监督者。',
                    '当您发现不良行为时，请不要回复。回复就表示对不良行为的承认，会助长这些不良行为，消耗您的精力，浪费大家的时间。',
                  ], tail: '只需举报即可。如果累积了足够多的举报，就会自动采取措施，或在版主的干预下采取措施。', emphasizeTail: true),
                  _section(context, '始终保持文明', ['没有什么比粗鲁更能破坏健康的对话了：'], bullets: const ['讲文明。不要发布任何理性的人会认为冒犯、辱骂或仇恨的内容。', '保持干净。不要发布任何淫秽或露骨的色情内容。', '互相尊重。不要骚扰或指责任何人，冒充别人，或暴露他们的私人信息。', '尊重我们的论坛。不要发布垃圾信息或以其他方式破坏论坛。'], tail: '这些都不是具有精确定义的具体条款，请避免任何此类内容的出现。如果您不确定，问问自己，如果您的帖子出现在主要新闻网站的头版，您会有什么感觉。\n\n这是一个公共论坛，搜索引擎会对这些讨论内容编制索引。请确保您的语言、链接和图像不会影响家人和朋友的安全。'),
                  _section(context, '保持整洁', ['努力将内容放在合适的位置，以便我们可以将更多的时间花在讨论而不是清理上。因此：'], bullets: const ['不要在错误的类别中开始话题；请阅读类别定义。', '不要在多个话题中重复发布相同的内容。', '不要发布无内容的回复。', '不要中途改变话题。', '不要在您的帖子上签名 — 每个帖子都附有您的个人资料。'], tail: '不要发布“+1”或“同意”，而要使用“点赞”按钮。不要从完全不同的方向讨论现有话题，而要使用“作为链接话题回复”。'),
                  _section(context, '仅发布自己的内容', ['未经允许，您不得发布属于他人的任何数字内容。您不得发布关于窃取他人知识产权（软件、视频、音频、图像）或违反任何其他法律的描述、链接或方法。']),
                  _section(context, '由您助力', ['本网站由您友好的版主团队和您（社区）共同运营。如果您对事情的运作方式有任何其他疑问，请开设新话题，我们一起讨论！如果您有无法通过元话题或举报解决的严重或紧急问题，请联系版主。']),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _section(BuildContext context, String title, List<String> paragraphs, {List<String> bullets = const [], String? tail, bool emphasizeTail = false}) {
    final colors = context.lehuColors;
    final children = <Widget>[Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 21, fontWeight: FontWeight.w700)), const SizedBox(height: 10)];
    for (final p in paragraphs) {
      children.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(p, style: TextStyle(color: colors.textPrimary, fontSize: 16, height: 1.55))));
    }
    if (bullets.isNotEmpty) children.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final b in bullets) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  '), Expanded(child: Text(b, style: TextStyle(color: colors.textPrimary, fontSize: 16, height: 1.45))) ]))])));
    if (tail != null) children.add(Text(tail, style: TextStyle(color: colors.textPrimary, fontSize: 16, height: 1.55, fontWeight: emphasizeTail ? FontWeight.w700 : FontWeight.w400)));
    return Padding(padding: const EdgeInsets.only(bottom: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
  }
}
