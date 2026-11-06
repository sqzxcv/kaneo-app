import 'package:flutter/widgets.dart';

import '../errors.dart';
import '../i18n/i18n.dart';
import 'toast.dart';

/// Runs a change the person asked for and reports the outcome as a toast. Resolves to the result,
/// or null if it failed. Failures are always shown here, so callers only handle success.
Future<T?> runAction<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
}) async {
  // Read before the gap: the page may be gone by the time the action finishes.
  final i18n = I18nScope.of(context);
  try {
    final result = await action();
    if (success != null && context.mounted) showToast(context, success, kind: ToastKind.success);
    return result;
  } catch (error) {
    final message = context.mounted
        ? userMessage(context, error)
        : i18n.t('mobile:common.somethingWrong');
    showGlobalToast(message, kind: ToastKind.error);
    return null;
  }
}
