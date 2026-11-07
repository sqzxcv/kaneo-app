import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../shell/page_return.dart';
import '../shell/workspace_gate.dart';
import '../task/open_task.dart';
import 'describe_activity.dart';

/// What happened lately in the current workspace, newest first. A reading column on wide windows,
/// like the web app's feed. Every entry opens its task.
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('mobile:activity.title'))),
      body: ContentWidth(
        child: WorkspaceGate(
          builder: (context, workspace) {
            final query = workspaceActivityQuery(workspace.id);
            return PageReturn(
              onReturn: () => ref.read(query.notifier).refresh(),
              child: AsyncBody(
                value: ref.watch(query),
                onRetry: () => ref.read(query.notifier).refresh(),
                isEmpty: (items) => items.isEmpty,
                empty: StatusMessage(title: context.t('mobile:activity.empty')),
                builder: (context, items) {
                  final now = ref.read(nowProvider)();
                  return RefreshIndicator(
                    onRefresh: () => ref.read(query.notifier).refresh(),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      itemCount: items.length,
                      itemBuilder: (context, index) => _ActivityRow(
                        key: ValueKey(items[index].id),
                        activity: items[index],
                        now: now,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// An entry of the web app's feed.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({super.key, required this.activity, required this.now});

  final WorkspaceActivity activity;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i18n = I18nScope.of(context);
    final text = Theme.of(context).textTheme;
    final actor = activityActor(i18n, activity);
    final excerpt = plainPreview(activity.excerpt ?? '');
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(KaneoRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openTask(context, activity.taskId, projectId: activity.projectId),
          hoverColor: c.accent.faded(0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: c.avatar,
                  foregroundColor: c.avatarForeground,
                  child: Text(initials(actor), style: const TextStyle(fontSize: 10)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: actor,
                              style: TextStyle(fontWeight: FontWeight.w500, color: c.foreground),
                            ),
                            TextSpan(text: ' ${describeActivity(i18n, activity, now: now)}'),
                          ],
                        ),
                        style: text.bodyMedium!.copyWith(fontSize: 13, color: c.mutedForeground),
                      ),
                      if (activity.type == 'comment' && excerpt.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: c.muted.faded(0.7),
                            borderRadius: BorderRadius.circular(KaneoRadius.lg),
                          ),
                          child: Text(
                            excerpt,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium!.copyWith(
                              fontSize: 13,
                              color: c.foreground.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            ticketId(activity.projectSlug, activity.taskNumber),
                            style: text.bodySmall!.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              activity.taskTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall,
                            ),
                          ),
                          ExcludeSemantics(child: Text(' · ', style: text.bodySmall)),
                          Text(
                            relativeLong(i18n, activity.createdAt, now: now),
                            style: text.bodySmall,
                          ),
                        ],
                      ),
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
