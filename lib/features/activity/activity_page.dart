import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../shell/workspace_gate.dart';
import '../task/open_task.dart';

/// Placeholder until KAN-39.
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlaceholderPage(
      title: context.t('mobile:nav.activity'),
      child: WorkspaceGate(
        builder: (context, workspace) {
          final query = workspaceActivityQuery(workspace.id);
          return AsyncBody(
            value: ref.watch(query),
            onRetry: () => ref.read(query.notifier).refresh(),
            isEmpty: (items) => items.isEmpty,
            empty: StatusMessage(title: context.t('mobile:activity.empty')),
            builder: (context, items) => ListView(
              children: [
                for (final item in items)
                  ListTile(
                    title: Text(item.taskTitle),
                    subtitle: Text('${item.userName ?? ''} · ${item.type}'),
                    onTap: () => openTask(context, item.taskId, projectId: item.projectId),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
