import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import 'task_description.dart';

/// Placeholder until KAN-34.
class TaskPage extends ConsumerWidget {
  const TaskPage({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = taskQuery(taskId);
    return PlaceholderPage(
      title: context.t('app:task.title'),
      child: AsyncBody(
        value: ref.watch(query),
        onRetry: () => ref.read(query.notifier).refresh(),
        builder: (context, task) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(task.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TaskDescription(task: task),
          ],
        ),
      ),
    );
  }
}
