import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
import 'new_task_page.dart';
import 'task_panel.dart';

/// Opens a task from a list or a board: a panel over the page on wide windows, so that the page
/// stays in view, and a full page on narrow ones. From inside a panel, it opens over that panel.
///
/// With no page around [context], as for a desktop notification, it opens a full page too. There is
/// nothing to keep in view then.
///
/// [projectId] isn't needed: the task says which project it belongs to.
void openTask(BuildContext context, String taskId, {String? projectId}) {
  final page = ModalRoute.of(context);
  if (!context.isWide || page == null) {
    openTaskPage(context, taskId);
    return;
  }
  Navigator.of(context).push(
    TaskPanelRoute(
      taskId: taskId,
      barrierLabel: context.t('mobile:common.close'),
      nested: page is TaskPanelRoute,
    ),
  );
}

/// Opens a task as a full page on any window. For links, and for notifications in the inbox: the
/// person is going to the task, not looking something up beside the page they are on.
void openTaskPage(BuildContext context, String taskId) {
  context.push(AppRoutes.task(taskId));
}

/// Leaves a task that has just been deleted, for the board of the project it was in, wherever the
/// task was opened from. [context] is inside the task.
///
/// Panels aren't known to the router, so they have to be closed first. A board that is right below
/// the task is come back to rather than opened again, and is as it was left.
void leaveDeletedTask(BuildContext context, String projectId) {
  final router = GoRouter.of(context);
  final board = AppRoutes.board(projectId);
  Navigator.of(context).popUntil((route) => route is! TaskPanelRoute);
  if (router.state.uri.path != board && router.canPop()) router.pop();
  if (router.state.uri.path != board) router.go(board);
}

/// Opens the new-task form: a dialog over the page on wide windows, so that the page stays in view,
/// and a full page on narrow ones. [status] preselects a column when creating from that column.
///
/// A narrow one goes through the router so that a phone leaves the board's landscape while typing.
void openNewTask(BuildContext context, {String? projectId, String? status}) {
  if (!context.isWide || ModalRoute.of(context) == null) {
    context.push(AppRoutes.newTask(projectId: projectId, status: status));
    return;
  }
  showPanel<void>(
    context,
    title: context.t('mobile:board.newTask'),
    maxWidth: newTaskFormWidth,
    builder: (context) => NewTaskForm(projectId: projectId, status: status),
  );
}
