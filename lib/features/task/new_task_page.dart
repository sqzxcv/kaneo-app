import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import '../markdown/markdown_field.dart';
import 'new_task.dart';
import 'task_edits.dart';
import 'task_properties.dart';
import 'task_title.dart';

/// The web app's `max-w-2xl`, for its new-task dialog.
const double newTaskFormWidth = 672;

/// The new-task form as a page of its own, for a narrow window and for a link.
class NewTaskPage extends StatelessWidget {
  const NewTaskPage({super.key, this.projectId, this.status});

  final String? projectId;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('mobile:board.newTask'))),
      body: SafeArea(
        top: false,
        child: ContentWidth(
          maxWidth: newTaskFormWidth,
          // All the height there is, for the form to keep its buttons at the bottom.
          child: SizedBox(
            height: double.infinity,
            child: NewTaskForm(projectId: projectId, status: status),
          ),
        ),
      ),
    );
  }
}

/// A new task's fields and the buttons to create it. Closes the route it is on once created.
///
/// Custom fields aren't asked for. The server fills in the required ones with their defaults, and a
/// required field always has one.
///
/// The text boxes stay in place in both layouts, so what was typed survives the window crossing over
/// between them. Only the fields below them change shape.
class NewTaskForm extends ConsumerStatefulWidget {
  const NewTaskForm({super.key, this.projectId, this.status});

  final String? projectId;

  /// The column to start in, when creating from that column.
  final String? status;

  @override
  ConsumerState<NewTaskForm> createState() => _NewTaskFormState();
}

class _NewTaskFormState extends ConsumerState<NewTaskForm> {
  final _title = TextEditingController();
  final _titleFocus = FocusNode();
  final _description = TextEditingController();
  final _descriptionFocus = FocusNode();

  late String? _projectId = widget.projectId;
  late String? _status = widget.status;
  String _priority = priorities.first;
  String? _assigneeId;
  String? _startDate;
  String? _dueDate;
  Set<String> _labelIds = const {};

  /// Labels made while picking, which the workspace's list may not have yet.
  final _createdLabels = <Label>[];

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _titleFocus.dispose();
    _description.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  /// The labels on offer. A task that doesn't exist yet has no copies of its own.
  List<Label> _labelOptions(List<Label>? workspaceLabels) =>
      taskLabelOptions([...?workspaceLabels, ..._createdLabels], '');

  Future<void> _submit({
    required String workspaceId,
    required String projectId,
    required String status,
    required WorkspaceMember? assignee,
    required List<Label> labels,
  }) async {
    final title = singleLineTitle(_title.text);
    if (_busy || title.isEmpty) return;
    // Read before the gap: the form may be gone by the time this finishes.
    final i18n = I18nScope.of(context);
    final tasks = ref.read(newTasksProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final allLabels = await tasks.create(
        workspaceId: workspaceId,
        projectId: projectId,
        labels: labels,
        assignee: assignee,
        body: CreateTaskBody(
          title: title,
          description: _description.text,
          startDate: _startDate,
          dueDate: _dueDate,
          priority: _priority,
          status: status,
          userId: assignee?.id,
        ),
      );
      if (mounted) Navigator.of(context).pop();
      if (allLabels) {
        showGlobalToast(i18n.t('common:modals.createTask.successCreated'), kind: ToastKind.success);
      } else {
        showGlobalToast(i18n.t('mobile:taskNew.labelsFailed'), kind: ToastKind.error);
      }
    } catch (error) {
      if (mounted) {
        // In the form rather than as a toast, which a dialog would cover. Everything typed stays.
        setState(() {
          _busy = false;
          _error = userMessage(context, error);
        });
      } else {
        showGlobalToast(i18n.t('common:modals.createTask.createError'), kind: ToastKind.error);
      }
    }
  }

  Future<void> _pickProject(BuildContext anchor, List<Project> projects) async {
    final picked = await pickOption<String>(
      anchor,
      title: anchor.t('mobile:taskNew.project'),
      selected: _projectId,
      options: [
        for (final project in projects)
          PickerOption(
            value: project.id,
            label: project.name,
            subtitle: project.slug.toUpperCase(),
            leading: Icon(projectIcon(project.icon), size: 16),
          ),
      ],
    );
    if (picked == null || picked.value == _projectId || !mounted) return;
    // A status belongs to a project. The assignee stays if the next project has them too.
    setState(() {
      _projectId = picked.value;
      _status = null;
    });
  }

