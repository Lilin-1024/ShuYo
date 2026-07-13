import 'package:flutter/material.dart';

import '../../data/models/category.dart';
import '../../data/models/discourse_user.dart';
import '../../data/models/topic.dart';
import '../../data/services/html_text.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/avatar.dart';

class TopicListPage extends StatefulWidget {
  const TopicListPage({
    super.key,
    required this.topics,
    required this.users,
    required this.previewForTopic,
    required this.categoryById,
    required this.onOpenTopic,
    required this.canLoadMore,
    required this.isLoadingMore,
    this.onOpenUser,
    this.onLoadMore,
  });

  final List<TopicListItem> topics;
  final Map<int, DiscourseUser> users;
  final Future<TopicPreview> Function(int id) previewForTopic;
  final ForumCategory? Function(int id) categoryById;
  final ValueChanged<TopicListItem> onOpenTopic;
  final ValueChanged<DiscourseUser>? onOpenUser;
  final bool canLoadMore;
  final bool isLoadingMore;
  final Future<void> Function()? onLoadMore;

  @override
  State<TopicListPage> createState() => _TopicListPageState();
}

class _TopicListPageState extends State<TopicListPage> {
  final _scrollController = ScrollController();
  bool _requestingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: widget.topics.length + (_hasFooter ? 1 : 0),
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: Color(0xFF202020)),
      itemBuilder: (context, index) {
        if (index >= widget.topics.length) {
          return _LoadMoreFooter(
            canLoadMore: widget.canLoadMore,
            isLoadingMore: widget.isLoadingMore || _requestingMore,
            onPressed: _loadMore,
          );
        }
        final topic = widget.topics[index];
        final user = widget.users[topic.originalPosterId];
        return _TopicListRow(
          topic: topic,
          user: user,
          category: widget.categoryById(topic.categoryId),
          previewFuture: widget.previewForTopic(topic.id),
          onTap: () => widget.onOpenTopic(topic),
          onOpenUser: user == null ? null : () => widget.onOpenUser?.call(user),
        );
      },
    );
  }

  bool get _hasFooter => widget.canLoadMore || widget.isLoadingMore;

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter < 520) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final onLoadMore = widget.onLoadMore;
    if (onLoadMore == null ||
        !widget.canLoadMore ||
        widget.isLoadingMore ||
        _requestingMore) {
      return;
    }
    setState(() => _requestingMore = true);
    try {
      await onLoadMore();
    } finally {
      if (mounted) {
        setState(() => _requestingMore = false);
      }
    }
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.canLoadMore,
    required this.isLoadingMore,
    required this.onPressed,
  });

  final bool canLoadMore;
  final bool isLoadingMore;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: isLoadingMore
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: canLoadMore ? onPressed : null,
                icon: const Icon(Icons.expand_more),
                label: const Text('加载更多'),
              ),
      ),
    );
  }
}

class _TopicListRow extends StatelessWidget {
  const _TopicListRow({
    required this.topic,
    required this.previewFuture,
    required this.onTap,
    this.onOpenUser,
    this.user,
    this.category,
  });

  final TopicListItem topic;
  final DiscourseUser? user;
  final ForumCategory? category;
  final Future<TopicPreview> previewFuture;
  final VoidCallback onTap;
  final VoidCallback? onOpenUser;

  @override
  Widget build(BuildContext context) {
    final metaText = _topicTimeText(topic);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onOpenUser,
              child: Row(
                children: [
                  ForumAvatar(
                    url: user?.avatarUrl(size: 96) ?? '',
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.username ?? '未知用户',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFD6D6D6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (metaText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            metaText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF8A8A8A),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              topic.title,
              style: const TextStyle(
                  fontSize: 18, height: 1.22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            FutureBuilder<TopicPreview>(
              future: previewFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    '摘要加载失败',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xFFBDBDBD), height: 1.35),
                  );
                }
                final preview = snapshot.data;
                if (preview == null) {
                  return const Text(
                    '摘要加载中...',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xFFBDBDBD), height: 1.35),
                  );
                }
                return _PreviewContent(preview: preview);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _CategoryChip(category: category),
                const Spacer(),
                _Metric(
                    icon: Icons.mode_comment_outlined,
                    value: '${topic.replyCount}'),
                const SizedBox(width: 12),
                _Metric(
                    icon: Icons.visibility_outlined, value: '${topic.views}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _topicTimeText(TopicListItem topic) {
    return TimeFormat.compact(topic.lastPostedAt ?? topic.createdAt);
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({required this.preview});

  final TopicPreview preview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!preview.hasText && !preview.hasImages)
          const Text(
            '暂无摘要',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Color(0xFFBDBDBD), height: 1.35),
          ),
        if (preview.hasText)
          Text(
            preview.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFBDBDBD), height: 1.35),
          ),
        if (preview.hasText && preview.hasImages) const SizedBox(height: 10),
        if (preview.hasImages) _PreviewImages(urls: preview.imageUrls),
      ],
    );
  }
}

class _PreviewImages extends StatelessWidget {
  const _PreviewImages({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) {
      return _SinglePreviewImage(url: urls.first);
    }
    return _ImageThumbnailRow(urls: urls);
  }
}

class _SinglePreviewImage extends StatelessWidget {
  const _SinglePreviewImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: Image.network(
          url,
          width: double.infinity,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          errorBuilder: (context, error, stackTrace) {
            return const _ImageFallback(height: 150);
          },
        ),
      ),
    );
  }
}

class _ImageThumbnailRow extends StatelessWidget {
  const _ImageThumbnailRow({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    const gap = 6.0;
    final visibleUrls = urls.take(3).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = (constraints.maxWidth - gap * 2) / 3;
        return Row(
          children: [
            for (var index = 0; index < visibleUrls.length; index++) ...[
              _SquareThumbnail(
                url: visibleUrls[index],
                size: tileSize,
                badgeText:
                    index == 2 && urls.length > 3 ? '共${urls.length}张' : null,
              ),
              if (index != visibleUrls.length - 1) const SizedBox(width: gap),
            ],
          ],
        );
      },
    );
  }
}

class _SquareThumbnail extends StatelessWidget {
  const _SquareThumbnail({
    required this.url,
    required this.size,
    this.badgeText,
  });

  final String url;
  final double size;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const _ImageFallback();
              },
            ),
            if (badgeText != null)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({this.height});

  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      alignment: Alignment.center,
      color: const Color(0xFF1C1C1C),
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Color(0xFF8A8A8A),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final ForumCategory? category;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(category?.color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          category?.name ?? '未知分区',
          style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF8A8A8A)),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(color: Color(0xFFBDBDBD), fontSize: 13)),
      ],
    );
  }
}

Color _parseColor(String? hex) {
  final normalized = hex == null || hex.length != 6 ? '333333' : hex;
  return Color(int.parse('0xFF$normalized'));
}
