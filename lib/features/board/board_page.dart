import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import '../task/open_task.dart';

/// Placeholder until KAN-27. Lists the columns and tasks of the board.
class BoardPage extends ConsumerWidget {
  const BoardPage({super.key, required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = boardQuery(projectId);
    return PlaceholderPage(
      title: context.t('mobile:board.board'),
      actions: [
        IconButton(
          tooltip: context.t('mobile:board.newTask'),
          icon: const Icon(LucideIcons.plus),
          onPressed: () => openNewTask(context, projectId: projectId),
        ),
      ],
      child: AsyncBody(
        value: ref.watch(query),
        onRetry: () => ref.read(query.notifier).refresh(),
        builder: (context, board) => ListView(
          children: [
            ListTile(
              title: Text(board.name),
              subtitle: Text(context.t('app:board.columnCount', {'count': board.columns.length})),
            ),
            for (final column in board.columns)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    title: Text(column.name, style: Theme.of(context).textTheme.titleSmall),
                    trailing: Text(
                      context.t('app:board.taskCount', {'count': column.tasks?.length ?? 0}),
                    ),
                  ),
                  for (final task in column.tasks ?? const <BoardTask>[])
                    ListTile(
                      dense: true,
                      title: Text(task.title),
                      subtitle: Text(ticketId(board.slug, task.number)),
                      onTap: () => openTask(context, task.id, projectId: task.projectId),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
