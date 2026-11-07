import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/core/core.dart';
import 'package:kaneo_app/features/markdown/markdown_view.dart';

import '../support/test_app.dart';

/// Runs [open] from a button, returning what it resolved to after the test taps through it.
class _Runner<T> {
  T? result;
  bool finished = false;

  Widget button(Future<T> Function(BuildContext context) open) => Builder(
    builder: (context) => ElevatedButton(
      key: const ValueKey('open'),
      onPressed: () async {
        result = await open(context);
        finished = true;
      },
      child: const Text('open'),
    ),
  );
}

void main() {
  const columns = [
    ProjectColumn(id: 'c1', projectId: 'p', name: 'To Do', slug: 'to-do'),
    ProjectColumn(id: 'c2', projectId: 'p', name: 'Done', slug: 'done', isFinal: true),
  ];
  const members = [
    WorkspaceMember(id: 'u1', name: 'Ada', email: 'ada@example.com', role: 'owner'),
    WorkspaceMember(id: 'u2', name: 'Bo', email: 'bo@example.com', role: 'member'),
  ];

  Future<_Runner<T>> open<T>(
    WidgetTester tester,
    Size size,
    Future<T> Function(BuildContext context) action,
  ) async {
    final runner = _Runner<T>();
    await pumpInApp(tester, Center(child: runner.button(action)), size: size);
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    return runner;
  }

  testBothLayouts('showConfirm resolves true only when confirmed', (tester, size) async {
    final runner = await open<bool>(
      tester,
      size,
      (context) => showConfirm(context, title: 'Delete it?', message: 'Sure?', confirmLabel: 'Yes'),
    );
    expect(find.text('Delete it?'), findsOneWidget);
    expect(find.text('Sure?'), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(runner.result, isTrue);
  });

  testBothLayouts('showConfirm resolves false when cancelled', (tester, size) async {
    final runner = await open<bool>(
      tester,
      size,
      (context) => showConfirm(context, title: 'Delete it?', destructive: true),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(runner.result, isFalse);
  });

  testBothLayouts('showActionMenu resolves to the chosen value', (tester, size) async {
    final runner = await open<String?>(
      tester,
      size,
      (context) => showActionMenu<String>(
        context,
        items: const [
          MenuAction(value: 'copy', label: 'Copy'),
          MenuAction(value: 'delete', label: 'Delete', destructive: true),
          MenuAction(value: 'off', label: 'Unavailable', enabled: false),
        ],
      ),
    );
    await tester.tap(find.text('Unavailable'));
    await tester.pump();
    expect(runner.finished, isFalse);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(runner.result, 'delete');
  });

  testBothLayouts('pickOption marks the current choice and resolves to the new one', (
    tester,
    size,
  ) async {
    final runner = await open<Picked<String>?>(
      tester,
      size,
      (context) => pickOption<String>(
        context,
        title: 'Pick',
        selected: 'a',
        options: const [
          PickerOption(value: 'a', label: 'First'),
          PickerOption(value: 'b', label: 'Second', subtitle: 'More'),
        ],
      ),
    );
    expect(find.text('Pick'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(runner.result?.value, 'b');
  });

  testBothLayouts('pickMany resolves to the checked options on save', (tester, size) async {
    final runner = await open<Set<String>?>(
      tester,
      size,
      (context) => pickMany<String>(
        context,
        title: 'Pick',
        selected: const {'a'},
        options: const [
          PickerOption(value: 'a', label: 'First'),
          PickerOption(value: 'b', label: 'Second'),
        ],
      ),
    );
    await tester.tap(find.text('Second'));
    await tester.pump();
    await tester.tap(find.text('First'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(runner.result, {'b'});
  });

  testBothLayouts('pickStatus resolves to the column slug', (tester, size) async {
    final runner = await open<String?>(
      tester,
      size,
      (context) => pickStatus(context, columns: columns, current: 'to-do'),
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(runner.result, 'done');
  });

  testBothLayouts('pickPriority offers every priority', (tester, size) async {
    final runner = await open<String?>(
      tester,
      size,
      (context) => pickPriority(context, current: 'low'),
    );
    for (final label in ['No priority', 'Low', 'Medium', 'High', 'Urgent']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Urgent'));
    await tester.pumpAndSettle();
    expect(runner.result, 'urgent');
  });

  testBothLayouts('pickAssignee can unassign, which is different from dismissing', (
    tester,
    size,
  ) async {
    final runner = await open<Picked<String?>?>(
      tester,
      size,
      (context) => pickAssignee(context, members: members, current: 'u1'),
    );
    await tester.tap(find.text('Unassigned'));
    await tester.pumpAndSettle();
    expect(runner.finished, isTrue);
    expect(runner.result, isNotNull);
    expect(runner.result?.value, isNull);
  });

  testBothLayouts('pickLabels resolves to label ids', (tester, size) async {
    final runner = await open<Set<String>?>(
      tester,
      size,
      (context) => pickLabels(
        context,
        labels: const [
          Label(id: 'l1', name: 'bug', color: 'red'),
          Label(id: 'l2', name: 'ui', color: 'blue'),
        ],
        selectedIds: const {'l1'},
      ),
    );
    await tester.tap(find.text('ui'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(runner.result, {'l1', 'l2'});
  });

  testBothLayouts('pickDate resolves to local midnight', (tester, size) async {
    final runner = await open<Picked<DateTime?>?>(
      tester,
      size,
      (context) => pickDate(context, title: 'Due', current: DateTime(2026, 3, 9)),
    );
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    expect(runner.result?.value, DateTime(2026, 3, 15));
  });

  testBothLayouts('pickDate reports clearing separately from dismissing', (tester, size) async {
    final runner = await open<Picked<DateTime?>?>(
      tester,
      size,
      (context) => pickDate(context, title: 'Due', current: DateTime(2026, 3, 9)),
    );
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(runner.result, isNotNull);
    expect(runner.result?.value, isNull);
  });

  testBothLayouts('showToast shows a message that goes away by itself', (tester, size) async {
    await pumpInApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showToast(context, 'Saved', kind: ToastKind.success),
          child: const Text('go'),
        ),
      ),
      size: size,
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('Saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('showGlobalToast needs no context', (tester) async {
    await pumpInApp(tester, const SizedBox());
    showGlobalToast('From the client', kind: ToastKind.error);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('From the client'), findsOneWidget);
  });

  group('runAction', () {
    Future<void> press(
      WidgetTester tester,
      Future<int> Function() action, {
      String? success,
    }) async {
      await pumpInApp(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => runAction(context, action, success: success),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
    }

    testWidgets('shows the success message', (tester) async {
      await press(tester, () async => 1, success: 'Done it');
      expect(find.text('Done it'), findsOneWidget);
    });

    testWidgets('shows an API failure as its message', (tester) async {
      await press(tester, () async => throw const ApiError('Title is required', status: 400));
      expect(find.text('Title is required'), findsOneWidget);
    });

    testWidgets('shows any other failure as something readable', (tester) async {
      await press(tester, () async => throw StateError('internal detail'));
      expect(find.text('internal detail'), findsNothing);
      expect(find.text('Something went wrong'), findsOneWidget);
    });
  });

  group('AsyncBody', () {
    Widget body(AsyncValue<List<int>> value, {VoidCallback? onRetry}) => AsyncBody<List<int>>(
      value: value,
      onRetry: onRetry,
      isEmpty: (data) => data.isEmpty,
      empty: const StatusMessage(title: 'Nothing here'),
      builder: (context, data) => Text('data ${data.length}'),
    );

    testBothLayouts('loading', (tester, size) async {
      await pumpInApp(tester, body(const AsyncLoading()), size: size, settle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testBothLayouts('data', (tester, size) async {
      await pumpInApp(tester, body(const AsyncData([1, 2])), size: size);
      expect(find.text('data 2'), findsOneWidget);
    });

    testBothLayouts('empty', (tester, size) async {
      await pumpInApp(tester, body(const AsyncData([])), size: size);
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testBothLayouts('error with retry', (tester, size) async {
      var retried = 0;
      final app = await pumpInApp(
        tester,
        body(
          const AsyncError(ApiError('The server had a problem'), StackTrace.empty),
          onRetry: () => retried++,
        ),
        size: size,
      );
      expect(find.text('The server had a problem'), findsOneWidget);
      await tester.tap(find.text(app.i18n.t('mobile:common.retry')));
      expect(retried, 1);
    });

    testBothLayouts('no permission offers no retry', (tester, size) async {
      final app = await pumpInApp(
        tester,
        body(const AsyncError(ApiError('Nope', status: 403), StackTrace.empty), onRetry: () {}),
        size: size,
      );
      expect(find.text(app.i18n.t('mobile:errors.forbidden')), findsOneWidget);
      expect(find.text(app.i18n.t('mobile:common.retry')), findsNothing);
      expect(find.text('Nope'), findsNothing);
    });
  });

  testBothLayouts('MarkdownView renders the text', (tester, size) async {
    await pumpInApp(tester, const MarkdownView(data: '**Bold** text'), size: size);
    expect(find.textContaining('Bold'), findsWidgets);
    expect(find.textContaining('**'), findsNothing);
  });
}
