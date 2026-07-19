import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/emoji_recent_store.dart';
import '../../data/services/emoji_text.dart';

class InlineEmojiPanel extends StatefulWidget {
  const InlineEmojiPanel({
    super.key,
    required this.controller,
    this.height = 282,
    this.onPicked,
  });

  final TextEditingController controller;
  final double height;
  final VoidCallback? onPicked;

  @override
  State<InlineEmojiPanel> createState() => _InlineEmojiPanelState();
}

class _InlineEmojiPanelState extends State<InlineEmojiPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<String> _recentShortcodes = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _categoryCount,
      vsync: this,
      initialIndex: _categoryCount > 1 ? 1 : 0,
      animationDuration: const Duration(milliseconds: 120),
    )..addListener(_handleTabChanged);
    unawaited(_loadRecentEmoji());
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recentEntries = EmojiText.entriesForShortcodes(_recentShortcodes);
    final categories = [
      EmojiCategory('常用', recentEntries),
      ...EmojiText.categories.where((category) => category.label != '常用'),
    ];
    return SizedBox(
      height: widget.height,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFF9A9A9A),
            indicatorColor: Colors.white,
            tabs: [
              for (final category in categories) Tab(text: category.label),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: _FastEmojiTabScrollPhysics(
                currentIndex: _tabController.index,
              ),
              children: [
                for (final category in categories)
                  _InlineEmojiGrid(
                    entries: category.entries,
                    controller: widget.controller,
                    onPicked: _recordRecentEmoji,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int get _categoryCount => EmojiText.categories.length;

  void _handleTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadRecentEmoji() async {
    final recents = await EmojiRecentStore.load();
    if (mounted) {
      setState(() => _recentShortcodes = recents);
    }
  }

  Future<void> _recordRecentEmoji(String shortcode) async {
    final recents = await EmojiRecentStore.record(shortcode);
    if (mounted) {
      setState(() => _recentShortcodes = recents);
    }
    widget.onPicked?.call();
  }
}

class _FastEmojiTabScrollPhysics extends PageScrollPhysics {
  const _FastEmojiTabScrollPhysics({
    required this.currentIndex,
    super.parent,
  });

  static const _switchThreshold = 0.25;

  final int currentIndex;

  @override
  _FastEmojiTabScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _FastEmojiTabScrollPhysics(
      currentIndex: currentIndex,
      parent: buildParent(ancestor),
    );
  }

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: 850,
        ratio: 1.08,
      );

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final target = _targetPixels(position, tolerance, velocity);
    if ((target - position.pixels).abs() <= tolerance.distance) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  double _targetPixels(
    ScrollMetrics position,
    Tolerance tolerance,
    double velocity,
  ) {
    final page = _pageFor(position);
    final currentPage = currentIndex.toDouble();
    final delta = page - currentPage;
    var targetPage = currentPage;

    if (velocity > tolerance.velocity || delta >= _switchThreshold) {
      targetPage = currentPage + 1;
    } else if (velocity < -tolerance.velocity || delta <= -_switchThreshold) {
      targetPage = currentPage - 1;
    }

    final minPage = _pageFor(position, pixels: position.minScrollExtent);
    final maxPage = _pageFor(position, pixels: position.maxScrollExtent);
    final clampedPage = targetPage.clamp(minPage, maxPage).toDouble();
    return _pixelsFor(position, clampedPage)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  double _pageFor(ScrollMetrics position, {double? pixels}) {
    final pagePixels = pixels ?? position.pixels;
    if (position is PageMetrics) {
      final viewport = position.viewportDimension * position.viewportFraction;
      if (viewport <= 0) {
        return 0;
      }
      final initialOffset = position.viewportFraction > 1
          ? position.viewportDimension * (position.viewportFraction - 1) / 2
          : 0.0;
      return (pagePixels - initialOffset) / viewport;
    }
    if (position.viewportDimension <= 0) {
      return 0;
    }
    return pagePixels / position.viewportDimension;
  }

  double _pixelsFor(ScrollMetrics position, double page) {
    if (position is PageMetrics) {
      final initialOffset = position.viewportFraction > 1
          ? position.viewportDimension * (position.viewportFraction - 1) / 2
          : 0.0;
      return page * position.viewportDimension * position.viewportFraction +
          initialOffset;
    }
    return page * position.viewportDimension;
  }
}

class _InlineEmojiGrid extends StatelessWidget {
  const _InlineEmojiGrid({
    required this.entries,
    required this.controller,
    required this.onPicked,
  });

  final List<EmojiEntry> entries;
  final TextEditingController controller;
  final Future<void> Function(String shortcode) onPicked;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          '最近使用过的 Emoji 会显示在这里',
          style: TextStyle(color: Color(0xFF9A9A9A)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      itemCount: entries.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Tooltip(
          message: entry.markup,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              EmojiText.insertText(controller, entry.value);
              unawaited(onPicked(entry.shortcode));
            },
            child: Center(
              child: Text(
                entry.value,
                style: const TextStyle(fontSize: 26),
              ),
            ),
          ),
        );
      },
    );
  }
}
