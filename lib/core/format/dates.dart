import 'package:intl/intl.dart';

import '../i18n/i18n.dart';

/// Parses a server date. A bare `2026-03-09` is that calendar day here, not UTC midnight, which
/// would be the previous day west of UTC.
DateTime? parseInstant(String? value) {
  if (value == null || value.isEmpty) return null;
  final bare = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (bare != null) {
    return DateTime(int.parse(bare[1]!), int.parse(bare[2]!), int.parse(bare[3]!));
  }
  return DateTime.tryParse(value)?.toLocal();
}

/// Local midnight of the day [value] falls on.
DateTime? parseDay(String? value) {
  final instant = parseInstant(value);
  return instant == null ? null : startOfDay(instant);
}

DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

int _daysBetween(DateTime from, DateTime to) =>
    (startOfDay(to).difference(startOfDay(from)).inHours / 24).round();

/// Kaneo stores calendar dates as the instant of local midnight, like the web app.
String toApiDate(DateTime day) => startOfDay(day).toUtc().toIso8601String();

/// `Oct 14`, with the year when it is not this year.
String formatDay(I18n i18n, DateTime day, {DateTime? now}) {
  final sameYear = day.year == (now ?? DateTime.now()).year;
  final format = sameYear ? DateFormat.MMMd(i18n.intlLocale) : DateFormat.yMMMd(i18n.intlLocale);
  return format.format(day);
}

String formatDate(I18n i18n, String? value) {
  final day = parseDay(value);
  return day == null ? '' : formatDay(i18n, day);
}

/// `Today`, `Tomorrow`, `Sun, Oct 4` within a week, otherwise `Oct 14`.
String formatDueShort(I18n i18n, String? value, {DateTime? now}) {
  final day = parseDay(value);
  if (day == null) return '';
  final today = now ?? DateTime.now();
  final diff = _daysBetween(today, day);
  if (diff == 0) return i18n.t('mobile:time.today');
  if (diff == 1) return i18n.t('mobile:time.tomorrow');
  if (diff > 1 && diff < 7) return DateFormat.MMMEd(i18n.intlLocale).format(day);
  return formatDay(i18n, day, now: today);
}

/// `Friday, November 6`, for page headers.
String formatLongDate(I18n i18n, DateTime date) =>
    DateFormat.MMMMEEEEd(i18n.intlLocale).format(date);

/// `Oct 14, 16:30`, with the year when it is not this year.
String formatDateTime(I18n i18n, String? value, {DateTime? now}) {
  final date = parseInstant(value);
  if (date == null) return '';
  return '${formatDay(i18n, date, now: now)} ${DateFormat.Hm(i18n.intlLocale).format(date)}';
}

bool isOverdue(String? value, {DateTime? now}) => daysOverdue(value, now: now) > 0;

/// Whole days a due date is late by, or 0.
int daysOverdue(String? value, {DateTime? now}) {
  final day = parseDay(value);
  if (day == null) return 0;
  final late = _daysBetween(day, now ?? DateTime.now());
  return late < 0 ? 0 : late;
}

/// Compact relative time: `12m`, `3h`, `Yesterday`, `Tue`, `Oct 2`.
String relativeShort(I18n i18n, String? value, {DateTime? now}) {
  final date = parseInstant(value);
  if (date == null) return '';
  final current = now ?? DateTime.now();
  final seconds = current.difference(date).inSeconds;
  if (seconds < 60) return i18n.t('mobile:time.now');
  if (seconds < 3600) return i18n.t('mobile:time.minutesShort', {'count': seconds ~/ 60});
  final days = _daysBetween(date, current);
  if (days == 0) return i18n.t('mobile:time.hoursShort', {'count': seconds ~/ 3600});
  if (days == 1) return i18n.t('mobile:time.yesterday');
  if (days < 7) return DateFormat.E(i18n.intlLocale).format(date);
  return formatDay(i18n, date, now: current);
}

/// `12 min ago`, `3 hr ago`, `Yesterday`, `Oct 2`.
String relativeLong(I18n i18n, String? value, {DateTime? now}) {
  final date = parseInstant(value);
  if (date == null) return '';
  final current = now ?? DateTime.now();
  final seconds = current.difference(date).inSeconds;
  if (seconds < 60) return i18n.t('mobile:time.justNow');
  if (seconds < 3600) return i18n.t('mobile:time.minutesAgo', {'count': seconds ~/ 60});
  final days = _daysBetween(date, current);
  if (days == 0) return i18n.t('mobile:time.hoursAgo', {'count': seconds ~/ 3600});
  if (days == 1) return i18n.t('mobile:time.yesterday');
  return formatDay(i18n, date, now: current);
}

/// The greeting for the time of day.
String greeting(I18n i18n, DateTime date) {
  final hour = date.hour;
  if (hour < 5) return i18n.t('mobile:time.goodEvening');
  if (hour < 12) return i18n.t('mobile:time.goodMorning');
  if (hour < 18) return i18n.t('mobile:time.goodAfternoon');
  return i18n.t('mobile:time.goodEvening');
}
