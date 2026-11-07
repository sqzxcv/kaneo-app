import 'package:flutter/widgets.dart';

import '../i18n/i18n.dart';

/// Task priorities in the order they are offered, as the API spells them.
const List<String> priorities = ['no-priority', 'low', 'medium', 'high', 'urgent'];

/// The status values of tasks outside the board's columns.
const String statusPlanned = 'planned';
const String statusArchived = 'archived';

String priorityLabel(BuildContext context, String? value) => switch (value) {
  'low' => context.t('mobile:meta.priority.low'),
  'medium' => context.t('mobile:meta.priority.medium'),
  'high' => context.t('mobile:meta.priority.high'),
  'urgent' => context.t('mobile:meta.priority.urgent'),
  _ => context.t('mobile:meta.priority.noPriority'),
};

const Map<String, Color> _labelColors = {
  'gray': Color(0xFF79716B),
  'dark-gray': Color(0xFF62748E),
  'purple': Color(0xFF8E51FF),
  'teal': Color(0xFF009966),
  'green': Color(0xFF00A63E),
  'yellow': Color(0xFFE17100),
  'orange': Color(0xFFF54900),
  'pink': Color(0xFFEC003F),
  'red': Color(0xFFE7000B),
  'blue': Color(0xFF155DFC),
  'sky': Color(0xFF00A6F4),
  'cyan': Color(0xFF0092B8),
  'fuchsia': Color(0xFFC800DE),
};

/// The colors offered for a new label: the palette without its two grays, as in the current app.
List<String> get labelColorChoices => _labelColors.keys.skip(2).toList();

/// The web app's label palette. Older and imported labels may store a hex color instead.
Color labelColor(String? value) {
  final named = _labelColors[value];
  if (named != null) return named;
  final hex = RegExp(r'^#([0-9a-fA-F]{3,8})$').firstMatch(value ?? '')?.group(1);
  if (hex != null) {
    final full = switch (hex.length) {
      3 => 'FF${hex.split('').map((c) => '$c$c').join()}',
      6 => 'FF$hex',
      8 => '${hex.substring(6)}${hex.substring(0, 6)}',
      _ => null,
    };
    if (full != null) return Color(int.parse(full, radix: 16));
  }
  return const Color(0xFFA1A1A1);
}

/// A task's ticket id such as `KAN-12`, or `#12` when the project is unknown.
String ticketId(String? projectSlug, int? number) {
  if (number == null) return '';
  return projectSlug == null || projectSlug.isEmpty
      ? '#$number'
      : '${projectSlug.toUpperCase()}-$number';
}

/// Up to two letters for an avatar without a picture.
String initials(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String head(String part, int n) => part.characters.take(n).toString();
  if (parts.length == 1) return head(parts.first, 2).toUpperCase();
  return '${head(parts.first, 1)}${head(parts.last, 1)}'.toUpperCase();
}
