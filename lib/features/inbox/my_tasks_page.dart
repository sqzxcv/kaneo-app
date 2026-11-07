import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../shell/workspace_gate.dart';
import '../task/open_task.dart';

/// Placeholder until KAN-38.
class MyTasksPage extends ConsumerWidget {
  const MyTasksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlaceholderPage(
      title: context.t('mobile:myTasks.title'),
      child: ContentWidth(
        child: WorkspaceGate(
          builder: (context, workspace) {
            final query = assignedTasksQuery(workspace.id);
            return AsyncBody(
              value: ref.watch(query),
              onRetry: () => ref.read(query.notifier).refresh(),
              builder: (context, assigned) => ListView(
                children: [
                  ListTile(
                    title: Text(
                      context.t('mobile:myTasks.assigned', {'count': assigned.tasks.length}),
                    ),
                  ),
                  for (final task in assigned.tasks)
                    ListTile(
                      title: Text(task.title),
                      subtitle: Text(task.projectName),
                      onTap: () => openTask(context, task.id, projectId: task.projectId),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
