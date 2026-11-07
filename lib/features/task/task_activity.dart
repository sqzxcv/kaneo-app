import '../../core/core.dart';

/// Everything that happened on a task, newest first. There is no limit, so this is all of it.
final taskActivitiesQuery = cachedQueryFamily<List<Activity>, String>(
  (taskId) => QuerySpec(
    key: 'task-activities/$taskId',
    fetch: (ref) => ref.read(kaneoApiProvider).activities(taskId),
    encode: (v) => v.map((e) => e.toJson()).toList(),
    decode: (j) =>
        (j as List).map((e) => Activity.fromJson((e as Map).cast<String, dynamic>())).toList(),
  ),
);

/// How many people a list offers to mention at a time, as in the web app.
const int _maxMentionSuggestions = 8;

/// Comments with nothing in them read as events, as in the web app.
bool isCommentEntry(Activity activity) =>
    activity.type == 'comment' && (activity.content ?? '').isNotEmpty;

/// Only its author can change a comment. One imported from elsewhere has no author here, even though
/// the person who imported it is on record, because the words aren't theirs.
bool canChangeComment(Activity activity, String? userId) =>
    userId != null &&
    isCommentEntry(activity) &&
    activity.externalSource == null &&
    activity.userId == userId;

bool wasEdited(Activity activity) =>
    activity.updatedAt != null && activity.updatedAt != activity.createdAt;

/// The name a person goes by in a mention. Accounts don't need to have set one.
String mentionName(WorkspaceMember person) =>
    person.name.trim().isEmpty ? person.email : person.name;

/// The people to offer for what has been typed after an `@`.
List<WorkspaceMember> peopleMatching(List<WorkspaceMember> people, String query) {
  final wanted = query.toLowerCase();
  return people
      .where((person) => mentionName(person).toLowerCase().contains(wanted))
      .take(_maxMentionSuggestions)
      .toList();
}

final _userToken = RegExp(r'\[\[user:[^|\]]+\|([^\]]+)\]\]');

/// [activity] the way the workspace's feed has it, so that both word events the same way.
///
/// [userName] is who [activity.userId] is. For an imported event that is who imported it, and the
/// name to show is the one it came with.
WorkspaceActivity feedEntry(Activity activity, {String? userName}) => WorkspaceActivity(
  id: activity.id,
  type: activity.type,
  createdAt: activity.createdAt,
  eventData: activity.eventData,
  // Assignments recorded before they had details name the person in a token of the web app's.
  excerpt: activity.content?.replaceAllMapped(_userToken, (match) => match[1]!),
  userId: activity.userId,
  userName: activity.externalSource == null ? userName : null,
  externalUserName: activity.externalUserName,
  taskId: activity.taskId,
  taskTitle: '',
  projectId: '',
  projectSlug: '',
);
