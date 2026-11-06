import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';

/// Opens a task. Every list, board and notification goes through here.
///
/// KAN-34 replaces the body: a side panel on wide windows and a full page on narrow ones. Callers
/// do not change. Pass [projectId] when it is on hand, to save the panel a lookup.
void openTask(BuildContext context, String taskId, {String? projectId}) {
  context.push(AppRoutes.task(taskId));
}

/// Opens the new-task form. [status] preselects a column when creating from that column.
///
/// KAN-9 replaces the body: a centered dialog on wide windows and a full page on narrow ones.
void openNewTask(BuildContext context, {String? projectId, String? status}) {
  context.push(AppRoutes.newTask(projectId: projectId, status: status));
}
