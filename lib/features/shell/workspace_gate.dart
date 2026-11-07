import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';

/// Waits for the current workspace, then builds the page for it. Shows the usual states until then.
///
/// With no workspace at all it points to the web app, the only place to get one for now.
class WorkspaceGate extends ConsumerWidget {
  const WorkspaceGate({super.key, required this.builder});

  final Widget Function(BuildContext context, Workspace workspace) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void reload() => ref.read(workspacesQuery.notifier).refresh();
    return AsyncBody(
      value: ref.watch(currentWorkspaceProvider),
      onRetry: reload,
      isEmpty: (workspace) => workspace == null,
      empty: StatusMessage(
        title: context.t('mobile:home.noWorkspace.title'),
        message: context.t('app:home.noWorkspaceOnWeb'),
        action: OutlinedButton(onPressed: reload, child: Text(context.t('mobile:common.retry'))),
      ),
      builder: (context, workspace) => builder(context, workspace!),
    );
  }
}
