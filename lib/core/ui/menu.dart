import 'package:flutter/gestures.dart';
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

/// Calls [onMenu] with the pointer's global position on a right-click, or on a long press on a touch
/// screen. A null [onMenu] turns both off.
///
/// A long press is over once it has asked for the menu, so the next one on [child] starts afresh
/// even if this press's end never arrives. Otherwise only the menu's route ends it, by cancelling the
/// pointer, and if that cancel is lost, as integration tests lose it, [child] never long-presses
/// again.
class MenuGestures extends StatelessWidget {
  const MenuGestures({super.key, required this.onMenu, required this.child, this.longPressDevices});

  final ValueChanged<Offset>? onMenu;
  final Widget child;

  /// The kinds of pointer whose long press opens the menu, or null for all of them. Leave a kind
  /// out when its long press does something else on [child], such as picking it up.
  final Set<PointerDeviceKind>? longPressDevices;

  @override
  Widget build(BuildContext context) {
    final onMenu = this.onMenu;
    return RawGestureDetector(
      gestures: {
        if (onMenu != null) ...{
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(debugOwner: this),
            (recognizer) =>
                recognizer.onSecondaryTapDown = (details) => onMenu(details.globalPosition),
          ),
          _MenuLongPress: GestureRecognizerFactoryWithHandlers<_MenuLongPress>(
            () => _MenuLongPress(debugOwner: this),
            (recognizer) => recognizer
              ..devices = longPressDevices
              ..onLongPressStart = (details) => onMenu(details.globalPosition),
          ),
        },
      },
      semantics: onMenu == null ? null : _MenuSemantics(onMenu),
      child: child,
    );
  }
}

/// Lets screen readers long-press too, opening the menu at the middle of what they pressed.
class _MenuSemantics extends SemanticsGestureDelegate {
  const _MenuSemantics(this.onMenu);

  final ValueChanged<Offset> onMenu;

  @override
  void assignSemantics(RenderSemanticsGestureHandler renderObject) {
    renderObject.onLongPress = () =>
        onMenu(renderObject.localToGlobal(renderObject.size.center(Offset.zero)));
  }
}

/// A long press that ends itself as soon as it has started, the way the menu's route would end it.
class _MenuLongPress extends LongPressGestureRecognizer {
  _MenuLongPress({super.debugOwner});

  /// The kinds of pointer it answers, or null for all. Unlike [supportedDevices] it can change
  /// while the recognizer lives on.
  Set<PointerDeviceKind>? devices;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      (devices?.contains(event.kind) ?? true) && super.isPointerAllowed(event);

  @override
  void didExceedDeadline() {
    final pointer = primaryPointer!;
    super.didExceedDeadline();
    if (state == GestureRecognizerState.possible && primaryPointer == pointer) {
      handleEvent(PointerCancelEvent(pointer: pointer));
    }
  }
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
    return MenuGestures(onMenu: (position) => _open(context, position), child: child);
  }
}
