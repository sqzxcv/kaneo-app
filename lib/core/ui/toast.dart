import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../layout/breakpoints.dart';
import '../theme/app_theme.dart';

enum ToastKind { info, success, error }

/// Lets code without a [BuildContext] show a toast. `KaneoApp` installs it.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The web app's toast on wide windows, in the corner, and the current app's above the tabs on
/// narrow ones. Only the icon carries the kind's color.
SnackBar _snackBar(BuildContext messenger, String message, ToastKind kind) {
  final window = MediaQuery.sizeOf(messenger);
  return SnackBar(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    margin: isWideSize(window)
        ? EdgeInsets.only(left: math.max(32, window.width - 360 - 32), right: 32, bottom: 32)
        : null,
    content: Builder(
      builder: (context) {
        final c = context.colors;
        final (icon, color) = switch (kind) {
          ToastKind.info => (LucideIcons.info, c.info),
          ToastKind.success => (LucideIcons.circleCheck, c.success),
          ToastKind.error => (LucideIcons.circleAlert, c.destructive),
        };
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        );
      },
    ),
  );
}

void _show(ScaffoldMessengerState? messenger, String message, ToastKind kind) {
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(_snackBar(messenger.context, message, kind));
}

/// Shows a short message that goes away by itself.
void showToast(BuildContext context, String message, {ToastKind kind = ToastKind.info}) {
  _show(ScaffoldMessenger.maybeOf(context) ?? rootMessengerKey.currentState, message, kind);
}

/// [showToast] for code that has no [BuildContext], such as the API client.
void showGlobalToast(String message, {ToastKind kind = ToastKind.info}) {
  _show(rootMessengerKey.currentState, message, kind);
}
