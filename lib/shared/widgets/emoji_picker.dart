import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/emoji_recent_store.dart';
import '../../data/services/emoji_text.dart';
import '../theme/lehu_theme.dart';

Future<void> showEmojiPicker({
  required BuildContext context,
  required TextEditingController controller,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.lehuColors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return _EmojiPickerSheet(controller: controller);
    },
  );
}

class _EmojiPickerSheet extends StatefulWidget {
  const _EmojiPickerSheet({required this.controller});

  final TextEditingController controller;

  @override
  State<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<_EmojiPickerSheet> {
  List<String> _recentShortcodes = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecents());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lehuColors;
    final recentEntries = EmojiText.entriesForShortcodes(_recentShortcodes);
    final categories = [
      EmojiCategory('常用', recentEntries),
      ...EmojiText.categories.where((category) => category.label != '常用'),
    ];
    final height = MediaQuery.sizeOf(context).height * 0.58;
    return DefaultTabController(
      length: categories.length,
      initialIndex: categories.length > 1 ? 1 : 0,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Emoji',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: colors.textPrimary,
                unselectedLabelColor: colors.textTertiary,
                indicatorColor: colors.textPrimary,
                tabs: [
                  for (final category in categories) Tab(text: category.label),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final category in categories)
                      _EmojiGrid(
                        entries: category.entries,
                        controller: widget.controller,
                        onPicked: _recordRecent,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadRecents() async {
    final recents = await EmojiRecentStore.load();
    if (mounted) {
      setState(() => _recentShortcodes = recents);
    }
  }

  Future<void> _recordRecent(String shortcode) async {
    final recents = await EmojiRecentStore.record(shortcode);
    if (mounted) {
      setState(() => _recentShortcodes = recents);
    }
  }
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({
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
      final colors = context.lehuColors;
      return Center(
        child: Text(
          '最近使用过的 Emoji 会显示在这里',
          style: TextStyle(color: colors.textTertiary),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
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
              Navigator.of(context).pop();
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
