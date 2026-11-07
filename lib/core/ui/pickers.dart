import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/models.dart';
import '../errors.dart';
import '../format/style.dart';
import '../i18n/i18n.dart';
import '../layout/breakpoints.dart';
import '../theme/app_theme.dart';
import 'calendar.dart';
import 'popover.dart';

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

/// How wide pickers with a text field are. A text field cannot size a popover by itself.
const double _fieldPickerWidth = 256;

/// Picks one option. Resolves to null if dismissed.
///
/// Like every picker here, it opens by [context]'s widget, so call it with the context of the
/// control that was pressed. For a pointer action, pass the global [position] as well. Wide windows
/// show it as a popover there, and narrow ones as a bottom sheet.
///
/// [searchHint] adds a field that filters the options by label and subtitle.
Future<Picked<T>?> pickOption<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
  Offset? position,
  String? searchHint,
}) {
  return showPopover<Picked<T>>(
    context,
    position: position,
    width: searchHint == null ? null : _fieldPickerWidth,
    builder: (context) => _OptionPicker<T>(
      title: title,
      options: options,
      selected: selected,
      searchHint: searchHint,
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
  return showPopover<Set<T>>(
    context,
    position: position,
    builder: (context) => _ManyPicker<T>(title: title, options: options, selected: selected),
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
    options: [
      for (final c in columns)
        PickerOption(
          value: c.slug,
          label: c.name,
          leading: _StatusIcon(column: c),
        ),
    ],
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
        PickerOption(
          value: value,
          label: priorityLabel(context, value),
          leading: _PriorityIcon(priority: value),
        ),
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
    searchHint: context.t('mobile:taskFields.searchPeople'),
    options: [
      PickerOption(
        value: null,
        label: context.t('mobile:taskFields.unassigned'),
        leading: const _Avatar(name: null),
      ),
      for (final m in members)
        PickerOption(
          value: m.id,
          label: m.name,
          subtitle: m.email,
          leading: _Avatar(name: m.name),
        ),
    ],
  );
}

/// Picks labels by id. Resolves to the new selection, or null if dismissed.
///
/// The field filters the labels. With [onCreate], a name no label has yet can be added on the spot,
/// in a color from the web app's palette, and the new label starts out selected.
Future<Set<String>?> pickLabels(
  BuildContext context, {
  required List<Label> labels,
  required Set<String> selectedIds,
  Future<Label> Function(String name, String color)? onCreate,
  Offset? position,
}) {
  return showPopover<Set<String>>(
    context,
    position: position,
    width: _fieldPickerWidth,
    builder: (context) =>
        _LabelPicker(labels: labels, selectedIds: selectedIds, onCreate: onCreate),
  );
}

/// Picks a calendar day at local midnight. Resolves to `Picked(null)` when cleared, or null if
/// dismissed. Convert the day with `toApiDate` before sending it.
Future<Picked<DateTime?>?> pickDate(
  BuildContext context, {
  required String title,
  DateTime? current,
  Offset? position,
}) {
  return showPopover<Picked<DateTime?>>(
    context,
    position: position,
    width: 296,
    builder: (context) => PopoverBody(
      title: title,
      action: current == null
          ? null
          : _HeaderButton(
              label: context.t('mobile:picker.clear'),
              color: context.colors.destructiveForeground,
              onPressed: () => Navigator.of(context).pop(const Picked<DateTime?>(null)),
            ),
      rows: [
        KaneoCalendar(
          selected: current,
          onPick: (day) => Navigator.of(context).pop(Picked<DateTime?>(day)),
        ),
      ],
    ),
  );
}

/// Whether [query] appears in any of [texts], ignoring case and surrounding space.
bool _matches(String query, List<String?> texts) {
  final needle = query.trim().toLowerCase();
  return needle.isEmpty || texts.any((text) => text?.toLowerCase().contains(needle) ?? false);
}

class _OptionPicker<T> extends StatefulWidget {
  const _OptionPicker({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchHint,
  });

  final String title;
  final List<PickerOption<T>> options;
  final T? selected;
  final String? searchHint;

  @override
  State<_OptionPicker<T>> createState() => _OptionPickerState<T>();
}

class _OptionPickerState<T> extends State<_OptionPicker<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final option in widget.options)
        if (_matches(_query, [option.label, option.subtitle])) option,
    ];
    return PopoverBody(
      title: widget.title,
      search: widget.searchHint == null
          ? null
          : _SearchField(
              hint: widget.searchHint!,
              onChanged: (value) => setState(() => _query = value),
            ),
      rows: [
        for (final option in shown)
          PopoverRow(
            title: option.label,
            subtitle: option.subtitle,
            leading: _SelectionSlot(
              selected: option.value == widget.selected,
              child: option.leading,
            ),
            onTap: () => Navigator.of(context).pop(Picked<T>(option.value)),
          ),
        if (shown.isEmpty && _query.trim().isNotEmpty)
          _Note(context.t('mobile:ui.nothingMatches', {'query': _query.trim()})),
      ],
    );
  }
}

