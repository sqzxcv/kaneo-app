import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaneo_app/features/task/description_autosave.dart';

/// A saver with a request the test finishes by hand. `testWidgets` is only here for its fake clock.
class _Harness {
  _Harness() {
    saver = DescriptionAutosave(
      send: (text) {
        sent.add(text);
        final request = Completer<void>();
        requests.add(request);
        return request.future;
      },
      onSaved: saved.add,
      onFailed: failures.add,
    )..begin('original');
    addTearDown(saver.dispose);
  }

  late final DescriptionAutosave saver;
  final sent = <String>[];
  final requests = <Completer<void>>[];
  final saved = <String>[];
  final failures = <Object>[];
}

void main() {
  testWidgets('sends one second after the last change, and not before', (tester) async {
    final h = _Harness();
    h.saver.edit('a');
    await tester.pump(descriptionSaveDelay - const Duration(milliseconds: 100));
    h.saver.edit('ab');
    await tester.pump(descriptionSaveDelay - const Duration(milliseconds: 100));
    expect(h.sent, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(h.sent, ['ab']);
  });

  testWidgets('sends exactly the text it was given', (tester) async {
    final h = _Harness();
    const text = '  # Title  \r\n\r\n\t- item \n\n\n';
    h.saver.edit(text);
    unawaited(h.saver.flush());
    expect(h.sent, [text]);
  });

  testWidgets('sends nothing when the text is what the server holds', (tester) async {
    final h = _Harness();
    await h.saver.flush();
    h.saver.edit('changed');
    h.saver.edit('original');
    await tester.pump(descriptionSaveDelay);
    await h.saver.flush();
    expect(h.sent, isEmpty);
    expect(h.saver.hasUnsaved, isFalse);
  });

  testWidgets('going back to the old text after a save is a change', (tester) async {
    final h = _Harness();
    h.saver.edit('changed');
    unawaited(h.saver.flush());
    h.requests.single.complete();
    await tester.pump();
    h.saver.edit('original');
    unawaited(h.saver.flush());
    expect(h.sent, ['changed', 'original']);
  });

  testWidgets('requests never overlap, and the newest text goes last', (tester) async {
    final h = _Harness();
    h.saver.edit('one');
    await tester.pump(descriptionSaveDelay);
    expect(h.sent, ['one']);

    h.saver.edit('two');
    await tester.pump(descriptionSaveDelay);
    h.saver.edit('three');
    await tester.pump(descriptionSaveDelay);
    expect(h.sent, ['one'], reason: 'The first request is still out.');

    h.requests.first.complete();
    await tester.pump();
    expect(h.sent, ['one', 'three'], reason: '"two" was replaced before it could go.');
    h.requests.last.complete();
    await tester.pump();
    expect(h.saved, ['one', 'three']);
    expect(h.saver.hasUnsaved, isFalse);
  });

  testWidgets('text typed during a request waits for its own delay', (tester) async {
    final h = _Harness();
    h.saver.edit('one');
    unawaited(h.saver.flush());
    h.saver.edit('two');
    h.requests.single.complete();
    await tester.pump();
    expect(h.sent, ['one']);
    expect(h.saver.unsavedText, 'two');
    await tester.pump(descriptionSaveDelay);
    expect(h.sent, ['one', 'two']);
  });

  testWidgets('a second flush during a request does not send twice', (tester) async {
    final h = _Harness();
    h.saver.edit('one');
    unawaited(h.saver.flush());
    unawaited(h.saver.flush());
    unawaited(h.saver.flush());
    h.requests.single.complete();
    await tester.pump();
    expect(h.sent, ['one']);
  });

  group('when a request fails', () {
    testWidgets('keeps the text and reports the failure once', (tester) async {
      final h = _Harness();
      h.saver.edit('one');
      unawaited(h.saver.flush());
      expect(h.saver.status, DescriptionSaveStatus.saving);
      h.requests.single.completeError(StateError('down'));
      await tester.pump();
      expect(h.failures, hasLength(1));
      expect(h.saved, isEmpty);
      expect(h.saver.status, DescriptionSaveStatus.failed);
      expect(h.saver.unsavedText, 'one');
      await tester.pump(const Duration(minutes: 1));
      expect(h.sent, ['one'], reason: 'It waits for a change or a flush.');
    });

    testWidgets('a retry sends the kept text', (tester) async {
      final h = _Harness();
      h.saver.edit('one');
      unawaited(h.saver.flush());
      h.requests.single.completeError(StateError('down'));
      await tester.pump();

      unawaited(h.saver.flush());
      expect(h.sent, ['one', 'one']);
      h.requests.last.complete();
      await tester.pump();
      expect(h.saver.status, DescriptionSaveStatus.saved);
      expect(h.saver.hasUnsaved, isFalse);
    });

    testWidgets('text typed during the request is not replaced by the failed text', (tester) async {
      final h = _Harness();
      h.saver.edit('one');
      unawaited(h.saver.flush());
      h.saver.edit('two');
      h.requests.single.completeError(StateError('down'));
      await tester.pump();
      expect(h.saver.unsavedText, 'two');
      await tester.pump(descriptionSaveDelay);
      expect(h.sent, ['one', 'two']);
    });

    testWidgets('a flush asked for during the request does not retry by itself', (tester) async {
      final h = _Harness();
      h.saver.edit('one');
      unawaited(h.saver.flush());
      unawaited(h.saver.flush());
      h.requests.single.completeError(StateError('down'));
      await tester.pump();
      expect(h.sent, ['one']);
      expect(h.failures, hasLength(1));
    });

    testWidgets('going back to the old text clears the failure', (tester) async {
      final h = _Harness();
      h.saver.edit('one');
      unawaited(h.saver.flush());
      h.requests.single.completeError(StateError('down'));
      await tester.pump();

      h.saver.edit('original');
      await h.saver.flush();
      expect(h.sent, ['one']);
      expect(h.saver.status, DescriptionSaveStatus.idle);
      expect(h.saver.hasUnsaved, isFalse);
    });
  });

  group('while an input method is composing', () {
    testWidgets('does not send, however long it takes', (tester) async {
      final h = _Harness();
      h.saver.edit('ni', composing: true);
      await tester.pump(const Duration(minutes: 1));
      expect(h.sent, isEmpty);
      expect(h.saver.hasUnsaved, isTrue);
    });

    testWidgets('composing cancels the wait for earlier text', (tester) async {
      final h = _Harness();
      h.saver.edit('confirmed');
      await tester.pump(const Duration(milliseconds: 500));
      h.saver.edit('confirmed ni', composing: true);
      await tester.pump(const Duration(minutes: 1));
      expect(h.sent, isEmpty);
    });

    testWidgets('sends the confirmed text a second after composing ends', (tester) async {
      final h = _Harness();
      h.saver.edit('ni', composing: true);
      await tester.pump(const Duration(seconds: 5));
      h.saver.edit('你');
      await tester.pump(descriptionSaveDelay);
      expect(h.sent, ['你']);
    });

    testWidgets('a flush still sends what is on screen, so leaving loses nothing', (tester) async {
      final h = _Harness();
      h.saver.edit('ni', composing: true);
      unawaited(h.saver.flush());
      expect(h.sent, ['ni']);
    });
  });

  testWidgets('status follows the save', (tester) async {
    final h = _Harness();
    expect(h.saver.status, DescriptionSaveStatus.idle);
    h.saver.edit('one');
    expect(h.saver.status, DescriptionSaveStatus.idle);
    expect(h.saver.unsavedText, 'one');
    unawaited(h.saver.flush());
    expect(h.saver.status, DescriptionSaveStatus.saving);
    expect(h.saver.unsavedText, 'one');
    h.requests.single.complete();
    await tester.pump();
    expect(h.saver.status, DescriptionSaveStatus.saved);
    expect(h.saver.unsavedText, isNull);
    h.saver.edit('two');
    expect(h.saver.status, DescriptionSaveStatus.idle, reason: 'The new text is not saved yet.');
    await tester.pump(descriptionSaveDelay);
  });

  testWidgets('a finished request is not called saved while newer text waits', (tester) async {
    final h = _Harness();
    h.saver.edit('one');
    unawaited(h.saver.flush());
    h.saver.edit('one two', composing: true);
    h.requests.single.complete();
    await tester.pump();
    expect(h.saver.status, DescriptionSaveStatus.idle);
    expect(h.saver.unsavedText, 'one two');
  });

  testWidgets('sends nothing after being disposed', (tester) async {
    final sent = <String>[];
    final saver = DescriptionAutosave(send: (text) async => sent.add(text))..begin('original');
    saver.edit('changed');
    saver.dispose();
    await tester.pump(descriptionSaveDelay);
    await saver.flush();
    saver.edit('later');
    await tester.pump(descriptionSaveDelay);
    expect(sent, isEmpty);
  });
}
