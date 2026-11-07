import 'package:flutter/material.dart';

import 'task_view.dart';

/// A task as a page of its own: on narrow windows, and on any window from a link or a notification.
class TaskPage extends StatelessWidget {
  const TaskPage({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context) => TaskView(taskId: taskId);
}
