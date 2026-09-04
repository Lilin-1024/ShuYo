import 'package:flutter/material.dart';

import '../../data/models/announcement.dart';
import '../../data/repositories/announcement_repository.dart';
import '../../data/services/announcement_api_client.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/fullscreen_image_page.dart';

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({
    super.key,
    required this.repository,
  });

  final AnnouncementRepository repository;

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  late Future<List<AnnouncementListItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchAnnouncements();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知公告')),
      body: FutureBuilder<List<AnnouncementListItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 3));
          }
          if (snapshot.hasError) {
            return _AnnouncementErrorState(
              message: _friendlyError(snapshot.error!),
              onRetry: _refresh,
            );
          }
          final items = snapshot.data ?? const <AnnouncementListItem>[];
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 96),
                  EmptyState(
                    icon: Icons.campaign_outlined,
                    title: '暂无公告',
                    message: '学校官网暂时没有返回通知公告。',
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemBuilder: (context, index) {
                return _AnnouncementTile(
                  item: items[index],
                  onTap: () => _openDetail(items[index]),
                );
              },
              separatorBuilder: (context, index) {
                return Divider(height: 1, color: context.shuyoColors.border);
              },
              itemCount: items.length,
            ),
          );
        },
      ),
    );
  }

  Future<void> _refresh() async {
    final future = widget.repository.fetchAnnouncements(forceRefresh: true);
    setState(() {
      _future = future;
    });
    await future;
  }

  void _openDetail(AnnouncementListItem item) {
    Navigator.of(context).push<void>(
      shuyoRoute(
        builder: (context) => AnnouncementDetailPage(
          repository: widget.repository,
          item: item,
        ),
      ),
    );
  }

  String _friendlyError(Object error) {
    if (error is AnnouncementApiException) {
      return error.message;
    }
    return '通知公告加载失败，请稍后重试';
  }
}

class AnnouncementDetailPage extends StatefulWidget {
  const AnnouncementDetailPage({
    super.key,
    required this.repository,
    required this.item,
  });

  final AnnouncementRepository repository;
  final AnnouncementListItem item;

  @override
  State<AnnouncementDetailPage> createState() => _AnnouncementDetailPageState();
}

class _AnnouncementDetailPageState extends State<AnnouncementDetailPage> {
  late Future<AnnouncementDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchDetail(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('公告详情')),
      body: FutureBuilder<AnnouncementDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 3));
          }
          if (snapshot.hasError) {
            return _AnnouncementErrorState(
              message: '公告详情加载失败，请稍后重试',
              onRetry: () async {
                setState(() {
                  _future = widget.repository.fetchDetail(widget.item);
                });
              },
            );
          }
          final detail = snapshot.data!;
          final colors = context.shuyoColors;
          final imageUrls = detail.blocks
              .where((block) => block.isImage)
              .map((block) => block.value)
              .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              Text(
                detail.title,
                style: ShuYoTextStyles.title(
                  color: colors.textPrimary,
                  size: 20,
                  height: 1.22,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _AnnouncementMetadata(detail: detail),
              const SizedBox(height: 22),
              if (!detail.hasContent)
                Text(
                  '这条公告暂时没有解析到正文。',
                  style: TextStyle(color: colors.textTertiary),
                )
              else
                ...List.generate(detail.blocks.length, (index) {
                  final block = detail.blocks[index];
                  final imageIndex = block.isImage
                      ? detail.blocks
                              .take(index + 1)
                              .where((item) => item.isImage)
                              .length -
                          1
                      : 0;
                  return _blockWidget(
                    block,
                    imageUrls: imageUrls,
                    imageIndex: imageIndex,
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _blockWidget(
    AnnouncementContentBlock block, {
    required List<String> imageUrls,
    required int imageIndex,
  }) {
    if (block.isImage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: GestureDetector(
          onTap: () {
            Navigator.of(context).push<void>(
              shuyoRoute(
                builder: (context) => FullscreenImagePage(
                  urls: imageUrls,
                  initialIndex: imageIndex,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              block.value,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                final colors = context.shuyoColors;
                return Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: colors.surfaceAlt,
                  child: Text(
                    '图片加载失败',
                    style: TextStyle(color: colors.textTertiary),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: SelectableText(
        block.value,
        style: TextStyle(
          fontSize: 16,
          height: 1.7,
          color: context.shuyoColors.textPrimary,
        ),
      ),
    );
  }
}

class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({
    required this.item,
    required this.onTap,
  });

  final AnnouncementListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: ShuYoTextStyles.title(
                      color: colors.textPrimary,
                      size: 16,
                      height: 1.26,
                      weight: FontWeight.w500,
                    ),
                  ),
                  if (item.summary.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      item.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 14.5,
                        height: 1.46,
                      ),
                    ),
                  ],
                  if (item.dateText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.dateText,
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementMetadata extends StatelessWidget {
  const _AnnouncementMetadata({required this.detail});

  final AnnouncementDetail detail;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (detail.dateText.isNotEmpty) detail.dateText,
      if (detail.department.isNotEmpty) detail.department,
      if (detail.author.isNotEmpty) detail.author,
    ];
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      parts.join(' · '),
      style: TextStyle(color: context.shuyoColors.textTertiary, fontSize: 13),
    );
  }
}

class _AnnouncementErrorState extends StatelessWidget {
  const _AnnouncementErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: '加载失败',
      message: message,
      action: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重试'),
      ),
    );
  }
}
