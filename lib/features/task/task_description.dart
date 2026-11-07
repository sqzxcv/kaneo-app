import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../markdown/markdown_field.dart';
import '../markdown/markdown_view.dart';
import 'description_autosave.dart';

/// A task's description: formatted, until a tap opens a text box on its Markdown source.
///
/// Changes save by themselves. The text box closes once the person has left it and everything is
/// saved. If saving fails it stays open with the text, and offers to try again.
class TaskDescription extends StatelessWidget {
  const TaskDescription({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) => _TaskDescription(key: ValueKey(task.id), task: task);
}

/// The whole text of a task whose response left it out for being large.
final _deferredDescription = FutureProvider.autoDispose.family<String, String>((ref, taskId) async {
  final api = ref.read(kaneoApiProvider);
  return loadDescription(api, await api.task(taskId));
}, retry: (count, error) => null);

class _TaskDescription extends ConsumerStatefulWidget {
  const _TaskDescription({super.key, required this.task});

  final Task task;

  @override
  ConsumerState<_TaskDescription> createState() => _TaskDescriptionState();
}

class _TaskDescriptionState extends ConsumerState<_TaskDescription> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final DescriptionAutosave _saver;
  late final AppLifecycleListener _lifecycle;

  /// The last value handed to [_saver], to tell edits from cursor moves.
  TextEditingValue _seen = TextEditingValue.empty;
  bool _editing = false;
  bool _opening = false;
  bool _focusOnOpen = false;

  String get _taskId => widget.task.id;

  @override
  void initState() {
    super.initState();
    // Listening keeps the saver alive for as long as this is on screen.
    _saver = ref.listenManual(descriptionAutosaveProvider(_taskId), (_, _) {}).read();
    _saver.addListener(_closeIfDone);
    _controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
    // The system may stop the app before the timer fires.
    _lifecycle = AppLifecycleListener(onHide: _saver.flush);
    final unsaved = _saver.unsavedText;
    if (unsaved != null) _fillTextBox(unsaved, focus: false);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _saver.removeListener(_closeIfDone);
    unawaited(_saver.flush());
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final value = _controller.value;
    final changed = value.text != _seen.text || value.composing != _seen.composing;
    _seen = value;
    if (changed) _saver.edit(value.text, composing: value.composing.isValid);
  }

  void _onFocusChanged() {
    if (_focus.hasFocus) return;
    unawaited(_saver.flush());
    _closeIfDone();
  }

  void _closeIfDone() {
    if (!_editing || _focus.hasFocus || _saver.hasUnsaved) return;
    setState(() => _editing = false);
  }

  /// Starts from what the server holds right now. The text on screen can be an old cached copy, and
  /// saving edits made to it would undo changes made elsewhere since.
  Future<void> _open() async {
    if (_opening || _editing || !_canEdit(watch: false)) return;
    setState(() => _opening = true);
    final api = ref.read(kaneoApiProvider);
    final loaded = await runAction(context, () async {
      final task = await api.task(_taskId);
      return (task: task, text: await loadDescription(api, task));
    });
    if (!mounted) return;
    if (loaded != null) {
      ref
          .read(taskQuery(_taskId).notifier)
          .setData(loaded.task.copyWith(description: loaded.text, descriptionDeferred: false));
      _saver.begin(loaded.text);
    }
    setState(() {
      _opening = false;
      if (loaded != null) _fillTextBox(loaded.text, focus: true);
    });
  }

  void _fillTextBox(String text, {required bool focus}) {
    final value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _seen = value;
    _controller.value = value;
    _editing = true;
    _focusOnOpen = focus;
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarkdownField(
            controller: _controller,
            focusNode: _focus,
            autofocus: _focusOnOpen,
            hintText: context.t('mobile:taskDetail.screen.addDescription'),
          ),
          // On its own, because rebuilding the text box on every status change is wasted work.
          ListenableBuilder(
            listenable: _saver,
            builder: (context, _) => _SaveStatus(status: _saver.status, onRetry: _saver.flush),
          ),
        ],
      );
    }
    final task = widget.task;
    if (task.descriptionDeferred == true) {
      final query = _deferredDescription(_taskId);
      return AsyncBody(
        value: ref.watch(query),
        onRetry: () => ref.invalidate(query),
        builder: (context, text) => _formatted(text),
      );
    }
    return _formatted(task.description ?? '');
  }

  /// The server has the last word, so only a clear no takes the text box away.
  bool _canEdit({required bool watch}) {
    final workspaceId = widget.task.workspaceId;
    if (workspaceId == null) return true;
    final query = capabilitiesQuery(workspaceId);
    return (watch ? ref.watch(query) : ref.read(query)).value?.updateTasks != false;
  }

  Widget _formatted(String text) {
    final canEdit = _canEdit(watch: true);
    return MouseRegion(
      cursor: canEdit ? SystemMouseCursors.text : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canEdit ? _open : null,
        child: Stack(
          children: [
            text.trim().isEmpty
                ? _Empty(canEdit: canEdit)
                : MarkdownView(data: text, onTapText: _open),
            if (_opening)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canEdit});

  final bool canEdit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        canEdit
            ? context.t('mobile:taskDetail.screen.addDescription')
            : context.t('app:description.empty'),
        style: Theme.of(context).textTheme.bodyMedium!
            .copyWith(fontSize: markdownTextSize, color: context.colors.mutedForeground),
      ),
    ),
  );
}

class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.status, required this.onRetry});

  final DescriptionSaveStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(context).textTheme.bodySmall!;
    final failed = status == DescriptionSaveStatus.failed;
    final label = switch (status) {
      DescriptionSaveStatus.idle => null,
      DescriptionSaveStatus.saving => context.t('app:description.saving'),
      DescriptionSaveStatus.saved => context.t('app:description.saved'),
      DescriptionSaveStatus.failed => context.t('app:description.notSaved'),
    };
    // The same height in every state, so the page doesn't jump under the person typing.
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          if (label != null)
            Expanded(
              child: Text(
                label,
                style: style.copyWith(color: failed ? colors.destructive : colors.mutedForeground),
              ),
            ),
          if (failed) TextButton(onPressed: onRetry, child: Text(context.t('mobile:common.retry'))),
        ],
      ),
    );
  }
}
