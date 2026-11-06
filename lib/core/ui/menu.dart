import 'package:flutter/material.dart';

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
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final error = Theme.of(context).colorScheme.error;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final item in items)
              ListTile(
                enabled: item.enabled,
                leading: item.icon == null
                    ? null
                    : Icon(item.icon, color: item.destructive ? error : null),
                title: Text(item.label, style: item.destructive ? TextStyle(color: error) : null),
                onTap: () => Navigator.of(context).pop(item.value),
              ),
          ],
        ),
      );
    },
  );
}
