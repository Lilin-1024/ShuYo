import 'package:flutter/material.dart';

import '../../data/models/category.dart';
import '../../shared/theme/shuyo_theme.dart';

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 0, 8),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            _FilterChipButton(
              label: isHot ? '最热' : '最新',
              selected: true,
              icon: isHot ? Icons.local_fire_department : Icons.schedule,
              onTap: onToggleMode,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 16),
                children: [
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
            ),
          ],
        ),
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
    final colors = context.shuyoColors;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? colors.selectedFill : colors.chipFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? colors.selectedFill : colors.chipBorder,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? colors.onSelectedFill : colors.textSecondary,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? colors.onSelectedFill : colors.textSecondary,
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