class _ManyPicker<T> extends StatefulWidget {
  const _ManyPicker({required this.title, required this.options, required this.selected});

  final String title;
  final List<PickerOption<T>> options;
  final Set<T> selected;

  @override
  State<_ManyPicker<T>> createState() => _ManyPickerState<T>();
}

class _ManyPickerState<T> extends State<_ManyPicker<T>> {
  late final Set<T> _current = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return PopoverBody(
      title: widget.title,
      action: _HeaderButton(
        label: context.t('mobile:common.save'),
        onPressed: () => Navigator.of(context).pop(_current),
      ),
      rows: [
        for (final option in widget.options)
          _CheckRow(
            label: option.label,
            subtitle: option.subtitle,
            leading: option.leading,
            checked: _current.contains(option.value),
            onChanged: (checked) => setState(() {
              checked ? _current.add(option.value) : _current.remove(option.value);
            }),
          ),
      ],
    );
  }
}

class _LabelPicker extends StatefulWidget {
  const _LabelPicker({required this.labels, required this.selectedIds, required this.onCreate});

  final List<Label> labels;
  final Set<String> selectedIds;
  final Future<Label> Function(String name, String color)? onCreate;

  @override
  State<_LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<_LabelPicker> {
  late final List<Label> _labels = [...widget.labels];
  late final Set<String> _selected = {...widget.selectedIds};
  final _search = TextEditingController();
  String _color = labelColorChoices.first;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create(String name) async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final label = await widget.onCreate!(name, _color);
      if (!mounted) return;
      setState(() {
        _labels.add(label);
        _selected.add(label.id);
        _search.clear();
      });
    } catch (error) {
      // Here rather than as a toast, which a bottom sheet would cover.
      if (mounted) setState(() => _error = userMessage(context, error));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _search.text.trim();
    final shown = [
      for (final label in _labels)
        if (_matches(name, [label.name])) label,
    ];
    final taken = _labels.any((label) => label.name.toLowerCase() == name.toLowerCase());
    final canCreate = widget.onCreate != null && name.isNotEmpty && !taken;
    return PopoverBody(
      title: context.t('mobile:taskFields.labels'),
      action: _HeaderButton(
        label: context.t('mobile:common.save'),
        onPressed: () => Navigator.of(context).pop(_selected),
      ),
      search: _SearchField(
        controller: _search,
        hint: context.t(
          widget.onCreate == null ? 'mobile:ui.search' : 'mobile:taskFields.searchOrCreate',
        ),
        onChanged: (_) => setState(() => _error = null),
      ),
      rows: [
        for (final label in shown)
          _CheckRow(
            label: label.name,
            leading: _LabelDot(color: labelColor(label.color)),
            checked: _selected.contains(label.id),
            onChanged: (checked) => setState(() {
              checked ? _selected.add(label.id) : _selected.remove(label.id);
            }),
          ),
        if (canCreate) ...[
          PopoverRow(
            enabled: !_creating,
            leading: Icon(LucideIcons.plus, size: 16, color: context.colors.foreground),
            title: context.t('mobile:taskFields.createLabel', {'name': name}),
            onTap: () => _create(name),
          ),
          _ColorChoices(selected: _color, onChanged: (color) => setState(() => _color = color)),
        ] else if (shown.isEmpty)
          _Note(
            name.isNotEmpty
                ? context.t('mobile:ui.nothingMatches', {'query': name})
                : context.t(
                    widget.onCreate == null
                        ? 'mobile:taskFields.none'
                        : 'mobile:taskFields.noLabels',
                  ),
          ),
        if (_error != null) _Note(_error!, color: context.colors.destructiveForeground),
      ],
    );
  }
}