  Future<void> _pickStatus(
    BuildContext anchor,
    String projectId,
    List<ProjectColumn> columns,
    String current,
  ) async {
    final picked = await pickStatus(
      anchor,
      current: current,
      columns: newTaskStatuses(
        columns,
        projectId: projectId,
        plannedName: anchor.t('mobile:taskFields.planned'),
      ),
    );
    if (picked != null && mounted) setState(() => _status = picked);
  }

  Future<void> _pickPriority(BuildContext anchor) async {
    final picked = await pickPriority(anchor, current: _priority);
    if (picked != null && mounted) setState(() => _priority = picked);
  }

  Future<void> _pickAssignee(
    BuildContext anchor,
    String workspaceId,
    List<WorkspaceMember>? loaded,
  ) async {
    final api = ref.read(kaneoApiProvider);
    final projectId = _projectId;
    final members =
        loaded ??
        await runAction(anchor, () => api.workspaceMembers(workspaceId, projectId: projectId));
    if (members == null || !anchor.mounted) return;
    final picked = await pickAssignee(anchor, members: members, current: _assigneeId);
    if (picked != null && mounted) setState(() => _assigneeId = picked.value);
  }

  Future<void> _pickLabels(
    BuildContext anchor,
    String workspaceId,
    List<Label>? loaded,
    bool canCreate,
  ) async {
    final api = ref.read(kaneoApiProvider);
    final labels = workspaceLabelsQuery(workspaceId);
    final workspaceLabels =
        loaded ?? await runAction(anchor, () => api.workspaceLabels(workspaceId));
    if (workspaceLabels == null || !anchor.mounted) return;
    final selected = await pickLabels(
      anchor,
      labels: _labelOptions(workspaceLabels),
      selectedIds: _labelIds,
      onCreate: canCreate
          ? (name, color) async {
              final label = await api.createLabel(
                name: name,
                color: color,
                workspaceId: workspaceId,
              );
              _createdLabels.add(label);
              if (mounted) await ref.read(labels.notifier).refresh();
              return label;
            }
          : null,
    );
    if (selected != null && mounted) setState(() => _labelIds = selected);
  }

  Future<void> _pickDay(
    BuildContext anchor,
    String title,
    String? value,
    void Function(String? date) onChanged,
  ) async {
    final current = parseDay(value);
    final picked = await pickDate(anchor, title: title, current: current);
    if (picked == null || picked.value == current || !mounted) return;
    setState(() => onChanged(picked.value == null ? null : toApiDate(picked.value!)));
  }

