import '../../core/core.dart';

/// The ways my tasks can be grouped, in the order they are offered.
enum MyTasksGrouping { dueDate, project, status }

/// When a task is due, in the order the groups are shown.
enum DueBucket { overdue, today, thisWeek, later, none }

/// A group of my tasks. Due-date groups have a [bucket], which is translated when shown. The others
/// have a [title].
class MyTasksGroup {
  const MyTasksGroup({required this.id, this.bucket, this.title, required this.tasks});

  final String id;
  final DueBucket? bucket;
  final String? title;
  final List<AssignedTask> tasks;
}

/// Compares calendar days, so that it changes at the person's midnight.
DueBucket dueBucket(String? dueDate, DateTime now) {
  final day = parseDay(dueDate);
  if (day == null) return DueBucket.none;
  final today = startOfDay(now);
  if (day.isBefore(today)) return DueBucket.overdue;
  if (day == today) return DueBucket.today;
  return day.isBefore(DateTime(now.year, now.month, now.day + 7))
      ? DueBucket.thisWeek
      : DueBucket.later;
}

/// Tasks stay in the server's order, the most pressing first, and that also gives the order of
/// projects and statuses: the one with the most pressing work is on top.
List<MyTasksGroup> groupMyTasks(
  List<AssignedTask> tasks,
  MyTasksGrouping grouping, {
  required DateTime now,
  required String Function(AssignedTask task) statusName,
}) {
  switch (grouping) {
    case MyTasksGrouping.dueDate:
      final buckets = <DueBucket, List<AssignedTask>>{};
      for (final task in tasks) {
        buckets.putIfAbsent(dueBucket(task.dueDate, now), () => []).add(task);
      }
      return [
        for (final bucket in DueBucket.values)
          if (buckets[bucket] case final inBucket?)
            MyTasksGroup(id: bucket.name, bucket: bucket, tasks: inBucket),
      ];
    case MyTasksGrouping.project:
      return _groupBy(tasks, (t) => t.projectId, (t) => t.projectName);
    case MyTasksGrouping.status:
      // By name, so that the same column of different projects is one group.
      return _groupBy(tasks, statusName, statusName);
  }
}

List<MyTasksGroup> _groupBy(
  List<AssignedTask> tasks,
  String Function(AssignedTask task) id,
  String Function(AssignedTask task) title,
) {
  final groups = <String, List<AssignedTask>>{};
  for (final task in tasks) {
    groups.putIfAbsent(id(task), () => []).add(task);
  }
  return [
    for (final MapEntry(key: key, value: inGroup) in groups.entries)
      MyTasksGroup(id: key, title: title(inGroup.first), tasks: inGroup),
  ];
}

/// The columns every project starts with, with the names the server gives them.
const Map<String, String> _defaultColumnNames = {
  'to-do': 'To Do',
  'in-progress': 'In Progress',
  'in-review': 'In Review',
  'done': 'Done',
};

/// A task's status in the person's language. A column someone has named keeps that name, as in the
/// web app.
String taskStatusName(I18n i18n, String status, String? columnName) {
  if (columnName != null && columnName != _defaultColumnNames[status]) return columnName;
  final key = 'tasks:status.$status';
  final translated = i18n.t(key);
  if (translated != key) return translated;
  return columnName ?? status;
}
