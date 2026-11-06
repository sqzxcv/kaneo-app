import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

/// Asks before doing something. Resolves to true only when the person confirms.
///
/// [destructive] marks the confirm button as dangerous.
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel ?? context.t('mobile:common.cancel')),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel ?? context.t('mobile:common.save')),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
