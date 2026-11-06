import 'package:flutter/widgets.dart';

import 'api/api_client.dart';
import 'i18n/i18n.dart';

/// Turns any failure into a message fit to show a person.
String userMessage(BuildContext context, Object? error) {
  if (error is ApiError) return error.message;
  return context.t('mobile:common.somethingWrong');
}

/// Whether the failure means this account may not see or do the thing, rather than that it broke.
bool isForbidden(Object? error) => error is ApiError && error.status == 403;
