import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import '../board/board_icons.dart';
import 'task_edits.dart';

/// A task's properties, one to a row. Each value opens its picker next to itself, and is plain text
/// for someone who may not change it.
///
/// Permissions that haven't loaded count as allowed, because the server has the last word.
class TaskProperties extends ConsumerWidget {
  const TaskProperties({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = task.workspaceId;
    final can = workspaceId == null ? null : ref.watch(capabilitiesQuery(workspaceId)).value;
    final canEdit = can?.updateTasks != false;
    final canAssign = workspaceId != null && can?.assignTasks != false;
    final canLabel = workspaceId != null && can?.updateLabels != false;
    final edits = ref.watch(taskEditsProvider(task.id));
    final columns = ref.watch(columnsQuery(task.projectId)).value ?? const <ProjectColumn>[];
    final labels = ref.watch(taskLabelsQuery(task.id)).value ?? const <Label>[];
    // Loaded ahead, so that these pickers open at once.
    if (canAssign) ref.watch(_members(workspaceId));
    if (canLabel) ref.watch(workspaceLabelsQuery(workspaceId));

    final colors = context.colors;
    final i18n = I18nScope.of(context);
    final column = columns.where((c) => c.slug == task.status).firstOrNull;
    final dueColor = column?.isFinal != true && isOverdue(task.dueDate) ? colors.dueOverdue : null;

    Widget date({
      required Key key,
      required String label,
      required IconData icon,
      required String? value,
      required void Function(String? date) onChanged,
      Color? color,
    }) => PropertyRow(
      label: label,
      child: PropertyValue(
        key: key,
        onPressed: canEdit
            ? (anchor) async {
                final current = parseDay(value);
                final picked = await pickDate(anchor, title: label, current: current);
                if (picked == null || picked.value == current) return;
                onChanged(picked.value == null ? null : toApiDate(picked.value!));
              }
            : null,
        child: PropertyText(
          icon: Icon(icon, size: 14, color: color ?? colors.mutedForeground),
          text: value == null ? context.t('tasks:properties.noDate') : formatDate(i18n, value),
          color: value == null ? colors.mutedForeground : color,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PropertyRow(
          label: context.t('mobile:taskFields.status'),
          child: PropertyValue(
            key: const ValueKey('task-status'),
            onPressed: canEdit ? (anchor) => _pickStatus(anchor, ref, edits) : null,
            child: PropertyText(
              icon: Icon(taskStatusIcon(task.status, column), size: 14),
              text: taskStatusName(context, task.status, columns),
            ),
          ),
        ),
        PropertyRow(
          label: context.t('mobile:taskFields.priority'),
          child: PropertyValue(
            key: const ValueKey('task-priority'),
            onPressed: canEdit
                ? (anchor) async {
                    final picked = await pickPriority(anchor, current: task.priority);
                    if (picked != null && picked != task.priority) edits.setPriority(picked);
                  }
                : null,
            child: PropertyText(
              icon: Icon(
                LucideIcons.signal,
                size: 14,
                color: priorityColor(context, task.priority),
              ),
              text: priorityLabel(context, task.priority),
            ),
          ),
        ),
        PropertyRow(
          label: context.t('mobile:taskFields.assignee'),
          child: PropertyValue(
            key: const ValueKey('task-assignee'),
            onPressed: canAssign ? (anchor) => _pickAssignee(anchor, ref, edits) : null,
            child: PropertyText(
              icon: CircleAvatar(
                radius: 9,
                backgroundColor: colors.avatar,
                foregroundColor: colors.avatarForeground,
                child: task.userId == null
                    ? const Icon(LucideIcons.user, size: 10)
                    : Text(initials(task.assigneeName), style: const TextStyle(fontSize: 8)),
              ),
              text: task.userId == null
                  ? context.t('mobile:taskFields.unassigned')
                  : task.assigneeName ?? '',
              color: task.userId == null ? colors.mutedForeground : null,
            ),
          ),
        ),
        PropertyRow(
          label: context.t('mobile:taskFields.labels'),
          child: PropertyValue(
            key: const ValueKey('task-labels'),
            onPressed: canLabel ? (anchor) => _pickLabels(anchor, ref, edits, can) : null,
            child: labels.isEmpty
                ? PropertyText(
                    icon: Icon(LucideIcons.tag, size: 14, color: colors.mutedForeground),
                    text: context.t(
                      canLabel ? 'tasks:properties.addLabels' : 'mobile:taskFields.none',
                    ),
                    color: colors.mutedForeground,
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [for (final label in labels) PropertyLabel(label: label)],
                  ),
          ),
        ),
        date(
          key: const ValueKey('task-start-date'),
          label: context.t('mobile:taskFields.startDate'),
          icon: LucideIcons.calendarDays,
          value: task.startDate,
          onChanged: edits.setStartDate,
        ),
        date(
          key: const ValueKey('task-due-date'),
          label: context.t('mobile:taskFields.dueDate'),
          icon: LucideIcons.calendar,
          value: task.dueDate,
          color: dueColor,
          onChanged: edits.setDueDate,
        ),
      ],
    );
  }

  /// Pass the project too, because that is who can be assigned here.
  AsyncNotifierProvider<CachedQuery<List<WorkspaceMember>>, List<WorkspaceMember>> _members(
    String workspaceId,
  ) => membersQuery((workspaceId: workspaceId, projectId: task.projectId));

  Future<void> _pickStatus(BuildContext anchor, WidgetRef ref, TaskEdits edits) async {
    final api = ref.read(kaneoApiProvider);
    final planned = anchor.t('mobile:taskFields.planned');
    final archived = anchor.t('mobile:taskFields.archived');
    final columns =
        ref.read(columnsQuery(task.projectId)).value ??
        await runAction(anchor, () => api.columns(task.projectId));
    if (columns == null || !anchor.mounted) return;
    ProjectColumn extra(String slug, String name) =>
        ProjectColumn(id: slug, projectId: task.projectId, name: name, slug: slug);
    final picked = await pickStatus(
      anchor,
      current: task.status,
      columns: [
        if (!columns.any((c) => c.slug == statusPlanned)) extra(statusPlanned, planned),
        ...columns,
        if (!columns.any((c) => c.slug == statusArchived)) extra(statusArchived, archived),
      ],
    );
    if (picked != null && picked != task.status) edits.setStatus(picked);
  }

  Future<void> _pickAssignee(BuildContext anchor, WidgetRef ref, TaskEdits edits) async {
    final workspaceId = task.workspaceId!;
    final api = ref.read(kaneoApiProvider);
    final members =
        ref.read(_members(workspaceId)).value ??
        await runAction(anchor, () => api.workspaceMembers(workspaceId, projectId: task.projectId));
    if (members == null || !anchor.mounted) return;
    final picked = await pickAssignee(anchor, members: members, current: task.userId);
    if (picked == null || picked.value == task.userId) return;
    edits.setAssignee(members.where((m) => m.id == picked.value).firstOrNull);
  }

  Future<void> _pickLabels(
    BuildContext anchor,
    WidgetRef ref,
    TaskEdits edits,
    WorkspaceCapabilities? can,
  ) async {
    final workspaceId = task.workspaceId!;
    final api = ref.read(kaneoApiProvider);
    final loaded = await runAction(anchor, () async {
      final results = await Future.wait([
        _orFetch(ref.read(workspaceLabelsQuery(workspaceId)).value, () {
          return api.workspaceLabels(workspaceId);
        }),
        _orFetch(ref.read(taskLabelsQuery(task.id)).value, () => api.taskLabels(task.id)),
      ]);
      return (workspace: results[0], attached: results[1]);
    });
    if (loaded == null || !anchor.mounted) return;
    final options = taskLabelOptions(loaded.workspace, task.id);
    final selected = await pickLabels(
      anchor,
      labels: options,
      selectedIds: selectedLabelIds(loaded.attached, options),
      onCreate: can?.createLabels == false
          ? null
          : (name, color) => api.createLabel(name: name, color: color, workspaceId: workspaceId),
    );
    if (selected == null) return;
    final changes = labelChanges(attached: loaded.attached, options: options, selected: selected);
    if (!changes.isEmpty) edits.setLabels(changes);
  }

  Future<T> _orFetch<T>(T? cached, Future<T> Function() fetch) async => cached ?? await fetch();
}

/// The icon for [status], whose column is [column] if it has one.
IconData taskStatusIcon(String status, ProjectColumn? column) => boardColumnIcon(
  BoardColumn(id: status, slug: status, name: status, icon: column?.icon, isFinal: column?.isFinal),
);

Color priorityColor(BuildContext context, String? priority) {
  final colors = context.colors;
  return switch (priority) {
    'urgent' => colors.priorityUrgent,
    'high' => colors.priorityHigh,
    'medium' => colors.priorityMedium,
    'low' => colors.priorityLow,
    _ => colors.mutedForeground,
  };
}

String taskStatusName(BuildContext context, String status, List<ProjectColumn> columns) {
  final column = columns.where((c) => c.slug == status).firstOrNull;
  if (column != null) return column.name;
  return switch (status) {
    statusPlanned => context.t('mobile:taskFields.planned'),
    statusArchived => context.t('mobile:taskFields.archived'),
    _ => status,
  };
}

class PropertyRow extends StatelessWidget {
  const PropertyRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            height: 32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall!
                    .copyWith(color: context.colors.mutedForeground),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The pressable part of a row. It hands the press its own context, for the picker to open beside,
/// and ignores another press until that has finished.
///
/// With [chip] it stands alone, as the web app's new-task dialog has it: as wide as its content, in
/// a border.
class PropertyValue extends StatefulWidget {
  const PropertyValue({super.key, required this.onPressed, required this.child, this.chip = false});

  final Future<void> Function(BuildContext anchor)? onPressed;
  final Widget child;
  final bool chip;

  @override
  State<PropertyValue> createState() => PropertyValueState();
}

class PropertyValueState extends State<PropertyValue> {
  bool _open = false;

  Future<void> _press() async {
    if (_open) return;
    _open = true;
    try {
      await widget.onPressed!(context);
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(KaneoRadius.md);
    final button = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: radius,
        hoverColor: context.colors.accent,
        onTap: widget.onPressed == null ? null : _press,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.chip ? 10 : 8, vertical: 7),
          child: widget.chip
              ? widget.child
              : Align(alignment: Alignment.centerLeft, child: widget.child),
        ),
      ),
    );
    if (!widget.chip) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: context.colors.border),
      ),
      child: button,
    );
  }
}

class PropertyText extends StatelessWidget {
  const PropertyText({super.key, required this.icon, required this.text, this.color});

  final Widget icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: _valueStyle(context).copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class PropertyLabel extends StatelessWidget {
  const PropertyLabel({super.key, required this.label});

  final Label label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 4, backgroundColor: labelColor(label.color)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label.name, overflow: TextOverflow.ellipsis, style: _valueStyle(context)),
        ),
      ],
    );
  }
}

TextStyle _valueStyle(BuildContext context) => TextStyle(
  fontSize: 13,
  height: 18 / 13,
  fontWeight: FontWeight.w500,
  color: context.colors.foreground,
);
