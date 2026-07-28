import 'package:flutter/material.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'ai_ui_modal_wrapper.dart';

class SettingsSelectionModal<T> extends StatelessWidget {
  const SettingsSelectionModal({
    super.key,
    required this.title,
    required this.items,
    required this.selectedItem,
    required this.onSelected,
    this.itemIcon,
    this.itemLabel,
  });

  final String title;
  final List<T> items;
  final T selectedItem;
  final ValueChanged<T> onSelected;
  final IconData Function(T)? itemIcon;
  final String Function(T)? itemLabel;

  @override
  Widget build(BuildContext context) {
    return AiUiModalWrapper(
      // 下面那个列表自己会滚，不要再套一层。
      scrollableContent: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = item == selectedItem;
                final label = itemLabel?.call(item) ?? item.toString();
                final icon = itemIcon?.call(item);

                return _SelectionTile(
                      label: label,
                      icon: icon,
                      isSelected: isSelected,
                      onTap: () {
                        onSelected(item);
                        Navigator.of(context).pop(item);
                      },
                    )
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (200 + index * 50).ms)
                    .slideX(
                      begin: 0.1,
                      end: 0,
                      duration: 300.ms,
                      delay: (200 + index * 50).ms,
                    );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionTile extends StatelessWidget {
  const _SelectionTile({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: isLight ? 0.08 : 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).aiUi.secondaryTextColor,
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? (isLight
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white)
                        : Theme.of(context).aiUi.secondaryTextColor,
                  ),
                ),
              ),
              if (isSelected)
                Icon(
                  FluentIcons.checkmark_circle_24_filled,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
