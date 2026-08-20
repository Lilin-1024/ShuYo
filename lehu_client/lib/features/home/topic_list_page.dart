import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/models/category.dart';
import '../../data/models/discourse_user.dart';
import '../../data/models/topic.dart';
import '../../data/services/html_text.dart';
import '../../shared/lehu_text_styles.dart';
import '../../shared/theme/lehu_theme.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/forum_network_image.dart';

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
    this.loadMoreError,
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
  final String? loadMoreError;
  final Future<void> Function()? onLoadMore;

  @override
  State<TopicListPage> createState() => _TopicListPageState();
}

class _TopicListPageState extends State<TopicListPage> {
  static const _initialPreviewWarmCount = 6;
  static const _initialPreviewWarmTimeout = Duration(milliseconds: 1200);

  final _scrollController = ScrollController();
  final _previewFutures = <int, Future<TopicPreview>>{};
  final _previewCache = <int, TopicPreview>{};
  int _previewWarmToken = 0;
  String? _previewWarmSignature;
  bool _requestingMore = false;
  bool _warmingInitialPreviews = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _scheduleInitialPreviewWarmup(notify: false);
  }

  @override
  void didUpdateWidget(covariant TopicListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final topicIds = widget.topics.map((topic) => topic.id).toSet();
    _previewFutures.removeWhere((id, _) => !topicIds.contains(id));
    _previewCache.removeWhere((id, _) => !topicIds.contains(id));
    _scheduleInitialPreviewWarmup();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _previewWarmToken++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    if (_warmingInitialPreviews) {
      return const _TopicListLoading();
    }
    return ListView.separated(
      controller: _scrollController,
      scrollCacheExtent: ScrollCacheExtent.pixels(1200),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: widget.topics.length + (_hasFooter ? 1 : 0),
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: colors.border),
      itemBuilder: (context, index) {
        if (index >= widget.topics.length) {
          return _LoadMoreFooter(
            canLoadMore: widget.canLoadMore,
            isLoadingMore: widget.isLoadingMore || _requestingMore,
            errorMessage: widget.loadMoreError,
            onPressed: _loadMore,
          );
        }
        final topic = widget.topics[index];
        final user = widget.users[topic.originalPosterId];
        return _TopicListRow(
          topic: topic,
          user: user,
          category: widget.categoryById(topic.categoryId),
          previewFuture: _previewForTopic(topic.id),
          cachedPreview: _previewCache[topic.id],
          onTap: () => widget.onOpenTopic(topic),
          onOpenUser: user == null ? null : () => widget.onOpenUser?.call(user),
        );
      },
    );
  }

  Future<TopicPreview> _previewForTopic(int id) {
    return _previewFutures[id] ??= _loadPreview(id);
  }

  Future<TopicPreview> _loadPreview(int id) async {
    try {
      final preview = await widget.previewForTopic(id);
      _previewCache[id] = preview;
      return preview;
    } on Object {
      _previewFutures.remove(id);
      return _previewCache[id] ?? const TopicPreview(text: '暂无摘要', images: []);
    }
  }

  bool get _hasFooter =>
      widget.canLoadMore ||
      widget.isLoadingMore ||
      widget.loadMoreError != null;

  void _scheduleInitialPreviewWarmup({bool notify = true}) {
    final ids = widget.topics
        .take(_initialPreviewWarmCount)
        .map((topic) => topic.id)
        .toList(growable: false);
    final signature = ids.join(',');
    if (signature == _previewWarmSignature) {
      return;
    }
    _previewWarmSignature = signature;
    final token = ++_previewWarmToken;
    final missingIds = ids
        .where((id) => !_previewCache.containsKey(id))
        .toList(growable: false);
    if (missingIds.isEmpty) {
      if (!_warmingInitialPreviews) {
        return;
      }
      if (notify) {
        setState(() => _warmingInitialPreviews = false);
      } else {
        _warmingInitialPreviews = false;
      }
      return;
    }
    if (notify) {
      setState(() => _warmingInitialPreviews = true);
    } else {
      _warmingInitialPreviews = true;
    }
    unawaited(_warmInitialPreviews(missingIds, token));
  }

  Future<void> _warmInitialPreviews(List<int> ids, int token) async {
    final futures = [
      for (final id in ids)
        _previewForTopic(id).then<void>((_) {}).catchError((Object _) {}),
    ];
    await Future.any<void>([
      Future.wait<void>(futures).then<void>((_) {}),
      Future<void>.delayed(_initialPreviewWarmTimeout),
    ]);
    if (!mounted || token != _previewWarmToken) {
      return;
    }
    setState(() => _warmingInitialPreviews = false);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (widget.loadMoreError != null) {
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
    this.errorMessage,
    required this.onPressed,
  });

  final bool canLoadMore;
  final bool isLoadingMore;
  final String? errorMessage;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final errorMessage = this.errorMessage;
    final colors = context.lehuColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: isLoadingMore
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : errorMessage != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        errorMessage,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: canLoadMore ? onPressed : null,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('重试'),
                      ),
                    ],
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

