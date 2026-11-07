import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import 'task_edits.dart';

/// [text] as a title, which is one line. Line breaks can only get in by pasting, because there are no
/// input formatters to disturb an input method.
String singleLineTitle(String text) => text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();

/// A task's title, in a text box that looks like a heading. It saves when the person leaves it.
///
/// There are no input formatters, because they disturb an input method. Line breaks pasted in come
/// out when saving instead.
class TaskTitle extends ConsumerStatefulWidget {
  const TaskTitle({super.key, required this.task});

  final Task task;

  @override
  ConsumerState<TaskTitle> createState() => _TaskTitleState();
}

class _TaskTitleState extends ConsumerState<TaskTitle> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  late final TaskEdits _edits;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.title);
    _edits = ref.listenManual(taskEditsProvider(widget.task.id), (_, _) {}).read();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(TaskTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Text in progress wins. It is saved when the person leaves it.
    if (!_focus.hasFocus && widget.task.title != _controller.text) {
      _controller.text = widget.task.title;
    }
  }

  @override
  void dispose() {
    _save(leaving: true);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _save();
  }

  /// An empty title isn't a change. The task goes back to the one it has.
  void _save({bool leaving = false}) {
    if (_controller.text == widget.task.title) return;
    final title = singleLineTitle(_controller.text);
    if (title.isNotEmpty && title != widget.task.title) {
      _edits.setTitle(title, leaving: leaving);
    }
    if (leaving) return;
    final shown = title.isEmpty ? widget.task.title : title;
    if (_controller.text != shown) _controller.text = shown;
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = widget.task.workspaceId;
    final canEdit =
        workspaceId == null ||
        ref.watch(capabilitiesQuery(workspaceId)).value?.updateTasks != false;
    final theme = Theme.of(context).textTheme;
    final style = theme.headlineSmall!.copyWith(
      fontSize: 24,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: context.colors.foreground,
    );
    return TextField(
      key: const ValueKey('task-title'),
      controller: _controller,
      focusNode: _focus,
      readOnly: !canEdit,
      style: style,
      minLines: 1,
      maxLines: null,
      // Not multiline, so that Enter finishes the title instead of adding a line.
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
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
        hintText: context.t('tasks:detail.titlePlaceholder'),
        hintStyle: style.copyWith(color: context.colors.mutedForeground),
      ),
      onSubmitted: (_) => _focus.unfocus(),
      // Touch screens don't leave a text box on a tap elsewhere unless told to.
      onTapOutside: (_) => _focus.unfocus(),
    );
  }
}
