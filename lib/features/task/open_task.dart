import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';
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

/// Opens the new-task form. [status] preselects a column when creating from that column.
///
/// KAN-9 replaces the body: a centered dialog on wide windows and a full page on narrow ones.
void openNewTask(BuildContext context, {String? projectId, String? status}) {
  context.push(AppRoutes.newTask(projectId: projectId, status: status));
}
