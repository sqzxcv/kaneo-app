import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import '../activity/describe_activity.dart';
import '../markdown/markdown_field.dart';
import '../markdown/markdown_view.dart';
import '../markdown/mention_text.dart';
import 'task_activity.dart';
import 'task_edits.dart';
import 'task_relations_view.dart';

/// How tall the list of people to mention gets before it scrolls. It opens upward from the text box,
/// to stay clear of a phone's keyboard, where there may not be much room.
const double _suggestionsMaxHeight = 220;
const double _suggestionsWidth = 280;

/// Everything that happened on a task and the comments on it, oldest first as on the web, so that the
/// latest is right above the box for a new comment.
///
/// Comments count as changing the task on the server. Permissions that haven't loaded count as
/// allowed, because the server has the last word.
class TaskActivitySection extends ConsumerWidget {
  const TaskActivitySection({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = taskActivitiesQuery(task.id);
    final value = ref.watch(query);
    final workspaceId = task.workspaceId;
    final can = workspaceId == null ? null : ref.watch(capabilitiesQuery(workspaceId)).value;
    final canComment = can?.updateTasks != false && !isForbidden(value.error);
    // Everyone in the workspace, because people who have left a project still wrote what they wrote.
    final members = workspaceId == null
        ? null
        : ref.watch(membersQuery((workspaceId: workspaceId, projectId: null))).value;
    final userId = ref.watch(sessionProvider.select((s) => s?.userId));
    final edits = ref.watch(taskEditsProvider(task.id));
    String? nameOf(String? id) => members?.where((m) => m.id == id).firstOrNull?.name;
    return Column(
      key: const ValueKey('task-activity'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskSectionHeader(title: context.t('tasks:detail.activity')),
        AsyncBody(
          value: value,
          onRetry: () => ref.read(query.notifier).refresh(),
          isEmpty: (items) => items.isEmpty,
          empty: TaskSectionNote(context.t('tasks:detail.noActivity')),
          builder: (context, items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items.reversed)
                isCommentEntry(item)
                    ? _CommentCard(
                        key: ValueKey('task-comment-${item.id}'),
                        task: task,
                        activity: item,
                        userName: nameOf(item.userId),
                        canChange: canComment && canChangeComment(item, userId),
                        edits: edits,
                      )
                    : _EventRow(
                        key: ValueKey('task-event-${item.id}'),
                        activity: item,
                        userName: nameOf(item.userId),
                      ),
            ],
          ),
        ),
        if (canComment) ...[const SizedBox(height: 8), _Composer(task: task, edits: edits)],
      ],
    );
  }
}

IconData _eventIcon(String type) => switch (type) {
  'priority_changed' => LucideIcons.circleAlert,
  'due_date_changed' => LucideIcons.calendar,
  'assignee_changed' || 'unassigned' => LucideIcons.userRound,
  _ => LucideIcons.history,
};

class _EventRow extends ConsumerWidget {
  const _EventRow({super.key, required this.activity, required this.userName});

