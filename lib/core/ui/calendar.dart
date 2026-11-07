import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../format/dates.dart';
import '../i18n/i18n.dart';
import '../layout/breakpoints.dart';
import '../theme/app_theme.dart';
import 'popover.dart';

/// The weeks of a month, Monday first. Cells outside the month are null.
List<List<DateTime?>> monthGrid(int year, int month) {
  final first = DateTime(year, month);
  final days = DateTime(year, month + 1, 0).day;
  final cells = <DateTime?>[
    ...List<DateTime?>.filled(first.weekday - DateTime.monday, null),
    for (var day = 1; day <= days; day++) DateTime(year, month, day),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return [for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7)];
}

/// The Monday after [day], which is a week away when [day] is a Monday.
DateTime nextMonday(DateTime day) => DateTime(day.year, day.month, day.day + 8 - day.weekday);

/// The current app's date picker: shortcuts, then a month to page through.
class KaneoCalendar extends StatefulWidget {
  const KaneoCalendar({super.key, this.selected, required this.onPick});

  final DateTime? selected;

  /// Called with local midnight of the chosen day.
  final ValueChanged<DateTime> onPick;

  @override
  State<KaneoCalendar> createState() => _KaneoCalendarState();
}

class _KaneoCalendarState extends State<KaneoCalendar> {
  late DateTime _month = () {
    final shown = widget.selected ?? DateTime.now();
    return DateTime(shown.year, shown.month);
  }();

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  Widget _shortcut(String label, DateTime day) => Expanded(
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => widget.onPick(startOfDay(day)),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );

  Widget _pageButton(String tooltip, IconData icon, int months) => IconButton(
    tooltip: tooltip,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    icon: Icon(icon, size: 16),
    onPressed: () => _shift(months),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final locale = I18nScope.of(context).intlLocale;
    final today = startOfDay(DateTime.now());
    final selected = widget.selected == null ? null : startOfDay(widget.selected!);
    final weekday = DateFormat.E(locale);
    final dayLabel = DateFormat.yMMMd(locale);
    return Padding(
      // Lines up with the title above, past the padding `PopoverBody` gives its rows.
      padding: EdgeInsets.symmetric(horizontal: context.isWide ? 8 : 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 6,
            children: [
              _shortcut(context.t('mobile:time.today'), today),
              _shortcut(
                context.t('mobile:time.tomorrow'),
                DateTime(today.year, today.month, today.day + 1),
              ),
              _shortcut(context.t('mobile:picker.nextWeek'), nextMonday(today)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat.yMMMM(locale).format(_month),
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _pageButton(context.t('mobile:picker.previousMonth'), LucideIcons.chevronLeft, -1),
              _pageButton(context.t('mobile:picker.nextMonth'), LucideIcons.chevronRight, 1),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(
                    // 2026-01-05 is a Monday.
                    weekday.format(DateTime(2026, 1, 5 + i)),
                    textAlign: TextAlign.center,
                    style: text.labelSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final week in monthGrid(_month.year, _month.month))
            Row(
              children: [
                for (final day in week)
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: day == null
                          ? null
                          : Center(
                              child: _DayCell(
                                day: day,
                                label: dayLabel.format(day),
                                selected: day == selected,
                                today: day == today,
                                onTap: () => widget.onPick(day),
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

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.label,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final DateTime day;
  final String label;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: HoverHighlight(
        enabled: !selected,
        borderRadius: 18,
        child: InkWell(
          customBorder: const CircleBorder(),
          hoverColor: Colors.transparent,
          mouseCursor: SystemMouseCursors.basic,
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? colors.primary : null,
              border: today && !selected ? Border.all(color: colors.foreground, width: 1.5) : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontFamily: KaneoFonts.mono,
                fontSize: 14,
                fontWeight: today || selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? colors.primaryForeground : colors.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
