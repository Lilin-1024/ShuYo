import 'package:flutter/material.dart';

import '../../shared/widgets/empty_state.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.forum_outlined,
      title: '消息暂未接入',
      message: '第一版先保留占位。后续确认私信接口和回复层级后，再做原生消息列表。',
    );
  }
}
