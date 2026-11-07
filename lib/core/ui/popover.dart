import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../layout/breakpoints.dart';
import '../theme/app_theme.dart';

/// The gap the web app leaves between a popover and what it opens from.
const double _anchorGap = 4;

/// How close a popover may come to the window's edges.
const double _windowMargin = 8;

/// With less room than this on both sides of its anchor, a popover covers the anchor instead.
const double _minRoom = 160;

/// Where a popover of [size] opening from [anchor] goes inside [bounds].
///
/// It starts below the anchor at its left edge, as most of the web app's popovers do. It flips to
/// the other side when it does not fit, and stays in [bounds] when it fits on neither.
Offset placePopover(Rect anchor, Size size, Rect bounds) {
  var left = anchor.left;
  if (left + size.width > bounds.right) left = anchor.right - size.width;
  var top = anchor.bottom + _anchorGap;
  if (top + size.height > bounds.bottom) {
    final above = anchor.top - _anchorGap - size.height;
    if (above >= bounds.top) top = above;
  }
  return Offset(
    left.clamp(bounds.left, math.max(bounds.left, bounds.right - size.width)),
    top.clamp(bounds.top, math.max(bounds.top, bounds.bottom - size.height)),
  );
}

/// How tall a popover opening from [anchor] may be: the room on the roomier side of the anchor.
double popoverHeightLimit(Rect anchor, Rect bounds) {
  final room = math.max(
    bounds.bottom - anchor.bottom - _anchorGap,
    anchor.top - _anchorGap - bounds.top,
  );
  return room < _minRoom ? bounds.height : room;
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout(this.anchor, this.insets);

  final Rect anchor;
  final EdgeInsets insets;

  Rect _bounds(Size window) => insets.deflateRect(Offset.zero & window);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final bounds = _bounds(constraints.biggest);
    return BoxConstraints(maxWidth: bounds.width, maxHeight: popoverHeightLimit(anchor, bounds));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      placePopover(anchor, childSize, _bounds(size));

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor || insets != oldDelegate.insets;
}

/// The area [context]'s widget covers in [overlay], or just the point at the global [position].
Rect _anchorIn(RenderBox overlay, BuildContext context, Offset? position) {
  if (position != null) return overlay.globalToLocal(position) & Size.zero;
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  }
  return overlay.size.center(Offset.zero) & Size.zero;
}

/// Shows [builder]'s content the way each layout does it, and resolves to what it pops with, or
/// null if dismissed. Wide windows get a floating popover and narrow ones a bottom sheet.
///
/// The popover opens by [context]'s widget, or at the global [position] for a right-click. Clicking
/// outside, right-clicking outside and Esc all close it. It sizes itself to its content unless
/// [width] is given. Start the content with [PopoverBody].
Future<T?> showPopover<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Offset? position,
  double? width,
}) {
  if (!context.isWide) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final media = MediaQuery.of(context);
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
            child: SafeArea(top: false, child: builder(context)),
          ),
        );
      },
    );
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  // Measured once. If the anchor moves later, such as when the window is resized, the popover stays
  // where it is, kept inside the window by its layout.
  final anchor = _anchorIn(overlay, context, position);
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (context, animation, _) {
      final media = MediaQuery.of(context);
      final curved = animation.drive(CurveTween(curve: Curves.easeOut));
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (_) => Navigator.of(context).maybePop(),
        child: CustomSingleChildLayout(
          delegate: _PopoverLayout(
            anchor,
            media.padding + media.viewInsets + const EdgeInsets.all(_windowMargin),
          ),
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              alignment: Alignment.topLeft,
              scale: curved.drive(Tween(begin: 0.98, end: 1)),
              // Keeps a right-click inside from counting as one outside.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapUp: (_) {},
                child: PopoverSurface(
                  width: width,
                  child: Builder(builder: builder),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The web app's popover: `rounded-lg border bg-popover shadow-lg/5`.
class PopoverSurface extends StatelessWidget {
  const PopoverSurface({super.key, required this.child, this.width});

  /// How wide it is. Null fits the content, between the web app's minimum and a sensible maximum.
  final double? width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KaneoRadius.lg),
      side: BorderSide(color: c.border),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: width ?? 128,
        maxWidth: width ?? 320,
        // Long lists scroll, as they do in the web app.
        maxHeight: 420,
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          shadows: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 15,
              spreadRadius: -3,
              offset: Offset(0, 10),
            ),
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 6,
              spreadRadius: -4,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: c.popover,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: width == null ? IntrinsicWidth(child: child) : child,
        ),
      ),
    );
  }
}

/// What a menu or picker holds: an optional [title] with an [action] beside it, an optional
/// [search] field, then [rows] that scroll. List tiles among them get the layout's metrics: the web
/// app's menu items on wide windows and the current app's sheet rows on narrow ones.
class PopoverBody extends StatelessWidget {
  const PopoverBody({super.key, this.title, this.action, this.search, required this.rows});

  final String? title;
  final Widget? action;
  final Widget? search;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final wide = context.isWide;
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: wide
                ? const EdgeInsets.fromLTRB(12, 8, 8, 2)
                : const EdgeInsets.fromLTRB(20, 0, 12, 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: wide
                          ? text.labelMedium?.copyWith(color: c.mutedForeground)
                          : text.headlineSmall,
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
          ),
        if (search != null)
          Padding(
            padding: wide
                ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
                : const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: search,
          ),
        Flexible(
          child: SingleChildScrollView(
            padding: wide ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: ListTileTheme(
              data: ListTileThemeData(
                visualDensity: VisualDensity.standard,
                mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.basic),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(wide ? KaneoRadius.sm : KaneoRadius.lg),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: wide ? 8 : 12),
                minTileHeight: wide ? 32 : 48,
                minVerticalPadding: wide ? 4 : 6,
                minLeadingWidth: 0,
                horizontalTitleGap: wide ? 8 : 12,
                titleTextStyle: wide ? text.bodyMedium : text.bodyLarge,
                subtitleTextStyle: text.bodySmall,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A row of a menu or picker.
class PopoverRow extends StatelessWidget {
  const PopoverRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.color,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// The title's color, for rows such as destructive ones.
  final Color? color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final row = HoverHighlight(
      enabled: enabled,
      child: ListTile(
        enabled: enabled,
        // The highlight above is the hover state. It works the same for every kind of row.
        hoverColor: Colors.transparent,
        leading: leading,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color ?? context.colors.foreground),
        ),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
    );
    // The web app's `data-disabled:opacity-64`.
    return enabled ? row : Opacity(opacity: 0.64, child: row);
  }
}

/// Paints the web app's `bg-accent` behind [child] while the mouse is over it.
class HoverHighlight extends StatefulWidget {
  const HoverHighlight({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = KaneoRadius.sm,
  });

  final Widget child;
  final bool enabled;
  final double borderRadius;

  @override
  State<HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<HoverHighlight> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _hovered && widget.enabled ? context.colors.accent : null,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        // Ink must paint above the hover background rather than on the popover's Material.
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Shows a larger piece of content, such as a form: a centered dialog on wide windows and a full
/// page on narrow ones. Resolves to what [builder]'s content pops with, or null if closed.
Future<T?> showPanel<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  double maxWidth = 512,
}) {
  if (!context.isWide) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(top: false, child: Builder(builder: builder)),
        ),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierColor: kaneoScrim,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(child: Builder(builder: builder)),
          ],
        ),
      ),
    ),
  );
}

/// The web app's backdrop behind a dialog: `bg-black/50`.
const Color kaneoScrim = Color(0x80000000);
