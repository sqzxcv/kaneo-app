import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';

/// Placeholder until KAN-10. Lists the projects of the current workspace.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider);
    return PlaceholderPage(
      title: context.t('mobile:nav.home'),
      actions: [
        IconButton(
          tooltip: context.t('mobile:home.search'),
          icon: const Icon(LucideIcons.search),
          onPressed: () => context.push(AppRoutes.search),
        ),
      ],
      child: AsyncBody(
        value: workspace,
        onRetry: () => ref.read(workspacesQuery.notifier).refresh(),
        isEmpty: (w) => w == null,
        empty: StatusMessage(title: context.t('mobile:home.noWorkspace.title')),
        builder: (context, current) => _Projects(workspaceId: current!.id),
      ),
    );
  }
}

class _Projects extends ConsumerWidget {
  const _Projects({required this.workspaceId});

  final String workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncBody(
      value: ref.watch(projectsQuery(workspaceId)),
      onRetry: () => ref.read(projectsQuery(workspaceId).notifier).refresh(),
      isEmpty: (projects) => projects.isEmpty,
      empty: StatusMessage(
        title: context.t('mobile:home.empty.title'),
        message: context.t('mobile:home.empty.message'),
      ),
      builder: (context, projects) => ListView(
        children: [
          for (final project in projects)
            ListTile(
              title: Text(project.name),
              subtitle: Text(project.slug),
              onTap: () => context.push(AppRoutes.board(project.id)),
            ),
        ],
      ),
    );
  }
}
