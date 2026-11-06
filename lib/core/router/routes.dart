/// Paths of every phase-one page. Build locations with these instead of writing strings.
abstract final class AppRoutes {
  static const login = '/login';
  static const home = '/';
  static const inbox = '/inbox';
  static const myTasks = '/my-tasks';
  static const activity = '/activity';
  static const search = '/search';
  static const account = '/account';

  static const boardPattern = '/board/:projectId';
  static const newTaskPath = '/task/new';
  static const taskPattern = '/task/:taskId';

  static String board(String projectId) => '/board/$projectId';

  static String task(String taskId) => '/task/$taskId';

  /// [status] preselects a column when creating from that column.
  static String newTask({String? projectId, String? status}) {
    final query = {'projectId': ?projectId, 'status': ?status};
    return Uri(path: newTaskPath, queryParameters: query.isEmpty ? null : query).toString();
  }
}
