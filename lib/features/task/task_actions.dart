import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/core.dart';
import 'open_task.dart';
import 'task_edits.dart';
import 'task_relations.dart';

/// Where the web app shows [task], on the address of the server. Null while that can't be known.
String? taskWebLink(String? serverUrl, Task task) {
  final workspaceId = task.workspaceId;
  if (serverUrl == null || workspaceId == null) return null;
  return resolveUrl(
    serverUrl,
    '/dashboard/workspace/$workspaceId/project/${task.projectId}/task/${task.id}',
  );
}

/// What goes out when a task is shared. [ticket] is empty until the project has loaded.
String taskShareText(String ticket, String title, String link) =>
    '${ticket.isEmpty ? title : '$ticket $title'}\n$link';

/// The projects [task] can move to.
List<Project> taskMoveDestinations(List<Project> projects, Task task) => [
  for (final project in projects)
    if (project.id != task.projectId && project.archivedAt == null) project,
];

enum TaskMenuItem { share, duplicate, move, delete }

/// What the task's menu offers. Sharing only takes being able to see the task.
///
/// Permissions that haven't loaded count as allowed, because the server has the last word.
List<TaskMenuItem> taskMenuItems({
  required WorkspaceCapabilities? can,
  required bool hasLink,
  required bool isSubtask,
  required bool hasDestination,
}) => [
  if (hasLink) TaskMenuItem.share,
  // A copy of a subtask is a subtask too, and linking it takes permission to change tasks.
  if (can?.createTasks != false && (!isSubtask || can?.updateTasks != false))
    TaskMenuItem.duplicate,
  if (can?.updateTasks != false && hasDestination) TaskMenuItem.move,
  if (can?.deleteTasks != false) TaskMenuItem.delete,
];

/// The buttons on a task's bar: copying its link, and a menu with what else can be done to it.
class TaskActions extends ConsumerStatefulWidget {
  const TaskActions({super.key, required this.task, required this.ticket});

  final Task task;

  /// The task's ticket id, or nothing until its project has loaded.
  final String ticket;

  @override
  ConsumerState<TaskActions> createState() => _TaskActionsState();
}

class _TaskActionsState extends ConsumerState<TaskActions> {
  /// A copy, a move or a deletion is under way, and asking again would do it twice.
  bool _busy = false;

