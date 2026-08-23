import 'package:flutter/material.dart';

class ForumRegistrationPlaceholderPage extends StatefulWidget {
  const ForumRegistrationPlaceholderPage({super.key});

  @override
  State<ForumRegistrationPlaceholderPage> createState() =>
      _ForumRegistrationPlaceholderPageState();
}

class _ForumRegistrationPlaceholderPageState
    extends State<ForumRegistrationPlaceholderPage> {
  final _nickname = TextEditingController();

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('创建乐乎账户')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '设置论坛昵称',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '该昵称将显示在乐乎论坛中。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nickname,
              autofocus: true,
              maxLength: 20,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '论坛昵称',
                prefixIcon: Icon(Icons.person_outline),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _nickname.text.trim().isEmpty ? null : _showPending,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('完成注册'),
            ),
            const SizedBox(height: 12),
            Text(
              '注册提交将在补充新账户抓包后开放。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPending() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('论坛注册接口暂未接入')),
      );
  }
}
