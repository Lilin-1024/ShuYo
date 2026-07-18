import 'package:flutter/material.dart';

import '../../data/models/announcement.dart';
import '../../data/repositories/announcement_repository.dart';
import '../../data/services/announcement_api_client.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/navigation/lehu_route.dart';
import '../../shared/widgets/empty_state.dart';

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
            return const Center(child: CircularProgressIndicator());
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
                return const Divider(height: 1, color: Color(0xFF202020));
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
      lehuRoute(
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
            return const Center(child: CircularProgressIndicator());
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            children: [
              Text(
                detail.title,
                style: LehuTextStyles.title(
                  size: 20,
                  height: 1.22,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _AnnouncementMetadata(detail: detail),
              const SizedBox(height: 22),
              if (!detail.hasContent)
                const Text(
                  '这条公告暂时没有解析到正文。',
                  style: TextStyle(color: Color(0xFF9A9A9A)),
                )
              else
                ...detail.blocks.map(_blockWidget),
            ],
          );
        },
      ),
    );
  }

  Widget _blockWidget(AnnouncementContentBlock block) {
    if (block.isImage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            block.value,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 120,
                alignment: Alignment.center,
                color: const Color(0xFF171717),
                child: const Text(
                  '图片加载失败',
                  style: TextStyle(color: Color(0xFF9A9A9A)),
                ),
              );
            },
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: SelectableText(
        block.value,
        style: const TextStyle(
          fontSize: 16,
          height: 1.7,
          color: Color(0xFFEDEDED),
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
                    style: LehuTextStyles.title(
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
                      style: const TextStyle(
                        color: Color(0xFFAAAAAA),
                        fontSize: 14.5,
                        height: 1.46,
                      ),
                    ),
                  ],
                  if (item.dateText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.dateText,
                      style: const TextStyle(
                        color: Color(0xFF7D7D7D),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, color: Color(0xFF7D7D7D)),
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
      style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 13),
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