  final Activity activity;
  final String? userName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final i18n = I18nScope.of(context);
    final now = ref.read(nowProvider)();
    final entry = feedEntry(activity, userName: userName);
    final description = describeActivity(i18n, entry, now: now);
    final time = relativeLong(i18n, activity.createdAt, now: now);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 20,
            child: Icon(_eventIcon(activity.type), size: 14, color: colors.mutedForeground),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: activityActor(i18n, entry),
                    style: TextStyle(fontWeight: FontWeight.w500, color: colors.foreground),
                  ),
                  TextSpan(text: ' $description · $time'),
                ],
              ),
              style: TextStyle(fontSize: 13, height: 1.5, color: colors.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentCard extends ConsumerStatefulWidget {
  const _CommentCard({
    super.key,
    required this.task,
    required this.activity,
    required this.userName,
    required this.canChange,
    required this.edits,
  });

  final Task task;
  final Activity activity;
  final String? userName;
  final bool canChange;
  final TaskEdits edits;

  @override
  ConsumerState<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends ConsumerState<_CommentCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _mentions = CommentMentions();
  bool _editing = false;
  bool _busy = false;

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _edit() {
    _mentions.clear();
    final text = _mentions.show(widget.activity.content ?? '');
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _editing = true);
  }

  /// A failure leaves the box open with what was typed in it, to try again.
  Future<void> _save() async {
    final text = _mentions.save(_controller.text);
    if (_busy || text.trim().isEmpty) return;
    if (text == widget.activity.content) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _busy = true);
    final saved = await widget.edits.editComment(widget.activity.id, text.trimRight());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (saved) _editing = false;
    });
  }

  Future<void> _delete() async {
    final confirmed = await showConfirm(
      context,
      title: context.t('mobile:taskDetail.activity.deleteTitle'),
      message: context.t('mobile:taskDetail.activity.deleteMessage'),
      confirmLabel: context.t('mobile:common.delete'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    await widget.edits.deleteComment(widget.activity.id);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    final colors = context.colors;
    final i18n = I18nScope.of(context);
    final name = activityActor(i18n, feedEntry(activity, userName: widget.userName));
    final now = ref.read(nowProvider)();
    final time = relativeLong(i18n, activity.createdAt, now: now);
    final buttonSize = Size.square(context.isWide ? 28 : 40);
    final size = Size(0, context.isWide ? 32 : 40);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.foreground.withValues(alpha: 0.02),
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(KaneoRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: buttonSize.height),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: colors.avatar,
                      foregroundColor: colors.avatarForeground,
                      child: Text(initials(name), style: const TextStyle(fontSize: 9)),
                    ),
                    const SizedBox(width: 8),
                    // One line, where a very long name gives way before the buttons do.
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: colors.foreground,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '  ${wasEdited(activity) ? context.t('mobile:taskDetail.activity.edited', {'time': time}) : time}',
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: colors.mutedForeground),
                      ),
                    ),
                    if (widget.canChange && !_editing) ...[
                      IconButton(
                        key: ValueKey('comment-edit-${activity.id}'),
                        tooltip: context.t('mobile:taskDetail.activity.edit'),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints.tight(buttonSize),
                        icon: const Icon(LucideIcons.pencil, size: 14),
                        onPressed: _busy ? null : _edit,
                      ),
                      IconButton(
                        key: ValueKey('comment-delete-${activity.id}'),
                        tooltip: context.t('mobile:common.delete'),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints.tight(buttonSize),
                        icon: const Icon(LucideIcons.trash2, size: 14),
                        onPressed: _busy ? null : _delete,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _editing
                    ? _CommentField(
                        name: 'comment-field-${activity.id}',
                        task: widget.task,
                        controller: _controller,
                        focus: _focus,
                        mentions: _mentions,
                        hint: context.t('activity:comment.editPlaceholder'),
                        autofocus: true,
                        readOnly: _busy,
                        actions: [
                          TextButton(
                            key: ValueKey('comment-cancel-${activity.id}'),
                            style: TextButton.styleFrom(minimumSize: size),
                            onPressed: _busy ? null : () => setState(() => _editing = false),
                            child: Text(context.t('mobile:common.cancel')),
                          ),
                          const SizedBox(width: 4),
                          ListenableBuilder(
                            listenable: _controller,
                            builder: (context, _) => FilledButton(
                              key: ValueKey('comment-save-${activity.id}'),
                              style: FilledButton.styleFrom(minimumSize: size),
                              onPressed: _busy || _controller.text.trim().isEmpty ? null : _save,
                              child: Text(context.t('mobile:common.save')),
                            ),
                          ),
                        ],
                      )
                    : MarkdownView(data: activity.content ?? ''),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.task, required this.edits});

  final Task task;
  final TaskEdits edits;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _mentions = CommentMentions();
  bool _sending = false;

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// A failure leaves the text in the box, to try again.
  Future<void> _send() async {
    final text = _mentions.save(_controller.text).trimRight();
    if (_sending || text.trim().isEmpty) return;
    setState(() => _sending = true);
    final saved = await widget.edits.addComment(text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (!saved) return;
    _controller.clear();
    _mentions.clear();
  }

  @override
  Widget build(BuildContext context) {
    return _CommentField(
      name: 'comment-box',
      task: widget.task,
      controller: _controller,
      focus: _focus,
      mentions: _mentions,
      hint: context.t('activity:comment.leavePlaceholder'),
      readOnly: _sending,
      actions: [
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            key: const ValueKey('comment-send'),
            style: FilledButton.styleFrom(minimumSize: Size(0, context.isWide ? 32 : 40)),
            onPressed: _sending || _controller.text.trim().isEmpty ? null : _send,
            child: Text(context.t('mobile:composer.sendComment')),
          ),
        ),
      ],
    );
  }
}