  Future<T> _whileBusy<T>(Future<T> Function() change) async {
    setState(() => _busy = true);
    try {
      return await change();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMenu(BuildContext anchor, List<TaskMenuItem> items, String? link) async {
    final chosen = await showActionMenu<TaskMenuItem>(
      anchor,
      items: [for (final item in items) _menuAction(anchor, item)],
    );
    if (chosen == null || !anchor.mounted) return;
    switch (chosen) {
      case TaskMenuItem.share:
        await _share(anchor, link!);
      case TaskMenuItem.duplicate:
        await _duplicate(anchor);
      case TaskMenuItem.move:
        await _move(anchor);
      case TaskMenuItem.delete:
        await _delete(anchor);
    }
  }

  MenuAction<TaskMenuItem> _menuAction(BuildContext context, TaskMenuItem item) => switch (item) {
    TaskMenuItem.share => MenuAction(
      value: item,
      label: context.t('mobile:taskDetail.menu.share'),
      icon: LucideIcons.share2,
    ),
    TaskMenuItem.duplicate => MenuAction(
      value: item,
      label: context.t('mobile:taskDetail.menu.duplicate'),
      icon: LucideIcons.copy,
    ),
    TaskMenuItem.move => MenuAction(
      value: item,
      label: context.t('mobile:taskDetail.menu.move'),
      icon: LucideIcons.folderInput,
    ),
    TaskMenuItem.delete => MenuAction(
      value: item,
      label: context.t('mobile:taskDetail.menu.delete'),
      icon: LucideIcons.trash2,
      destructive: true,
    ),
  };

  Future<void> _copyLink(String link) => runAction(
    context,
    () => Clipboard.setData(ClipboardData(text: link)),
    success: context.t('mobile:taskDetail.screen.linkCopied'),
  );

  Future<void> _share(BuildContext anchor, String link) async {
    // An iPad and a Mac point the share sheet at this. A phone ignores it.
    final button = anchor.findRenderObject();
    final origin = button is RenderBox && button.hasSize
        ? button.localToGlobal(Offset.zero) & button.size
        : null;
    final task = widget.task;
    await runAction(
      anchor,
      () => SharePlus.instance.share(
        ShareParams(
          text: taskShareText(widget.ticket, task.title, link),
          sharePositionOrigin: origin,
        ),
      ),
    );
  }

  Future<void> _duplicate(BuildContext anchor) async {
    final edits = ref.read(taskEditsProvider(widget.task.id));
    final copy = await _whileBusy(edits.duplicate);
    if (copy == null || !anchor.mounted) return;
    showToast(anchor, anchor.t('mobile:taskDetail.menu.duplicated'), kind: ToastKind.success);
    openTask(anchor, copy.id);
  }

  Future<void> _move(BuildContext anchor) async {
    final task = widget.task;
    final workspaceId = task.workspaceId!;
    final api = ref.read(kaneoApiProvider);
    final edits = ref.read(taskEditsProvider(task.id));
    final projects =
        ref.read(projectsQuery(workspaceId)).value ??
        await runAction(anchor, () => api.projects(workspaceId));
    if (projects == null || !anchor.mounted) return;
    final destinations = taskMoveDestinations(projects, task);
    if (destinations.isEmpty) {
      showToast(anchor, anchor.t('app:shell.noProjects'));
      return;
    }
    final picked = await pickOption(
      anchor,
      title: anchor.t('mobile:taskDetail.menu.moveTitle'),
      options: [
        for (final project in destinations)
          PickerOption(
            value: project.id,
            label: project.name,
            subtitle: project.slug.toUpperCase(),
          ),
      ],
    );
    if (picked == null || !anchor.mounted) return;
    final moved = await _whileBusy(() => edits.moveTo(picked.value));
    if (moved && anchor.mounted) {
      showToast(anchor, anchor.t('mobile:taskDetail.menu.moved'), kind: ToastKind.success);
    }
  }

  Future<void> _delete(BuildContext anchor) async {
    final task = widget.task;
    final edits = ref.read(taskEditsProvider(task.id));
    final i18n = I18nScope.of(anchor);
    final confirmed = await showConfirm(
      anchor,
      title: i18n.t('mobile:taskDetail.menu.deleteTitle'),
      message: i18n.t('mobile:taskDetail.menu.deleteMessage', {'title': task.title}),
      confirmLabel: i18n.t('mobile:common.delete'),
      destructive: true,
    );
    if (!confirmed || !anchor.mounted) return;
    final deleted = await _whileBusy(edits.delete);
    if (!deleted) return;
    showGlobalToast(i18n.t('mobile:taskDetail.menu.deleted'), kind: ToastKind.success);
    // If the person has already left the task, they aren't taken anywhere.
    if (anchor.mounted) leaveDeletedTask(anchor, task.projectId);
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final workspaceId = task.workspaceId;
    final can = workspaceId == null ? null : ref.watch(capabilitiesQuery(workspaceId)).value;
    final projects = workspaceId == null ? null : ref.watch(projectsQuery(workspaceId)).value;
    final relations = ref.watch(taskRelationsQuery(task.id)).value;
    // Lives as long as the buttons, so that a change started from them can be queued.
    ref.watch(taskEditsProvider(task.id));
    final link = taskWebLink(ref.watch(sessionProvider.select((s) => s?.serverUrl)), task);
    final items = taskMenuItems(
      can: can,
      hasLink: link != null,
      isSubtask: relations != null && parentTaskOf(task.id, relations) != null,
      hasDestination:
          workspaceId != null &&
          (projects == null || taskMoveDestinations(projects, task).isNotEmpty),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (link != null)
          IconButton(
            key: const ValueKey('task-copy-link'),
            tooltip: context.t('mobile:taskDetail.screen.copyLink'),
            icon: const Icon(LucideIcons.link2, size: 18),
            onPressed: () => _copyLink(link),
          ),
        if (items.isNotEmpty)
          Builder(
            builder: (anchor) => IconButton(
              key: const ValueKey('task-more'),
              tooltip: context.t('mobile:taskDetail.screen.more'),
              icon: const Icon(LucideIcons.ellipsis, size: 18),
              onPressed: _busy ? null : () => _openMenu(anchor, items, link),
            ),
          ),
      ],
    );
  }
}
