import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';

/// The web app's sidebar width.
const double sidebarWidth = 256;

const double _rowHeight = 32;

/// The left side of wide windows, after the web app's `AppSidebar`: the workspace, the main pages,
/// the projects and the account.
///
/// Failures stay short here and never use the page's wording or spinner: the page next to it is
/// usually showing the same failure in full.
class AppSidebar extends ConsumerStatefulWidget {
  const AppSidebar({super.key, required this.location});

  final Uri location;

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  @override
  void didUpdateWidget(AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location.path != widget.location.path) scheduleMicrotask(_refresh);
  }

  /// A page's queries refresh each time the page opens, because they are released when it closes.
  /// The sidebar holds on to these two for as long as it is on screen, so it refreshes them itself
  /// when the person moves between pages. Otherwise a project added on the web would never appear.
  void _refresh() {
    if (!mounted) return;
    if (ref.read(workspacesQuery).hasValue) {
      unawaited(ref.read(workspacesQuery.notifier).refresh());
    }
    final workspace = ref.read(currentWorkspaceProvider).value;
    if (workspace == null) return;
    final projects = projectsQuery(workspace.id);
    if (ref.read(projects).hasValue) unawaited(ref.read(projects.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.location.path;

    Widget destination(String route, String labelKey, IconData icon) => _SidebarRow(
      icon: icon,
      label: context.t(labelKey),
      selected: path == route,
      onTap: () => context.go(route),
    );

    return SizedBox(
      width: sidebarWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(8, 8, 8, 4), child: _WorkspaceHeader()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                destination(AppRoutes.home, 'navigation:sidebar.home', LucideIcons.house),
                destination(AppRoutes.inbox, 'navigation:sidebar.inbox', LucideIcons.inbox),
                destination(
                  AppRoutes.myTasks,
                  'navigation:sidebar.myTasks',
                  LucideIcons.circleCheck,
                ),
                destination(AppRoutes.activity, 'mobile:nav.activity', LucideIcons.activity),
              ],
            ),
          ),
          Expanded(child: _Projects(path: path)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: destination(AppRoutes.account, 'mobile:home.account', LucideIcons.user),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceHeader extends ConsumerWidget {
  const _WorkspaceHeader();

  Future<void> _switch(BuildContext context, WidgetRef ref, Workspace current) async {
    // Taken up front: the window can turn narrow, and take the sidebar away, while this is open.
    final selection = ref.read(selectedWorkspaceIdProvider.notifier);
    final router = GoRouter.of(context);
    final picked = await pickOption<String>(
      context,
      title: context.t('navigation:workspaceSwitcher.workspaces'),
      selected: current.id,
      options: [
        for (final workspace in ref.read(workspacesQuery).value ?? const <Workspace>[])
          PickerOption(value: workspace.id, label: workspace.name),
      ],
    );
    if (picked == null || picked.value == current.id) return;
    await selection.select(picked.value);
    // The open page may belong to the workspace just left.
    router.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(currentWorkspaceProvider);
    final current = value.value;
    final Widget switcher;
    if (current != null) {
      switcher = Semantics(
        label: context.t('mobile:home.switchWorkspace'),
        child: _SidebarRow(
          label: current.name,
          strong: true,
          trailing: Icon(LucideIcons.chevronDown, size: 14, color: context.colors.foreground),
          onTap: () => _switch(context, ref, current),
        ),
      );
    } else if (value.hasError && !value.hasValue) {
      switcher = _SidebarNotice(
        message: context.t('app:shell.workspaceUnavailable'),
        onRetry: isForbidden(value.error)
            ? null
            : () => ref.read(workspacesQuery.notifier).refresh(),
      );
    } else {
      // Loading, or no workspace at all, which the page next to it explains.
      switcher = value.isLoading ? const _SkeletonRow() : const SizedBox(height: _rowHeight);
    }
    return Row(
      children: [
        Expanded(child: switcher),
        const SizedBox(width: 4),
        _SidebarIconButton(
          icon: LucideIcons.search,
          tooltip: context.t('mobile:home.search'),
          onPressed: () => context.go(AppRoutes.search),
        ),
      ],
    );
  }
}

class _Projects extends ConsumerWidget {
  const _Projects({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(currentWorkspaceProvider).value;
    if (workspace == null) return const SizedBox.shrink();
    final query = projectsQuery(workspace.id);
    final projects = ref.watch(query);
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            context.t('navigation:sidebar.projects'),
            style: Theme.of(context).textTheme.labelMedium!
                .copyWith(color: context.colors.sidebarAccentForeground),
          ),
        ),
        if (projects.hasValue) ...[
          if (projects.requireValue.isEmpty)
            _SidebarNotice(message: context.t('app:shell.noProjects')),
          for (final project in projects.requireValue)
            _SidebarRow(
              icon: projectIcon(project.icon),
              label: project.name,
              selected: path == AppRoutes.board(project.id),
              onTap: () => context.go(AppRoutes.board(project.id)),
            ),
        ] else if (projects.hasError)
          _SidebarNotice(
            message: context.t('app:shell.projectsUnavailable'),
            onRetry: isForbidden(projects.error) ? null : () => ref.read(query.notifier).refresh(),
          )
        else
          for (var i = 0; i < 3; i++) const _SkeletonRow(),
      ],
    );
  }
}

/// A row of the sidebar. Takes the sidebar's colors for hover, focus and the current page.
class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing,
    this.selected = false,
    this.strong = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? trailing;
  final bool selected;

  /// Uses the page's text color even when not selected, as the workspace name does.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = strong
        ? c.foreground
        : selected
        ? c.sidebarAccentForeground
        : c.sidebarForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        child: Material(
          color: selected ? c.sidebarAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(KaneoRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: c.sidebarAccent,
            focusColor: c.sidebarAccent,
            highlightColor: c.sidebarAccent,
            splashFactory: NoSplash.splashFactory,
            child: SizedBox(
              height: _rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: color,
                          fontWeight: selected || strong ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarIconButton extends StatelessWidget {
  const _SidebarIconButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: c.sidebarForeground),
      constraints: const BoxConstraints.tightFor(width: _rowHeight, height: _rowHeight),
      padding: EdgeInsets.zero,
      hoverColor: c.sidebarAccent,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KaneoRadius.md)),
      ),
    );
  }
}

/// A short line in place of a list, with a retry button when trying again can help.
class _SidebarNotice extends StatelessWidget {
  const _SidebarNotice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (onRetry != null)
              _SidebarIconButton(
                icon: LucideIcons.rotateCw,
                tooltip: context.t('mobile:common.retry'),
                onPressed: onRetry!,
              ),
          ],
        ),
      ),
    );
  }
}

/// Holds a row's place while its data loads.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight + 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.sidebarAccent,
            borderRadius: BorderRadius.circular(KaneoRadius.sm),
          ),
        ),
      ),
    );
  }
}