/// The text box for a comment, where an `@` offers the people to mention, with its buttons below it.
class _CommentField extends ConsumerStatefulWidget {
  const _CommentField({
    required this.name,
    required this.task,
    required this.controller,
    required this.focus,
    required this.mentions,
    required this.hint,
    required this.actions,
    this.autofocus = false,
    this.readOnly = false,
  });

  /// What the text box and its mention button go by.
  final String name;
  final Task task;
  final TextEditingController controller;
  final FocusNode focus;
  final CommentMentions mentions;
  final String hint;
  final List<Widget> actions;
  final bool autofocus;
  final bool readOnly;

  @override
  ConsumerState<_CommentField> createState() => _CommentFieldState();
}

class _CommentFieldState extends ConsumerState<_CommentField> {
  final _suggestions = OverlayPortalController();
  final _anchor = LayerLink();
  late final _typing = Listenable.merge([widget.controller, widget.focus]);

  @override
  void initState() {
    super.initState();
    // It stays up, and has nothing in it until there is someone to offer.
    _suggestions.show();
  }

  void _pick(MentionQuery query, WorkspaceMember person) {
    final mention = widget.mentions.pick(id: person.id, name: mentionName(person));
    widget.controller.value = withMention(widget.controller.value, query, mention);
    widget.focus.requestFocus();
  }

  void _startMention() {
    widget.controller.value = withAtSign(widget.controller.value);
    widget.focus.requestFocus();
  }

  Widget _buildSuggestions(BuildContext context, List<WorkspaceMember> people) => ListenableBuilder(
    listenable: _typing,
    builder: (context, _) {
      final query = widget.focus.hasFocus && !widget.readOnly
          ? mentionQueryAt(widget.controller.value)
          : null;
      final shown = query == null || widget.mentions.knows(query.query.trimRight())
          ? const <WorkspaceMember>[]
          : peopleMatching(people, query.query);
      if (shown.isEmpty) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.topLeft,
        child: CompositedTransformFollower(
          link: _anchor,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(0, -4),
          // Picking someone isn't leaving the text box.
          child: TextFieldTapRegion(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _suggestionsMaxHeight),
              child: PopoverSurface(
                width: math.min(_suggestionsWidth, _anchor.leaderSize?.width ?? _suggestionsWidth),
                child: PopoverBody(
                  rows: [
                    for (final person in shown)
                      PopoverRow(
                        key: ValueKey('mention-${person.id}'),
                        title: mentionName(person),
                        subtitle: person.email,
                        leading: _PersonAvatar(name: mentionName(person)),
                        onTap: () => _pick(query!, person),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final workspaceId = widget.task.workspaceId;
    // Who can be assigned here is who can see the task, so it is who to mention as well.
    final people = workspaceId == null
        ? const <WorkspaceMember>[]
        : ref
                  .watch(membersQuery((workspaceId: workspaceId, projectId: widget.task.projectId)))
                  .value ??
              const <WorkspaceMember>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverlayPortal(
          controller: _suggestions,
          overlayChildBuilder: (context) => _buildSuggestions(context, people),
          child: CompositedTransformTarget(
            link: _anchor,
            child: MarkdownField(
              key: ValueKey(widget.name),
              controller: widget.controller,
              focusNode: widget.focus,
              autofocus: widget.autofocus,
              readOnly: widget.readOnly,
              minLines: 2,
              hintText: widget.hint,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // Pressing this isn't leaving the text box either.
            TextFieldTapRegion(
              child: IconButton(
                key: ValueKey('${widget.name}-mention'),
                tooltip: context.t('mobile:composer.mentionSomeone'),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tight(Size.square(context.isWide ? 28 : 40)),
                icon: const Icon(LucideIcons.atSign, size: 14),
                onPressed: widget.readOnly ? null : _startMention,
              ),
            ),
            const Spacer(),
            ...widget.actions,
          ],
        ),
      ],
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = context.isWide ? 20.0 : 28.0;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colors.avatar,
      foregroundColor: colors.avatarForeground,
      child: Text(initials(name), style: TextStyle(fontSize: size * 0.42)),
    );
  }
}
