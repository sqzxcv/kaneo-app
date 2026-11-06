import 'package:flutter/material.dart';

import '../api/models.dart';
import '../format/style.dart';
import '../i18n/i18n.dart';

/// A choice made in a picker whose answer can legitimately be null, such as "unassigned". The
/// picker itself resolves to null when dismissed, so the two cases stay apart.
class Picked<T> {
  const Picked(this.value);

  final T value;
}

/// One row of a picker.
class PickerOption<T> {
  const PickerOption({required this.value, required this.label, this.subtitle, this.leading});

  final T value;
  final String label;
  final String? subtitle;
  final Widget? leading;
}

/// Picks one option. Resolves to null if dismissed.
///
/// Like every picker here, it opens by [context]'s widget, so call it with the context of the
/// control that was pressed. For a pointer action, pass the global [position] as well.
Future<Picked<T>?> pickOption<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
  Offset? position,
}) {
  return showModalBottomSheet<Picked<T>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: _SheetBody(
        title: title,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final option in options)
              ListTile(
                leading: option.leading,
                title: Text(option.label),
                subtitle: option.subtitle == null ? null : Text(option.subtitle!),
                trailing: option.value == selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(Picked<T>(option.value)),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Picks any number of options. Resolves to the new selection, or null if dismissed.
Future<Set<T>?> pickMany<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  required Set<T> selected,
  Offset? position,
}) {
  return showModalBottomSheet<Set<T>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final current = {...selected};
      return StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: _SheetBody(
            title: title,
            action: TextButton(
              onPressed: () => Navigator.of(context).pop(current),
              child: Text(context.t('mobile:common.save')),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final option in options)
                  CheckboxListTile(
                    secondary: option.leading,
                    title: Text(option.label),
                    subtitle: option.subtitle == null ? null : Text(option.subtitle!),
                    value: current.contains(option.value),
                    onChanged: (checked) => setState(() {
                      checked == true ? current.add(option.value) : current.remove(option.value);
                    }),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Picks a column. Resolves to its slug, which is what tasks store as their status.
Future<String?> pickStatus(
  BuildContext context, {
  required List<ProjectColumn> columns,
  String? current,
  Offset? position,
}) async {
  final picked = await pickOption<String>(
    context,
    title: context.t('mobile:taskFields.status'),
    selected: current,
    position: position,
    options: [for (final c in columns) PickerOption(value: c.slug, label: c.name)],
  );
  return picked?.value;
}

/// Picks a priority. Resolves to its API value, such as `high`.
Future<String?> pickPriority(BuildContext context, {String? current, Offset? position}) async {
  final picked = await pickOption<String>(
    context,
    title: context.t('mobile:taskFields.priority'),
    selected: current ?? priorities.first,
    position: position,
    options: [
      for (final value in priorities)
        PickerOption(value: value, label: priorityLabel(context, value)),
    ],
  );
  return picked?.value;
}

/// Picks an assignee. Resolves to the user id, `Picked(null)` for unassigned, or null if dismissed.
Future<Picked<String?>?> pickAssignee(
  BuildContext context, {
  required List<WorkspaceMember> members,
  String? current,
  Offset? position,
}) {
  return pickOption<String?>(
    context,
    title: context.t('mobile:taskFields.assignee'),
    selected: current,
    position: position,
    options: [
      PickerOption(value: null, label: context.t('mobile:taskFields.unassigned')),
      for (final m in members) PickerOption(value: m.id, label: m.name, subtitle: m.email),
    ],
  );
}

/// Picks labels by id. Resolves to the new selection, or null if dismissed.
///
/// [onCreate] lets the person add a label inline; KAN-26 adds the control that calls it.
Future<Set<String>?> pickLabels(
  BuildContext context, {
  required List<Label> labels,
  required Set<String> selectedIds,
  Future<Label> Function(String name, String color)? onCreate,
  Offset? position,
}) {
  return pickMany<String>(
    context,
    title: context.t('mobile:taskFields.labels'),
    selected: selectedIds,
    position: position,
    options: [
      for (final l in labels)
        PickerOption(
          value: l.id,
          label: l.name,
          leading: CircleAvatar(radius: 6, backgroundColor: labelColor(l.color)),
        ),
    ],
  );
}

/// Picks a calendar day at local midnight. Resolves to `Picked(null)` when cleared, or null if
/// dismissed. Convert the day with `toApiDate` before sending it.
Future<Picked<DateTime?>?> pickDate(
  BuildContext context, {
  required String title,
  DateTime? current,
  Offset? position,
}) async {
  final now = DateTime.now();
  final day = await showDatePicker(
    context: context,
    // A tap outside would read as "clear", because the dialog only reports null.
    barrierDismissible: false,
    helpText: title,
    initialDate: current ?? now,
    firstDate: DateTime(now.year - 20),
    lastDate: DateTime(now.year + 20),
    cancelText: current == null ? null : context.t('mobile:picker.clear'),
  );
  if (day != null) return Picked(DateTime(day.year, day.month, day.day));
  return current == null ? null : const Picked(null);
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
              ?action,
            ],
          ),
        ),
        Flexible(child: child),
      ],
    );
  }
}
