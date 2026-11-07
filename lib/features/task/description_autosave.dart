import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../core/core.dart';

/// How long typing has to stop before the text is saved.
const descriptionSaveDelay = Duration(seconds: 1);

enum DescriptionSaveStatus { idle, saving, saved, failed }

/// Decides when a description goes to the server.
///
/// Text is sent exactly as given, and only if it differs from what the server holds, so a person
/// who opens the text box and leaves changes nothing. Requests never overlap, which keeps an older
/// text from arriving after a newer one. A failed text stays here until a later save succeeds.
class DescriptionAutosave extends ChangeNotifier {
  DescriptionAutosave({
    required this._send,
    this._onSaved,
    this._onFailed,
    this._delay = descriptionSaveDelay,
  });

  final Future<void> Function(String text) _send;
  final void Function(String text)? _onSaved;
  final void Function(Object error)? _onFailed;
  final Duration _delay;

  String? _saved;
  String? _pending;
  String? _sending;
  DescriptionSaveStatus _outcome = DescriptionSaveStatus.idle;
  Timer? _timer;
  bool _running = false;
  bool _flushAgain = false;
  bool _disposed = false;

  DescriptionSaveStatus get status {
    if (_sending != null) return DescriptionSaveStatus.saving;
    if (_outcome == DescriptionSaveStatus.saved && hasUnsaved) return DescriptionSaveStatus.idle;
    return _outcome;
  }

  /// Whether some text has not reached the server yet.
  bool get hasUnsaved => _sending != null || (_pending != null && _pending != _saved);

  /// The newest text that has not reached the server, or null when there is none.
  String? get unsavedText => hasUnsaved ? _pending ?? _sending : null;

  /// Records what the server holds. Call when opening the text box on text nobody has changed yet.
  void begin(String saved) {
    _saved = saved;
    _outcome = DescriptionSaveStatus.idle;
    _notify();
  }

  /// Records what is in the text box. It goes out after [_delay] without another change.
  ///
  /// [composing] means an input method has not confirmed part of the text. Pinyin in progress is not
  /// content, so the wait restarts when the input method finishes. [flush] still sends it, because
  /// by then the person has left and what they see is all there is.
  void edit(String text, {bool composing = false}) {
    if (_disposed) return;
    _pending = text;
    _timer?.cancel();
    if (!composing) _timer = Timer(_delay, flush);
    _notify();
  }

  /// Saves now instead of waiting. Never throws; a failure is reported through `onFailed`.
  Future<void> flush() async {
    if (_disposed) return;
    _timer?.cancel();
    if (_running) {
      _flushAgain = true;
      return;
    }
    _running = true;
    try {
      do {
        _flushAgain = false;
        final text = _pending;
        if (text == null) break;
        _pending = null;
        if (text == _saved) {
          if (_outcome == DescriptionSaveStatus.failed) _outcome = DescriptionSaveStatus.idle;
          break;
        }
        _sending = text;
        _notify();
        try {
          await _send(text);
        } catch (error) {
          _sending = null;
          // Newer text typed during the request wins, and keeps its own timer.
          _pending ??= text;
          _outcome = DescriptionSaveStatus.failed;
          if (!_disposed) _onFailed?.call(error);
          break;
        }
        _sending = null;
        _saved = text;
        _outcome = DescriptionSaveStatus.saved;
        if (!_disposed) _onSaved?.call(text);
      } while (_flushAgain && !_disposed);
    } finally {
      _running = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// One per task and account. It stays alive while it holds unsaved text, so a save that fails after
/// the page closed still has the text when the task is opened again. This lasts until the app exits.
final descriptionAutosaveProvider = Provider.autoDispose.family<DescriptionAutosave, String>((
  ref,
  taskId,
) {
  // Text typed under one account must never be sent under the next.
  ref.watch(sessionProvider);
  final api = ref.watch(kaneoApiProvider);
  final saver = DescriptionAutosave(
    send: (text) => api.updateDescription(taskId, text),
    onSaved: (text) {
      final query = taskQuery(taskId);
      final notifier = ref.read(query.notifier);
      final current = ref.read(query).value;
      if (current == null) return;
      notifier.setData(current.copyWith(description: text, descriptionDeferred: false));
    },
    onFailed: (error) {
      // The client has already said why, and is on its way to the login page.
      if (error is ApiError && error.status == 401) return;
      final i18n = ref.read(i18nProvider);
      final reason = error is ApiError ? error.message : i18n.t('mobile:common.somethingWrong');
      showGlobalToast(
        i18n.t('app:description.saveFailed', {'reason': reason}),
        kind: ToastKind.error,
      );
    },
  );
  KeepAliveLink? keepAlive;
  saver.addListener(() {
    if (saver.hasUnsaved) {
      keepAlive ??= ref.keepAlive();
    } else {
      keepAlive?.close();
      keepAlive = null;
    }
  });
  ref.onDispose(saver.dispose);
  return saver;
});