/// A checkbox row. A list tile, so that it behaves the same in both layouts, inside the highlight
/// every row has.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.checked,
    required this.onChanged,
    this.subtitle,
    this.leading,
  });

  final String label;
  final String? subtitle;
  final Widget? leading;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return HoverHighlight(
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        hoverColor: Colors.transparent,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        activeColor: c.primary,
        checkColor: c.primaryForeground,
        side: BorderSide(color: c.ring),
        checkboxShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        secondary: leading,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
        value: checked,
        onChanged: (value) => onChanged(value ?? false),
      ),
    );
  }
}

/// Keeps a place for the check mark of the current choice, as the web app's radio items do.
class _SelectionSlot extends StatelessWidget {
  const _SelectionSlot({required this.selected, this.child});

  final bool selected;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        SizedBox.square(
          dimension: 16,
          child: selected
              ? Icon(LucideIcons.check, size: 16, color: context.colors.foreground)
              : null,
        ),
        ?child,
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.label, required this.onPressed, this.color});

  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged, this.controller});

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      autocorrect: false,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(LucideIcons.search, size: 16, color: context.colors.mutedForeground),
        prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
    );
  }
}

class _ColorChoices extends StatelessWidget {
  const _ColorChoices({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            context.t('mobile:taskFields.labelColor'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in labelColorChoices)
                Semantics(
                  label: name,
                  button: true,
                  selected: name == selected,
                  child: InkWell(
                    key: ValueKey('label-color-$name'),
                    customBorder: const CircleBorder(),
                    onTap: () => onChanged(name),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: labelColor(name),
                        border: name == selected ? Border.all(color: c.foreground, width: 2) : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabelDot extends StatelessWidget {
  const _LabelDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// A person's initials, or a blank circle for nobody.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = context.isWide ? 20.0 : 28.0;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: name == null ? c.avatarUnassigned : c.avatar,
      child: name == null
          ? Icon(LucideIcons.user, size: size * 0.6, color: c.avatarUnassignedForeground)
          : Text(
              initials(name),
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w500,
                color: c.avatarForeground,
              ),
            ),
    );
  }
}

/// A column's icon, which is monochrome like the rest of the app's statuses.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.column});

  final ProjectColumn column;

  @override
  Widget build(BuildContext context) {
    final icon = switch (column.slug) {
      'in-progress' => LucideIcons.circleDot,
      'in-review' => LucideIcons.search,
      statusPlanned => LucideIcons.circleDashed,
      statusArchived => LucideIcons.archive,
      _ =>
        column.isFinal == true || column.slug == 'done'
            ? LucideIcons.circleCheck
            : LucideIcons.circle,
    };
    return Icon(icon, size: 16, color: context.colors.mutedForeground);
  }
}

/// A priority's three marks, as in the current app.
class _PriorityIcon extends StatelessWidget {
  const _PriorityIcon({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (marks, tint) = switch (priority) {
      'low' => (1, c.priorityLow),
      'medium' => (2, c.priorityMedium),
      'high' => (3, c.priorityHigh),
      'urgent' => (3, c.priorityUrgent),
      _ => (0, c.mutedForeground),
    };
    if (marks == 0) return Icon(LucideIcons.minus, size: 14, color: tint);
    return CustomPaint(
      size: const Size.square(14),
      painter: _PriorityMarks(marks: marks, filled: tint, empty: c.priorityBarEmpty),
    );
  }
}

class _PriorityMarks extends CustomPainter {
  const _PriorityMarks({required this.marks, required this.filled, required this.empty});

  final int marks;
  final Color filled;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (index, x) in const [3.0, 7.0, 11.0].indexed) {
      final paint = Paint()
        ..color = index < marks ? filled : empty
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, 2.5), Offset(x, 8), paint);
      canvas.drawCircle(Offset(x, 11), 1, paint);
    }
  }

  @override
  bool shouldRepaint(_PriorityMarks oldDelegate) =>
      marks != oldDelegate.marks || filled != oldDelegate.filled || empty != oldDelegate.empty;
}
