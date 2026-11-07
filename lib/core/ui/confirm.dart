import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../layout/breakpoints.dart';
import '../theme/app_theme.dart';
import 'popover.dart';

/// Asks before doing something, in a centered dialog on both layouts, like the web app's alert
/// dialog and the current app's confirmation. Resolves to true only when the person confirms.
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
    barrierColor: kaneoScrim,
    builder: (context) {
      final c = context.colors;
      final text = Theme.of(context).textTheme;
      final size = Size(0, context.isWide ? 32 : 40);
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          // The web app's `rounded-2xl`.
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 512),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.headlineMedium),
                      if (message != null) ...[
                        const SizedBox(height: 8),
                        Text(message, style: text.bodyMedium?.copyWith(color: c.mutedForeground)),
                      ],
                    ],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  // The web app's `bg-muted/72`.
                  color: c.muted.withValues(alpha: c.muted.a * 0.72),
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: size),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(cancelLabel ?? context.t('mobile:common.cancel')),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: size,
                          backgroundColor: destructive ? c.destructive : null,
                          foregroundColor: destructive ? const Color(0xFFFFFFFF) : null,
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(confirmLabel ?? context.t('mobile:common.save')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return confirmed ?? false;
}
