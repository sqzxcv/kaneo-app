import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors.dart';
import '../i18n/i18n.dart';

/// A centered message with an optional action, for empty and failed pages.
class StatusMessage extends StatelessWidget {
  const StatusMessage({super.key, required this.title, this.message, this.action});

  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: text.titleSmall, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(message!, style: text.bodySmall, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Renders a query's loading, error, no-permission, empty and data states.
///
/// Data on hand always wins: a refresh in progress, or one that failed, keeps it on screen.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.isEmpty,
    this.empty,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;

  /// Shows a retry button with the error.
  final VoidCallback? onRetry;

  /// Decides whether [empty] replaces the data.
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) {
      final data = value.requireValue;
      if (empty != null && (isEmpty?.call(data) ?? false)) return empty!;
      return builder(context, data);
    }
    if (value.hasError) {
      return StatusMessage(
        title: isForbidden(value.error)
            ? context.t('mobile:errors.forbidden')
            : context.t('mobile:ui.loadFailed'),
        message: isForbidden(value.error) ? null : userMessage(context, value.error),
        action: onRetry == null || isForbidden(value.error)
            ? null
            : OutlinedButton(onPressed: onRetry, child: Text(context.t('mobile:common.retry'))),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}
