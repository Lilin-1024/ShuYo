import 'package:flutter/material.dart';

import '../lehu_text_styles.dart';
import '../theme/lehu_theme.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    required this.onNotification,
    this.showBack = false,
    this.showSettings = false,
    this.showMore = false,
    this.showSearch = false,
    this.showCreate = false,
    this.notificationCount = 0,
    this.onBack,
    this.onSettings,
    this.onMore,
    this.onSearch,
    this.onCreate,
    this.onTitleTap,
    this.onTitleDoubleTap,
  });

  final String title;
  final bool showBack;
  final bool showSettings;
  final bool showMore;
  final bool showSearch;
  final bool showCreate;
  final int notificationCount;
  final VoidCallback? onBack;
  final VoidCallback? onSettings;
  final VoidCallback? onMore;
  final VoidCallback? onSearch;
  final VoidCallback? onCreate;
  final VoidCallback? onTitleTap;
  final VoidCallback? onTitleDoubleTap;
  final VoidCallback onNotification;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: showBack
                ? IconButton(
                    tooltip: '返回',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  )
                : IconButton(
                    tooltip: '通知',
                    onPressed: onNotification,
                    icon: _NotificationIcon(count: notificationCount),
                  ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTitleTap,
              onDoubleTap: onTitleDoubleTap,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LehuTextStyles.headerTitle(color: colors.textPrimary),
                ),
              ),
            ),
          ),
          if (showSettings)
            IconButton(
              tooltip: '设置',
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          if (showSearch)
            IconButton(
              tooltip: '搜索',
              onPressed: onSearch,
              icon: const Icon(Icons.search),
            ),
          if (showCreate)
            IconButton(
              tooltip: '发帖',
              onPressed: onCreate,
              icon: const Icon(Icons.add),
            ),
          if (showMore)
            IconButton(
              tooltip: '更多',
              onPressed: onMore,
              icon: const Icon(Icons.more_horiz),
            )
          else if (!showSettings && !showSearch && !showCreate)
            const SizedBox(width: 48),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    if (count <= 0) {
      return const Icon(Icons.notifications_none);
    }
    final label = count > 99 ? '99+' : '$count';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.notifications_none),
        Positioned(
          right: -8,
          top: -8,
          child: Container(
            constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.danger,
              shape: BoxShape.rectangle,
              borderRadius: const BorderRadius.all(Radius.circular(9)),
            ),
            child: Text(
              label,
              style: LehuTextStyles.chip(
                color: colors.onDanger,
                size: 10,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
