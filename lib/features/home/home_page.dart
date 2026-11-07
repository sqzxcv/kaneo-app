import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import '../shell/page_return.dart';
import '../shell/workspace_gate.dart';
import '../shell/workspace_switch.dart';

/// How wide the page grows, the web app's `max-w-5xl`.
const double _pageMaxWidth = 1024;

/// Wide windows lay the cards out like the web app's three-column grid. Windows too small for that
/// next to the sidebar use fewer columns, so that a card always has room for its name.
const int _maxCardColumns = 3;
const double _minCardWidth = 180;
const double _cardGap = 12;

/// Archived projects are dimmed, like in the current app.
const double _archivedOpacity = 0.6;

/// Marks a project on the home page, as a card or as a row.
ValueKey<String> homeProjectKey(String projectId) => ValueKey('home-project-$projectId');

/// The date, a greeting and the projects of the current workspace. Wide windows follow the web
/// app's home page and have the workspace switcher in the sidebar. Narrow ones follow the current
/// app and have it in the bar.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = context.isWide;
    final workspace = ref.watch(currentWorkspaceProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: wide
            ? Text(context.t('mobile:nav.home'))
            : workspace == null
            ? null
            : _WorkspaceButton(current: workspace),
        // Wide windows have these in the sidebar.
        actions: wide
            ? null
            : [
                IconButton(
                  tooltip: context.t('mobile:home.search'),
                  icon: const Icon(LucideIcons.search),
                  onPressed: () => context.push(AppRoutes.search),
                ),
                IconButton(
                  tooltip: context.t('mobile:home.account'),
                  icon: const Icon(LucideIcons.user),
                  onPressed: () => context.push(AppRoutes.account),
                ),
              ],
      ),
      body: WorkspaceGate(builder: (context, workspace) => _HomeBody(workspaceId: workspace.id)),
    );
  }
}

class _WorkspaceButton extends ConsumerWidget {
  const _WorkspaceButton({required this.current});