class _TopicListLoading extends StatelessWidget {
  const _TopicListLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
}

class _TopicListRow extends StatelessWidget {
  const _TopicListRow({
    required this.topic,
    required this.previewFuture,
    this.cachedPreview,
    required this.onTap,
    this.onOpenUser,
    this.user,
    this.category,
  });

  final TopicListItem topic;
  final DiscourseUser? user;
  final ForumCategory? category;
  final Future<TopicPreview> previewFuture;
  final TopicPreview? cachedPreview;
  final VoidCallback onTap;
  final VoidCallback? onOpenUser;

  @override
  Widget build(BuildContext context) {
    final metaText = _topicTimeText(topic);
    final colors = context.lehuColors;
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
                          style: LehuTextStyles.title(
                            color: colors.listAuthor,
                            size: 14.5,
                            weight: FontWeight.w500,
                          ),
                        ),
                        if (metaText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            metaText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textMuted,
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
              style: LehuTextStyles.title(
                color: colors.textPrimary,
                size: 16.5,
                height: 1.24,
                weight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<TopicPreview>(
              future: previewFuture,
              initialData: cachedPreview,
              builder: (context, snapshot) {
                final preview = snapshot.data ?? cachedPreview;
                if (preview != null) {
                  return _PreviewContent(preview: preview);
                }
                if (snapshot.hasError) {
                  return const _PreviewContent(
                    preview: TopicPreview(text: '暂无摘要', images: []),
                  );
                }
                return const SizedBox.shrink();
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
    return TimeFormat.compact(
      topic.lastPostedAt ?? topic.createdAt,
      relativeWithinDay: true,
    );
  }
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({required this.preview});

  final TopicPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!preview.hasText && !preview.hasImages)
          Text(
            '暂无摘要',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 15,
              height: 1.42,
              fontWeight: FontWeight.w400,
            ),
          ),
        if (preview.hasText)
          Text(
            preview.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              height: 1.42,
              fontWeight: FontWeight.w400,
            ),
          ),
        if (preview.hasText && preview.hasImages) const SizedBox(height: 10),
        if (preview.hasImages) _PreviewImages(images: preview.images),
      ],
    );
  }
}

class _PreviewImages extends StatelessWidget {
  const _PreviewImages({required this.images});

  final List<TopicPreviewImage> images;

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      return _SinglePreviewImage(image: images.first);
    }
    return _ImageThumbnailRow(images: images);
  }
}

class _SinglePreviewImage extends StatelessWidget {
  const _SinglePreviewImage({required this.image});

  final TopicPreviewImage image;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width - 32;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final aspectRatio = image.aspectRatio ?? 1.45;
        final naturalHeight = width / aspectRatio;
        final height = naturalHeight.clamp(150.0, 260.0).toDouble();
        final imageWidth = (height * aspectRatio).clamp(90.0, width).toDouble();
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: imageWidth,
            height: height,
            child: ForumNetworkImage(
              image.url,
              width: imageWidth,
              height: height,
              fit: BoxFit.cover,
              alignment: Alignment.centerLeft,
              errorBuilder: (context, error, stackTrace) {
                return _ImageFallback(height: height);
              },
            ),
          ),
        );
      },
    );
  }
}

class _ImageThumbnailRow extends StatelessWidget {
  const _ImageThumbnailRow({required this.images});

  final List<TopicPreviewImage> images;

  @override
  Widget build(BuildContext context) {
    const gap = 6.0;
    final visibleImages = images.take(3).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = (constraints.maxWidth - gap * 2) / 3;
        return Row(
          children: [
            for (var index = 0; index < visibleImages.length; index++) ...[
              _SquareThumbnail(
                url: visibleImages[index].url,
                size: tileSize,
                badgeText: index == 2 && images.length > 3
                    ? '共${images.length}张'
                    : null,
              ),
              if (index != visibleImages.length - 1) const SizedBox(width: gap),
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
            ForumNetworkImage(
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
                      fontWeight: FontWeight.w600,
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
    final colors = context.lehuColors;
    return Container(
      height: height,
      alignment: Alignment.center,
      color: colors.surfaceMuted,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: colors.textMuted,
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
    final colors = context.lehuColors;
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
          style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
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
    final colors = context.lehuColors;
    return Row(
      children: [
        Icon(icon, size: 16, color: colors.textMuted),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
        ),
      ],
    );
  }
}

Color _parseColor(String? hex) {
  final normalized = hex == null || hex.length != 6 ? '333333' : hex;
  return Color(int.parse('0xFF$normalized'));
}