  /// A chip on wide windows, as in the web app's dialog, where the name of the field stands in for
  /// the value until there is one. A row with its name beside it on narrow windows.
  Widget _field({
    required Key key,
    required String label,
    required Widget icon,
    required String? value,
    required Future<void> Function(BuildContext anchor)? onPressed,
    String? prompt,
    String? empty,
    Widget? content,
  }) {
    final wide = context.isWide;
    final button = PropertyValue(
      key: key,
      chip: wide,
      onPressed: _busy ? null : onPressed,
      child:
          content ??
          PropertyText(
            icon: icon,
            text: value ?? (wide ? prompt ?? label : empty ?? context.t('mobile:taskFields.none')),
            color: value == null ? context.colors.mutedForeground : null,
          ),
    );
    return wide ? button : PropertyRow(label: label, child: button);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final i18n = I18nScope.of(context);
    final wide = context.isWide;
    // Held here so that it is there when the button is pressed.
    ref.watch(newTasksProvider);

    final workspace = ref.watch(currentWorkspaceProvider);
    final workspaceId = workspace.value?.id;
    final projectsValue = workspaceId == null ? null : ref.watch(projectsQuery(workspaceId));
    final projects = projectsValue?.value;
    final project = projects?.where((p) => p.id == _projectId).firstOrNull;
    final columnsValue = project == null ? null : ref.watch(columnsQuery(project.id));
    final columns = columnsValue?.value;
    final status = columns == null ? null : initialTaskStatus(columns, _status);
    final column = columns?.where((c) => c.slug == status).firstOrNull;

    // Permissions that haven't loaded count as allowed, because the server has the last word.
    final can = workspaceId == null ? null : ref.watch(capabilitiesQuery(workspaceId)).value;
    final canCreate = can?.createTasks != false;
    final canAssign = workspaceId != null && can?.assignTasks != false;
    final canLabel = workspaceId != null && can?.updateLabels != false;

    final members = canAssign
        ? ref.watch(membersQuery((workspaceId: workspaceId, projectId: project?.id))).value
        : null;
    final assignee = members?.where((m) => m.id == _assigneeId).firstOrNull;
    final workspaceLabels = canLabel ? ref.watch(workspaceLabelsQuery(workspaceId)).value : null;
    final labels = [
      for (final label in _labelOptions(workspaceLabels))
        if (_labelIds.contains(label.id)) label,
    ];

    Object? loadFailure;
    VoidCallback? retry;
    void failedWith(AsyncValue<Object?>? value, VoidCallback again) {
      if (loadFailure != null || value == null || value.hasValue || !value.hasError) return;
      loadFailure = value.error;
      retry = again;
    }

    failedWith(workspace, () => ref.read(workspacesQuery.notifier).refresh());
    if (workspaceId != null) {
      failedWith(projectsValue, () => ref.read(projectsQuery(workspaceId).notifier).refresh());
    }
    if (project != null) {
      failedWith(columnsValue, () => ref.read(columnsQuery(project.id).notifier).refresh());
    }
    final noProjects = workspace.hasValue && (workspaceId == null || projects?.isEmpty == true);

    // Who it is assigned to has to be known to be someone in this project.
    final ready =
        canCreate &&
        !_busy &&
        workspaceId != null &&
        project != null &&
        status != null &&
        (_assigneeId == null || members != null);
    final VoidCallback? submit = ready
        ? () => _submit(
            workspaceId: workspaceId,
            projectId: project.id,
            status: status,
            assignee: assignee,
            labels: labels,
          )
        : null;

    final titleStyle = Theme.of(context).textTheme.headlineSmall!.copyWith(
      fontSize: 24,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: colors.foreground,
    );

    final fields = <Widget>[
      _field(
        key: const ValueKey('new-task-project'),
        label: context.t('mobile:taskNew.project'),
        icon: Icon(projectIcon(project?.icon), size: 14, color: colors.mutedForeground),
        value: project?.name,
        prompt: context.t('common:modals.createTask.selectProject'),
        empty: context.t('common:modals.createTask.selectProject'),
        onPressed: projects == null || projects.isEmpty
            ? null
            : (anchor) => _pickProject(anchor, projects),
      ),
      _field(
        key: const ValueKey('new-task-status'),
        label: context.t('mobile:taskFields.status'),
        icon: Icon(
          status == null ? LucideIcons.circleDashed : taskStatusIcon(status, column),
          size: 14,
        ),
        value: status == null ? null : taskStatusName(context, status, columns!),
        empty: '',
        onPressed: project == null || columns == null || status == null
            ? null
            : (anchor) => _pickStatus(anchor, project.id, columns, status),
      ),
      _field(
        key: const ValueKey('new-task-priority'),
        label: context.t('mobile:taskFields.priority'),
        icon: Icon(LucideIcons.signal, size: 14, color: priorityColor(context, _priority)),
        value: _priority == priorities.first ? null : priorityLabel(context, _priority),
        onPressed: _pickPriority,
      ),
      _field(
        key: const ValueKey('new-task-assignee'),
        label: context.t('mobile:taskFields.assignee'),
        icon: CircleAvatar(
          radius: 9,
          backgroundColor: colors.avatar,
          foregroundColor: colors.avatarForeground,
          child: assignee == null
              ? const Icon(LucideIcons.user, size: 10)
              : Text(initials(assignee.name), style: const TextStyle(fontSize: 8)),
        ),
        value: assignee?.name,
        empty: context.t('mobile:taskFields.unassigned'),
        onPressed: canAssign ? (anchor) => _pickAssignee(anchor, workspaceId, members) : null,
      ),
      _field(
        key: const ValueKey('new-task-start-date'),
        label: context.t('mobile:taskFields.startDate'),
        icon: Icon(LucideIcons.calendarDays, size: 14, color: colors.mutedForeground),
        value: _startDate == null ? null : formatDate(i18n, _startDate),
        empty: context.t('tasks:properties.noDate'),
        onPressed: (anchor) => _pickDay(
          anchor,
          anchor.t('mobile:taskFields.startDate'),
          _startDate,
          (date) => _startDate = date,
        ),
      ),
      _field(
        key: const ValueKey('new-task-due-date'),
        label: context.t('mobile:taskFields.dueDate'),
        icon: Icon(LucideIcons.calendar, size: 14, color: colors.mutedForeground),
        value: _dueDate == null ? null : formatDate(i18n, _dueDate),
        empty: context.t('tasks:properties.noDate'),
        onPressed: (anchor) => _pickDay(
          anchor,
          anchor.t('mobile:taskFields.dueDate'),
          _dueDate,
          (date) => _dueDate = date,
        ),
      ),
      _field(
        key: const ValueKey('new-task-labels'),
        label: context.t('mobile:taskFields.labels'),
        icon: Icon(LucideIcons.tag, size: 14, color: colors.mutedForeground),
        value: labels.isEmpty ? null : '',
        empty: context.t(canLabel ? 'tasks:properties.addLabels' : 'mobile:taskFields.none'),
        content: labels.isEmpty
            ? null
            : Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [for (final label in labels) PropertyLabel(label: label)],
              ),
        onPressed: canLabel
            ? (anchor) =>
                  _pickLabels(anchor, workspaceId, workspaceLabels, can?.createLabels != false)
            : null,
      ),
    ];

