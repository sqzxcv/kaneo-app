import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kaneo_app/core/core.dart';

/// A picker takes a snapshot, so wait for fresh choices and keep the auto-disposed query alive
/// until that request finishes. A cached snapshot can otherwise omit new labels or members.
Future<T> boardPickerData<T>(
  ProviderContainer container,
  AsyncNotifierProvider<CachedQuery<T>, T> query,
) async {
  final subscription = container.listen(query, (_, _) {});
  try {
    await container.read(query.future);
    await container.read(query.notifier).refresh();
    return await container.read(query.future);
  } finally {
    subscription.close();
  }
}
