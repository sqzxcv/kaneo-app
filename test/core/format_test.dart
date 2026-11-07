import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';

import '../support/test_app.dart';

void main() {
  late I18n i18n;

  setUpAll(() async {
    i18n = await I18n.load(read: readCatalogFile);
  });

  final now = DateTime(2026, 3, 9, 12);

  group('parsing dates', () {
    test('a bare date is that calendar day here', () {
      expect(parseDay('2026-03-09'), DateTime(2026, 3, 9));
      expect(parseInstant('2026-03-09'), DateTime(2026, 3, 9));
    });

    test('an instant is converted to local time', () {
      final instant = DateTime(2026, 3, 9, 23, 30);
      expect(parseInstant(instant.toUtc().toIso8601String()), instant);
      expect(parseDay(instant.toUtc().toIso8601String()), DateTime(2026, 3, 9));
    });

    test('empty and invalid values are null', () {
      expect(parseDay(null), isNull);
      expect(parseDay(''), isNull);
      expect(parseInstant('not a date'), isNull);
    });

    test('toApiDate sends local midnight as an instant', () {
      final sent = toApiDate(DateTime(2026, 3, 9, 15));
      expect(DateTime.parse(sent).toLocal(), DateTime(2026, 3, 9));
      expect(sent, endsWith('Z'));
    });
  });

  group('formatting dates, as the mobile app does', () {
    test('formatDay shows the year only when it is not this year', () {
      expect(formatDay(i18n, DateTime(2026, 3, 9), now: now), 'Mar 9');
      expect(formatDay(i18n, DateTime(2025, 3, 9), now: now), 'Mar 9, 2025');
    });

    test('formatLongDate', () {
      expect(formatLongDate(i18n, DateTime(2026, 3, 9)), 'Monday, March 9');
    });

    test('formatDateTime', () {
      expect(
        formatDateTime(i18n, DateTime(2026, 3, 9, 12, 30).toUtc().toIso8601String(), now: now),
        'Mar 9 12:30',
      );
      expect(formatDateTime(i18n, null, now: now), '');
    });

    test('formatDueShort', () {
      expect(formatDueShort(i18n, '2026-03-09', now: now), 'Today');
      expect(formatDueShort(i18n, '2026-03-10', now: now), 'Tomorrow');
      expect(formatDueShort(i18n, '2026-03-11', now: now), 'Wed, Mar 11');
      expect(formatDueShort(i18n, '2026-04-11', now: now), 'Apr 11');
      expect(formatDueShort(i18n, null, now: now), '');
    });

    test('relativeShort', () {
      String at(DateTime date) => relativeShort(i18n, date.toUtc().toIso8601String(), now: now);
      expect(at(DateTime(2026, 3, 9, 11, 59, 30)), i18n.t('mobile:time.now'));
      expect(at(DateTime(2026, 3, 9, 11, 48)), '12m');
      expect(at(DateTime(2026, 3, 9, 9)), '3h');
      expect(at(DateTime(2026, 3, 8, 9)), i18n.t('mobile:time.yesterday'));
      expect(at(DateTime(2026, 3, 6, 9)), 'Fri');
      expect(at(DateTime(2026, 2, 6, 9)), 'Feb 6');
    });

    test('relativeLong', () {
      String at(DateTime date) => relativeLong(i18n, date.toUtc().toIso8601String(), now: now);
      expect(at(DateTime(2026, 3, 9, 11, 59, 30)), i18n.t('mobile:time.justNow'));
      expect(at(DateTime(2026, 3, 9, 9)), '3 hr ago');
      expect(at(DateTime(2026, 3, 8, 9)), i18n.t('mobile:time.yesterday'));
      expect(at(DateTime(2026, 2, 6, 9)), 'Feb 6');
    });

    test('dates follow the active language', () async {
      final chinese = await I18n.load(locale: 'zh-CN', read: readCatalogFile);
      expect(formatLongDate(chinese, DateTime(2026, 3, 9)), contains('3月9日'));
      expect(formatDueShort(chinese, '2026-03-09', now: now), chinese.t('mobile:time.today'));
    });

    test('overdue counts whole local days', () {
      expect(isOverdue('2026-03-09', now: now), isFalse);
      expect(isOverdue('2026-03-08', now: now), isTrue);
      expect(daysOverdue('2026-03-06', now: now), 3);
      expect(daysOverdue('2026-03-10', now: now), 0);
      expect(daysOverdue(null, now: now), 0);
    });

    test('greeting depends on the hour', () {
      expect(greeting(i18n, DateTime(2026, 3, 9, 4)), i18n.t('mobile:time.goodEvening'));
      expect(greeting(i18n, DateTime(2026, 3, 9, 9)), i18n.t('mobile:time.goodMorning'));
      expect(greeting(i18n, DateTime(2026, 3, 9, 13)), i18n.t('mobile:time.goodAfternoon'));
      expect(greeting(i18n, DateTime(2026, 3, 9, 20)), i18n.t('mobile:time.goodEvening'));
    });

    test('the greeting changes exactly at the hours it is told', () {
      expect(greeting(i18n, DateTime(2026, 3, 9, 4, 59)), i18n.t('mobile:time.goodEvening'));
      expect(greeting(i18n, DateTime(2026, 3, 9, 5)), i18n.t('mobile:time.goodMorning'));
      expect(greeting(i18n, DateTime(2026, 3, 9, 11, 59)), i18n.t('mobile:time.goodMorning'));
      expect(greeting(i18n, DateTime(2026, 3, 9, 12)), i18n.t('mobile:time.goodAfternoon'));
      expect(greeting(i18n, DateTime(2026, 3, 9, 17, 59)), i18n.t('mobile:time.goodAfternoon'));
      expect(greeting(i18n, DateTime(2026, 3, 9, 18)), i18n.t('mobile:time.goodEvening'));
    });

    group('nextGreetingOrDayChange', () {
      test('is the next greeting of the day', () {
        expect(nextGreetingOrDayChange(DateTime(2026, 3, 9)), DateTime(2026, 3, 9, 5));
        expect(nextGreetingOrDayChange(DateTime(2026, 3, 9, 4, 59, 59)), DateTime(2026, 3, 9, 5));
        expect(nextGreetingOrDayChange(DateTime(2026, 3, 9, 11)), DateTime(2026, 3, 9, 12));
        expect(nextGreetingOrDayChange(DateTime(2026, 3, 9, 17)), DateTime(2026, 3, 9, 18));
      });

      test('is always later than now, even exactly at a change', () {
        expect(nextGreetingOrDayChange(DateTime(2026, 3, 9, 5)), DateTime(2026, 3, 9, 12));
        expect(nextGreetingOrDayChange(DateTime(2026, 3, 9, 12)), DateTime(2026, 3, 9, 18));
        expect(nextGreetingOrDayChange(DateTime(2026, 3, 9, 18)), DateTime(2026, 3, 10));
      });

      test('is midnight in the evening, across months and years', () {
        expect(nextGreetingOrDayChange(DateTime(2026, 3, 9, 23, 59)), DateTime(2026, 3, 10));
        expect(nextGreetingOrDayChange(DateTime(2026, 2, 28, 20)), DateTime(2026, 3, 1));
        expect(nextGreetingOrDayChange(DateTime(2026, 12, 31, 20)), DateTime(2027, 1, 1));
      });
    });
  });

  group('style helpers', () {
    test('ticketId', () {
      expect(ticketId('kan', 12), 'KAN-12');
      expect(ticketId(null, 12), '#12');
      expect(ticketId('kan', null), '');
    });

    test('initials', () {
      expect(initials('Ada Byron Lovelace'), 'AL');
      expect(initials('ada'), 'AD');
      expect(initials(null), '?');
      expect(initials('   '), '?');
      expect(initials('张三'), '张三');
    });

    test('labelColor knows the palette and hex values', () {
      expect(labelColor('red'), const Color(0xFFE7000B));
      expect(labelColor('#fff'), const Color(0xFFFFFFFF));
      expect(labelColor('#112233'), const Color(0xFF112233));
      expect(labelColor('#11223344'), const Color(0x44112233));
      expect(labelColor('nonsense'), const Color(0xFFA1A1A1));
      expect(labelColor(null), const Color(0xFFA1A1A1));
    });

    testWidgets('priorityLabel translates and falls back to no priority', (tester) async {
      late BuildContext context;
      await pumpInApp(
        tester,
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      expect(priorityLabel(context, 'urgent'), 'Urgent');
      expect(priorityLabel(context, null), 'No priority');
      expect(priorities, ['no-priority', 'low', 'medium', 'high', 'urgent']);
    });
  });

  group('wide or narrow', () {
    test('goes by the shorter side, at 600', () {
      expect(isWideSize(const Size(1366, 1024)), isTrue);
      expect(isWideSize(const Size(1024, 1366)), isTrue);
      expect(isWideSize(const Size(600, 600)), isTrue);
      expect(isWideSize(const Size(599, 1000)), isFalse);
      expect(isWideSize(const Size(390, 844)), isFalse);
      expect(isWideSize(const Size(844, 390)), isFalse);
    });
  });
}