    final size = Size(0, wide ? 32 : 40);
    return PopScope(
      // The task is on its way, and closing now would leave no word of how that went.
      canPop: !_busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // Keeps the buttons at the bottom of a page.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: wide ? const EdgeInsets.fromLTRB(24, 8, 24, 16) : const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const ValueKey('new-task-title'),
                    controller: _title,
                    focusNode: _titleFocus,
                    autofocus: true,
                    style: titleStyle,
                    minLines: 1,
                    maxLines: null,
                    // Not multiline, so that Enter finishes the title instead of adding a line.
                    keyboardType: TextInputType.text,
                    // A hardware keyboard's Enter creates the task, as in the web app. A phone's
                    // key is too easy to press on the way to the description.
                    textInputAction: wide ? TextInputAction.done : TextInputAction.next,
                    textCapitalization: TextCapitalization.sentences,
                    // Every border by name, because the theme gives text boxes their own.
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintText: context.t('mobile:taskNew.taskTitle'),
                      hintStyle: titleStyle.copyWith(color: colors.mutedForeground),
                    ),
                    onSubmitted: wide ? (_) => submit?.call() : null,
                    // Touch screens don't leave a text box on a tap elsewhere unless told to.
                    onTapOutside: (_) => _titleFocus.unfocus(),
                  ),
                  const SizedBox(height: 16),
                  MarkdownField(
                    key: const ValueKey('new-task-description'),
                    controller: _description,
                    focusNode: _descriptionFocus,
                    hintText: context.t('common:modals.createTask.descriptionPlaceholder'),
                  ),
                  const SizedBox(height: 16),
                  if (wide)
                    Wrap(spacing: 8, runSpacing: 8, children: fields)
                  else
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: fields),
                  if (!canCreate)
                    _Notice(
                      key: const ValueKey('new-task-notice'),
                      context.t('mobile:errors.forbidden'),
                    )
                  else if (loadFailure != null)
                    _Notice(
                      key: const ValueKey('new-task-notice'),
                      isForbidden(loadFailure)
                          ? context.t('mobile:errors.forbidden')
                          : userMessage(context, loadFailure),
                      color: colors.destructiveForeground,
                      onRetry: isForbidden(loadFailure) ? null : retry,
                    )
                  else if (noProjects)
                    _Notice(
                      key: const ValueKey('new-task-notice'),
                      context.t('app:shell.noProjects'),
                    ),
                  if (_error != null)
                    _Notice(
                      key: const ValueKey('new-task-error'),
                      _error!,
                      color: colors.destructiveForeground,
                    ),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              // The web app's `bg-muted/72`.
              color: colors.muted.withValues(alpha: colors.muted.a * 0.72),
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16, vertical: 12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const ValueKey('new-task-cancel'),
                    style: OutlinedButton.styleFrom(minimumSize: size),
                    onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                    child: Text(context.t('mobile:common.cancel')),
                  ),
                  ListenableBuilder(
                    listenable: _title,
                    builder: (context, _) => FilledButton(
                      key: const ValueKey('new-task-create'),
                      style: FilledButton.styleFrom(minimumSize: size),
                      onPressed: singleLineTitle(_title.text).isEmpty ? null : submit,
                      child: Text(context.t('mobile:taskNew.create')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A line under the fields, on what is keeping the form from working.
class _Notice extends StatelessWidget {
  const _Notice(this.message, {super.key, this.color, this.onRetry});

  final String message;
  final Color? color;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color ?? context.colors.mutedForeground),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(context.t('mobile:common.retry'))),
        ],
      ),
    );
  }
}
