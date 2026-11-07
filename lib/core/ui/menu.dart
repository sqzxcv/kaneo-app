import 'package:flutter/material.dart';

import '../layout/breakpoints.dart';
import '../theme/app_theme.dart';
import 'popover.dart';

/// One row of an action menu.
class MenuAction<T> {
  const MenuAction({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool destructive;
  final bool enabled;
}

/// Shows a menu and resolves to the chosen value, or null if dismissed.
///
/// The menu opens by [context]'s widget, so call it with the context of the button that was
/// pressed. For a right-click or long press, pass the pointer's global [position] as well.
Future<T?> showActionMenu<T>(
  BuildContext context, {
  required List<MenuAction<T>> items,
  Offset? position,
}) {
  return showPopover<T>(
    context,
    position: position,
    builder: (context) {
      final c = context.colors;
      return PopoverBody(
        rows: [
          for (final item in items)
            PopoverRow(
              enabled: item.enabled,
              title: item.label,
              color: item.destructive ? c.destructiveForeground : null,
              leading: item.icon == null
                  ? null
                  : Icon(
                      item.icon,
                      size: context.isWide ? 16 : 20,
                      color: item.destructive
                          ? c.destructiveForeground
                          : c.foreground.withValues(alpha: 0.8),
                    ),
              onTap: () => Navigator.of(context).pop(item.value),
            ),
        ],
      );
    },
  );
}

/// Opens a menu on [child] with a right-click, or a long press on a touch screen, at the pointer.
class ContextMenuRegion<T> extends StatelessWidget {
  const ContextMenuRegion({
    super.key,
    required this.items,
    required this.onSelected,
    required this.child,
  });

  /// Asked each time the menu opens, so that it shows the current state.
  final List<MenuAction<T>> Function() items;
  final ValueChanged<T> onSelected;
  final Widget child;

  Future<void> _open(BuildContext context, Offset position) async {
    final chosen = await showActionMenu<T>(context, items: items(), position: position);
    if (chosen != null) onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (details) => _open(context, details.globalPosition),
      onLongPressStart: (details) => _open(context, details.globalPosition),
      child: child,
    );
  }
}
