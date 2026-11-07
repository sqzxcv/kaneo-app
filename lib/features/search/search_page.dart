import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import '../inbox/my_tasks_groups.dart' show taskStatusName;
import '../shell/page_return.dart';
import '../shell/workspace_gate.dart';
import '../task/open_task.dart';
import 'search_results.dart';

/// How long typing has to pause before it searches, as in the current app and the web app.
const Duration _typingPause = Duration(milliseconds: 300);

/// Finds tasks, projects and comments in the current workspace. Coming back to the page shows the
/// last search as it was, and looks again.
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('mobile:ui.search'))),
      body: ContentWidth(
        child: WorkspaceGate(
          builder: (context, workspace) =>
              _SearchBody(key: ValueKey(workspace.id), workspaceId: workspace.id),
        ),
      ),
    );
  }
}

class _SearchBody extends ConsumerStatefulWidget {
  const _SearchBody({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  ConsumerState<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends ConsumerState<_SearchBody> {
  final _field = TextEditingController();
  Timer? _pause;

  /// The words searched for. Empty before there are any.
  String _text = '';

  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _text = rememberedSearch(ref.read(cacheStoreProvider), widget.workspaceId) ?? '';
    _field.text = _text;
    _field.addListener(_typed);
  }

  @override
  void dispose() {
    _pause?.cancel();
    _field.dispose();
    super.dispose();
  }

  ({String workspaceId, String text}) get _queryArg =>
      (workspaceId: widget.workspaceId, text: _text);

  void _typed() {
    _pause?.cancel();
    final value = _field.value;
    // Letters an input method is still composing aren't the words yet.
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    final text = value.text.trim();
    if (text == _text) return;
    if (text.isEmpty) {
      _search(text);
    } else {
      _pause = Timer(_typingPause, () => _search(text));
    }
  }

  void _search(String text) {
    _pause?.cancel();
    if (text.isEmpty) unawaited(forgetSearch(ref.read(cacheStoreProvider), widget.workspaceId));
    if (text != _text) setState(() => _text = text);
  }

  void _refresh() {
    if (_text.isNotEmpty) unawaited(ref.read(searchQuery(_queryArg).notifier).refresh());
  }

  void _open(SearchResult result) {
    switch (result.type) {
      case 'task':
        openTask(context, result.id, projectId: result.projectId);
      case 'project':
        unawaited(context.push(AppRoutes.board(result.id)));
      default:
        unawaited(_openCommentTask(result));
    }
  }

  /// A comment's result names its task only by ticket id, so that has to be looked up first.
  Future<void> _openCommentTask(SearchResult result) async {
    final slug = result.projectSlug;
    final number = result.taskNumber;
    if (slug == null || number == null) {
      final projectId = result.projectId;
      if (projectId != null) unawaited(context.push(AppRoutes.board(projectId)));
      return;
    }
    if (_opening) return;
    _opening = true;
    final task = await runAction(
      context,
      () => ref
          .read(kaneoApiProvider)
          .taskByTicketId(ticketId(slug, number), workspaceId: widget.workspaceId),
    );
    _opening = false;
    if (task != null && mounted) openTask(context, task.id);
  }

  @override
  Widget build(BuildContext context) {
    return PageReturn(
      onReturn: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: ValueListenableBuilder(
              valueListenable: _field,
              builder: (context, value, _) => TextField(
                key: const ValueKey('search-field'),
                controller: _field,
                autofocus: _text.isEmpty,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onSubmitted: (text) => _search(text.trim()),
                decoration: InputDecoration(
                  hintText: context.t('mobile:search.placeholder'),
                  prefixIcon: const Icon(LucideIcons.search, size: 16),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.t('mobile:search.clear'),
                          onPressed: _field.clear,
                          icon: const Icon(LucideIcons.circleX, size: 16),
                        ),
                ),
              ),
            ),
          ),
          Expanded(child: _text.isEmpty ? _prompt(context) : _results(context)),
        ],
      ),
    );
  }

  Widget _prompt(BuildContext context) => StatusMessage(
    title: context.t('mobile:search.empty.title'),
    message: context.t('mobile:search.empty.message'),
  );

  Widget _results(BuildContext context) {
    final query = searchQuery(_queryArg);
    return AsyncBody(
      value: ref.watch(query),
      onRetry: _refresh,
      isEmpty: (response) => !response.results.any(isSearchResultShown),
      empty: StatusMessage(title: context.t('mobile:search.noResults', {'query': _text})),
      builder: (context, response) {
        final now = ref.read(nowProvider)();
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          children: [
            for (final group in searchGroups)
              ..._group(context, group.titleKey, [
                for (final result in response.results)
                  if (result.type == group.type) result,
              ], now),
          ],
        );
      },
    );
  }

  List<Widget> _group(
    BuildContext context,
    String titleKey,
    List<SearchResult> results,
    DateTime now,
  ) {
    if (results.isEmpty) return const [];
    final style = Theme.of(context).textTheme.bodySmall!;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Row(
          children: [
            Text(context.t(titleKey), style: style.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Text('${results.length}', style: style),
          ],
        ),
      ),
      for (final result in results)
        _ResultRow(
          key: ValueKey('${result.type}-${result.id}'),
          result: result,
          now: now,
          onTap: () => _open(result),
        ),
    ];
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({super.key, required this.result, required this.now, required this.onTap});

  final SearchResult result;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(KaneoRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: c.accent.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: switch (result.type) {
              'task' => _task(context),
              'project' => _project(context),
              _ => _comment(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _layout({required Widget leading, required Widget main, required Widget details}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 24,
        child: Align(alignment: AlignmentDirectional.topStart, child: leading),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [main, const SizedBox(height: 2), details],
        ),
      ),
    ],
  );

  Widget _title(BuildContext context, String title) => Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodyMedium,
  );

  Widget _details(BuildContext context, String? ticket, String? rest) {
    final style = Theme.of(context).textTheme.bodySmall!;
    return Row(
      children: [
        if (ticket != null && ticket.isNotEmpty) ...[
          Text(ticket, style: style.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(rest ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      ],
    );
  }

  Widget _task(BuildContext context) {
    final status = result.status;
    return _layout(
      leading: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: PriorityIcon(priority: result.priority ?? ''),
      ),
      main: Row(
        children: [
          Expanded(child: _title(context, result.title)),
          if (status != null) ...[
            const SizedBox(width: 8),
            Text(
              taskStatusName(I18nScope.of(context), status, null),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      details: _details(
        context,
        ticketId(result.projectSlug, result.taskNumber),
        result.projectName,
      ),
    );
  }

  Widget _project(BuildContext context) => _layout(
    leading: Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Icon(LucideIcons.layoutGrid, size: 16, color: context.colors.mutedForeground),
    ),
    main: _title(context, result.title),
    details: _details(context, result.projectSlug?.toUpperCase(), null),
  );

  Widget _comment(BuildContext context) {
    final i18n = I18nScope.of(context);
    final c = context.colors;
    final name = result.userName;
    final when = relativeLong(i18n, result.createdAt, now: now);
    final content = plainPreview(result.content ?? '');
    return _layout(
      leading: CircleAvatar(
        radius: 12,
        backgroundColor: c.avatar,
        foregroundColor: c.avatarForeground,
        child: Text(initials(name), style: const TextStyle(fontSize: 10)),
      ),
      main: Text(
        content.isEmpty ? result.title : content,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13),
      ),
      details: _details(
        context,
        ticketId(result.projectSlug, result.taskNumber),
        name == null
            ? when
            : when.isEmpty
            ? name
            : i18n.t('mobile:search.commentMeta', {'name': name, 'when': when}),
      ),
    );
  }
}
