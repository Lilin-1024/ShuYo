import 'package:flutter/material.dart';

import '../../data/models/category.dart';

class ForumFilterBar extends StatelessWidget {
  const ForumFilterBar({
    super.key,
    required this.categories,
    required this.isHot,
    required this.selectedCategoryId,
    required this.onToggleMode,
    required this.onSelectCategory,
  });

  final List<ForumCategory> categories;
  final bool isHot;
  final int? selectedCategoryId;
  final VoidCallback onToggleMode;
  final ValueChanged<int?> onSelectCategory;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        children: [
          _FilterChipButton(
            label: isHot ? '最热' : '最新',
            selected: true,
            icon: isHot ? Icons.local_fire_department : Icons.schedule,
            onTap: onToggleMode,
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: '全部',
            selected: selectedCategoryId == null,
            onTap: () => onSelectCategory(null),
          ),
          for (final category in categories) ...[
            const SizedBox(width: 8),
            _FilterChipButton(
              label: category.name,
              selected: selectedCategoryId == category.id,
              onTap: () => onSelectCategory(category.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEDEDED) : const Color(0xFF171717),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFEDEDED) : const Color(0xFF303030),
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.black : const Color(0xFFD6D6D6),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : const Color(0xFFD6D6D6),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
