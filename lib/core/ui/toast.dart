import 'package:flutter/material.dart';

enum ToastKind { info, success, error }

/// Lets code without a [BuildContext] show a toast. `KaneoApp` installs it.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

SnackBar _snackBar(String message, ToastKind kind) => SnackBar(
  content: Builder(
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return Text(message, style: kind == ToastKind.error ? TextStyle(color: scheme.error) : null);
    },
  ),
);

/// Shows a short message that goes away by itself.
void showToast(BuildContext context, String message, {ToastKind kind = ToastKind.info}) {
  final messenger = ScaffoldMessenger.maybeOf(context) ?? rootMessengerKey.currentState;
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(_snackBar(message, kind));
}

/// [showToast] for code that has no [BuildContext], such as the API client.
void showGlobalToast(String message, {ToastKind kind = ToastKind.info}) {
  rootMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(_snackBar(message, kind));
}
