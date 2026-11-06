import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';

/// Waits for the current workspace, then builds the page for it. Shows the usual states until then.
class WorkspaceGate extends ConsumerWidget {
  const WorkspaceGate({super.key, required this.builder});

  final Widget Function(BuildContext context, Workspace workspace) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: ref.watch(currentWorkspaceProvider),
      onRetry: () => ref.read(workspacesQuery.notifier).refresh(),
      isEmpty: (workspace) => workspace == null,
      empty: StatusMessage(title: context.t('mobile:home.noWorkspace.title')),
      builder: (context, workspace) => builder(context, workspace!),
    );
  }
}