  final Workspace current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: context.t('mobile:home.switchWorkspace'),
      child: InkWell(
        borderRadius: BorderRadius.circular(KaneoRadius.md),
        onTap: () => switchWorkspace(context, ref, current),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(current.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Icon(LucideIcons.chevronDown, size: 14, color: context.colors.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerStatefulWidget {
  const _HomeBody({required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<_HomeBody> {
  bool _showArchived = false;

  Future<void> _refresh() => Future.wait([
    ref.read(projectsQuery(widget.workspaceId).notifier).refresh(),
    if (_showArchived) ref.read(allProjectsQuery(widget.workspaceId).notifier).refresh(),
  ]);

  /// This page stays open under whatever was opened from it, such as a board where tasks got done,
  /// so nothing reads the progress again. On wide windows the sidebar does, whenever the page changes.
  void _returned() {
    if (!context.isWide) unawaited(ref.read(projectsQuery(widget.workspaceId).notifier).refresh());
    if (_showArchived) {
      unawaited(ref.read(allProjectsQuery(widget.workspaceId).notifier).refresh());
    }
  }

  EdgeInsets _padding(BuildContext context) {
    if (!context.isWide) return const EdgeInsets.fromLTRB(16, 16, 16, 24);
    // The web app's `px-6 py-10 lg:px-10`.
    final side = MediaQuery.sizeOf(context).width >= 1024 ? 40.0 : 24.0;
    return EdgeInsets.fromLTRB(side, 40, side, 40);
  }

  @override
  Widget build(BuildContext context) {
    final active = projectsQuery(widget.workspaceId);
    final all = allProjectsQuery(widget.workspaceId);
    final activeValue = ref.watch(active);
    final allValue = _showArchived ? ref.watch(all) : null;
    // The list stays on screen while the archived projects are on their way.
    final showAll = allValue != null && (allValue.hasValue || !allValue.isLoading);
    final query = showAll ? all : active;
    return PageReturn(
      onReturn: _returned,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: [
            ContentWidth(
              maxWidth: _pageMaxWidth,
              child: Padding(
                padding: _padding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Today(),
                    const SizedBox(height: 28),
                    _SectionHeader(
                      title: context.t('workspace:home.projects.title'),
                      action: context.t(
                        _showArchived ? 'mobile:home.hideArchived' : 'mobile:home.showArchived',
                      ),
                      onAction: () => setState(() => _showArchived = !_showArchived),
                    ),
                    const SizedBox(height: 12),
                    AsyncBody(
                      value: showAll ? allValue : activeValue,
                      onRetry: () => ref.read(query.notifier).refresh(),
                      isEmpty: (projects) => projects.isEmpty,
                      empty: StatusMessage(
                        title: context.t('mobile:home.empty.title'),
                        message: context.t('mobile:home.empty.message'),
                      ),
                      builder: (context, projects) => context.isWide
                          ? _ProjectGrid(projects: projects)
                          : _ProjectGroup(projects: projects),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's date and the greeting. Changes on its own while the page is open, and catches up as soon
/// as the app comes back to the foreground: timers don't run reliably in the background.
class _Today extends ConsumerStatefulWidget {
  const _Today();

  @override
  ConsumerState<_Today> createState() => _TodayState();
}

class _TodayState extends ConsumerState<_Today> {
  late final AppLifecycleListener _lifecycle;
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => setState(_update));
    _update();
  }

  void _update() {
    _now = ref.read(nowProvider)();
    _timer?.cancel();
    _timer = Timer(nextGreetingOrDayChange(_now).difference(_now), () => setState(_update));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18nScope.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatLongDate(i18n, _now),
          style: text.bodySmall!.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Text(greeting(i18n, _now), style: text.displayMedium),
      ],
    );
  }
}

/// A section's title over a line, with a quiet action at its end. The web app's `SectionHeader`.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action, required this.onAction});

  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall!.copyWith(fontSize: 15),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              flex: 2,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: c.mutedForeground,
                  textStyle: text.labelMedium!.copyWith(fontSize: 13),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(action, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The web app's project cards, in as many columns as fit, up to three.
class _ProjectGrid extends StatelessWidget {
  const _ProjectGrid({required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fit = ((width + _cardGap) / (_minCardWidth + _cardGap)).floor();
        final columns = fit.clamp(1, _maxCardColumns);
        // A hair under the exact width, or rounding errors could push a row's last card onto the
        // next row.
        final cardWidth = (width - _cardGap * (columns - 1)) / columns - 0.01;
        return Wrap(
          spacing: _cardGap,
          runSpacing: _cardGap,
          children: [
            for (final project in projects)
              SizedBox(
                key: homeProjectKey(project.id),
                width: cardWidth,
                child: _ProjectCard(project: project),
              ),
          ],
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final percent = _percent(project);
    return Opacity(
      opacity: project.archivedAt == null ? 1 : _archivedOpacity,
      child: Semantics(
        container: true,
        button: true,
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: c.border),
            borderRadius: BorderRadius.circular(KaneoRadius.lg),
          ),
          child: InkWell(
            onTap: () => context.push(AppRoutes.board(project.id)),
            hoverColor: c.accent.faded(0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(projectIcon(project.icon), size: 16, color: c.mutedForeground),
                      const SizedBox(width: 8),
                      Expanded(child: _ProjectName(project: project)),
                      const SizedBox(width: 8),
                      Text(_formatPercent(context, percent), style: text.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ProgressBar(percent: percent),
                  const SizedBox(height: 14),
                  Text(
                    project.archivedAt == null
                        ? context.t('workspace:home.projects.tasks', {
                            'count': _totalTasks(project),
                          })
                        : context.t('mobile:home.archived'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The current app's project list: rows inside one rounded box.
class _ProjectGroup extends StatelessWidget {
  const _ProjectGroup({required this.projects});

  final List<Project> projects;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: c.border),
        borderRadius: BorderRadius.circular(KaneoRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, project) in projects.indexed) ...[
            if (index > 0) Divider(height: 1, thickness: 1, color: c.border),
            _ProjectRow(key: homeProjectKey(project.id), project: project),
          ],
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({super.key, required this.project});

  final Project project;

  String _status(BuildContext context) {
    if (project.archivedAt != null) return context.t('mobile:home.archived');
    final due = project.statistics?.dueDate;
    if (due != null) {
      return context.t('mobile:home.due', {'date': formatDate(I18nScope.of(context), due)});
    }
    final total = _totalTasks(project);
    if (total == 0) return context.t('mobile:home.noTasks');
    final done = (_percent(project) / 100 * total).round();
    return context.t('mobile:home.progress', {'done': done, 'total': total});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final percent = _percent(project);
    return Opacity(
      opacity: project.archivedAt == null ? 1 : _archivedOpacity,
      child: Semantics(
        container: true,
        button: true,
        child: InkWell(
          onTap: () => context.push(AppRoutes.board(project.id)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(projectIcon(project.icon), size: 16, color: c.mutedForeground),
                    const SizedBox(width: 12),
                    Expanded(child: _ProjectName(project: project)),
                    const SizedBox(width: 8),
                    Text(_status(context), style: text.bodySmall),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 28),
                  child: Row(
                    children: [
                      Expanded(child: _ProgressBar(percent: percent)),
                      const SizedBox(width: 12),
                      Text(_formatPercent(context, percent), style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectName extends StatelessWidget {
  const _ProjectName({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Text(
      project.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelLarge,
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LinearProgressIndicator(
      value: percent / 100,
      minHeight: 4,
      borderRadius: BorderRadius.circular(2),
      color: c.foreground.withValues(alpha: 0.8),
      backgroundColor: c.muted,
    );
  }
}

int _percent(Project project) =>
    (project.statistics?.completionPercentage ?? 0).round().clamp(0, 100);

int _totalTasks(Project project) => (project.statistics?.totalTasks ?? 0).round();

String _formatPercent(BuildContext context, int percent) =>
    NumberFormat.percentPattern(I18nScope.of(context).intlLocale).format(percent / 100);
