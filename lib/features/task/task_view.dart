import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import 'task_activity_view.dart';
import 'task_description.dart';
import 'task_properties.dart';
import 'task_relations_view.dart';
import 'task_title.dart';

/// From this width a task shows its properties in a column of their own, as the web app's panel
/// does. Below it, which includes every phone, there is one column with the properties near the top.
const double taskTwoColumnsMinWidth = 640;

const double _propertiesWidth = 272;

/// Everything about a task, with its bar. A panel and a full page both show this.
///
/// [onClose] adds a close button, for a panel. A page gets its way back from the bar.
class TaskView extends ConsumerWidget {
  const TaskView({super.key, required this.taskId, this.onClose});

  final String taskId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = taskQuery(taskId);
    final value = ref.watch(query);
    return Scaffold(
      appBar: _TaskBar(task: value.value, onClose: onClose),
      body: SafeArea(
        top: false,
        child: AsyncBody(
          value: value,
          onRetry: () => ref.read(query.notifier).refresh(),
          builder: (context, task) => _TaskBody(key: ValueKey(task.id), task: task),
        ),
      ),
    );
  }
}

class _TaskBar extends ConsumerWidget implements PreferredSizeWidget {
  const _TaskBar({required this.task, required this.onClose});

  final Task? task;
  final VoidCallback? onClose;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final workspaceId = task?.workspaceId;
    final projects = workspaceId == null ? null : ref.watch(projectsQuery(workspaceId)).value;
    final project = projects?.where((p) => p.id == task?.projectId).firstOrNull;
    final ticket = ticketId(project?.slug, task?.number);
    final style = Theme.of(context).textTheme.bodySmall!;
    return AppBar(
      automaticallyImplyLeading: onClose == null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              project?.name ?? context.t('app:task.title'),
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(fontSize: 13, color: colors.mutedForeground),
            ),
          ),
          if (ticket.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(LucideIcons.chevronRight, size: 12, color: colors.mutedForeground),
            ),
            Text(
              ticket,
              style: style.copyWith(
                fontSize: 12,
                fontFamily: KaneoFonts.mono,
                color: colors.foreground,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (onClose != null)
          IconButton(
            tooltip: context.t('mobile:common.close'),
            icon: const Icon(LucideIcons.x, size: 18),
            onPressed: onClose,
          ),
      ],
    );
  }
}

/// The two arrangements hold the same widgets. The keys carry what is being typed from one to the
/// other when the width crosses over, and the text boxes never scroll out of existence.
class _TaskBody extends StatefulWidget {
  const _TaskBody({super.key, required this.task});

  final Task task;

  @override
  State<_TaskBody> createState() => _TaskBodyState();
}

class _TaskBodyState extends State<_TaskBody> {
  final _title = GlobalKey();
  final _description = GlobalKey();
  final _relations = GlobalKey();
  final _activity = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final title = TaskTitle(key: _title, task: task);
    final description = TaskDescription(key: _description, task: task);
    final properties = TaskProperties(task: task);
    final parent = TaskParentLink(task: task);
    final relations = TaskRelationSections(key: _relations, task: task);
    final activity = TaskActivitySection(key: _activity, task: task);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < taskTwoColumnsMinWidth) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                parent,
                title,
                const SizedBox(height: 12),
                properties,
                const SizedBox(height: 16),
                description,
                const SizedBox(height: 24),
                relations,
                const SizedBox(height: 24),
                activity,
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
                child: ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      parent,
                      title,
                      const SizedBox(height: 16),
                      description,
                      const SizedBox(height: 28),
                      relations,
                      const SizedBox(height: 28),
                      activity,
                    ],
                  ),
                ),
              ),
            ),
            VerticalDivider(width: 1, color: context.colors.border),
            SizedBox(
              width: _propertiesWidth,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 24),
                child: properties,
              ),
            ),
          ],
        );
      },
    );
  }
}
