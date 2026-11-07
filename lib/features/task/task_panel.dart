import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/core.dart';
import 'task_view.dart';

/// Marks the panel, so that tests can look inside it and measure it.
const taskPanelKey = ValueKey('task-panel');

/// The web app's largest task panel.
const double _panelMaxWidth = 896;
const double _panelMinWidth = 320;

/// How much of the page should stay in view beside the panel.
const double _pageInView = 96;

/// How wide a panel is with [available] room next to the sidebar.
double taskPanelWidth(double available) => math.min(
  available,
  math.max(_panelMinWidth, math.min(_panelMaxWidth, available - _pageInView)),
);

/// A task sliding in from the right, over the page it was opened from. That page stays as it was,
/// so closing the panel returns to the same scroll position.
///
/// It stays a panel if the window turns narrow, and fills the window then, because the person may
/// be typing in it. [nested] is a panel opened from a panel, which doesn't darken the page again.
class TaskPanelRoute extends PopupRoute<void> {
  TaskPanelRoute({required this.taskId, required this.barrierLabel, this.nested = false});

  final String taskId;
  final bool nested;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => nested ? null : const Color(0x52000000);

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _TaskPanel(taskId: taskId, animation: animation);
}

class _TaskPanel extends StatelessWidget {
  const _TaskPanel({required this.taskId, required this.animation});

  static final _slide = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic));

  final String taskId;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: context.isWide ? taskPanelWidth(constraints.maxWidth) : constraints.maxWidth,
          child: SlideTransition(
            position: animation.drive(_slide),
            child: DecoratedBox(
              key: taskPanelKey,
              decoration: BoxDecoration(
                color: colors.background,
                border: Border(left: BorderSide(color: colors.border)),
                boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 24)],
              ),
              child: TaskView(taskId: taskId, onClose: () => Navigator.of(context).maybePop()),
            ),
          ),
        ),
      ),
    );
  }
}
