import 'package:flutter/material.dart';

import '../../core/client_app_info.dart';
import '../../data/models/client_backend.dart';
import '../theme/lehu_theme.dart';

Future<bool> showClientUpdatePrompt(
  BuildContext context, {
  required ClientUpdateInfo update,
}) async {
  final openDownload = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final colors = dialogContext.lehuColors;
      return AlertDialog(
        title: Text(update.updateTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前版本：${ClientAppInfo.version}'),
              const SizedBox(height: 8),
              Text('最新版本：${update.latestVersion}'),
              if (update.updateMessage.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(update.updateMessage),
              ],
              if (update.noticeText.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  update.noticeText,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (update.hasDownloadUrl)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('更新'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  );
  return openDownload ?? false;
}
