import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../shell/workspace_gate.dart';

/// Placeholder until KAN-38.
class InboxPage extends ConsumerWidget {
  const InboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlaceholderPage(
      title: context.t('mobile:nav.inbox'),
      child: ContentWidth(
        child: WorkspaceGate(
          builder: (context, workspace) {
            final query = notificationsQuery(workspace.id);
            return AsyncBody(
              value: ref.watch(query),
              onRetry: () => ref.read(query.notifier).refresh(),
              isEmpty: (items) => items.isEmpty,
              empty: StatusMessage(title: context.t('mobile:inbox.empty.title')),
              builder: (context, items) => ListView(
                children: [
                  ListTile(title: Text(context.t('app:list.count', {'count': items.length}))),
                  for (final item in items)
                    ListTile(
                      title: Text(item.title ?? item.type),
                      subtitle: Text(item.content ?? ''),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
