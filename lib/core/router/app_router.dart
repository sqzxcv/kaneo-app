import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/activity_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/board/board_page.dart';
import '../../features/home/home_page.dart';
import '../../features/inbox/inbox_page.dart';
import '../../features/inbox/my_tasks_page.dart';
import '../../features/search/search_page.dart';
import '../../features/shell/account_page.dart';
import '../../features/shell/app_shell.dart';
import '../../features/task/new_task_page.dart';
import '../../features/task/task_page.dart';
import '../providers.dart';
import 'routes.dart';

export 'routes.dart';

/// Where the app opens. Tests use it to start on a specific page.
final initialLocationProvider = Provider<String>((ref) => AppRoutes.home);

/// Sends anyone without a session to the login page, and anyone with one away from it.
String? authRedirect({required bool signedIn, required Uri location}) {
  final atLogin = location.path == AppRoutes.login;
  if (!signedIn && !atLogin) return AppRoutes.login;
  if (signedIn && atLogin) return AppRoutes.home;
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final sessionChanged = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => sessionChanged.value++);
  ref.onDispose(sessionChanged.dispose);

  final router = GoRouter(
    initialLocation: ref.read(initialLocationProvider),
    refreshListenable: sessionChanged,
    redirect: (context, state) =>
        authRedirect(signedIn: ref.read(sessionProvider) != null, location: state.uri),
    routes: [
      GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri, child: child),
        routes: [
          GoRoute(path: AppRoutes.home, builder: (context, state) => const HomePage()),
          GoRoute(path: AppRoutes.inbox, builder: (context, state) => const InboxPage()),
          GoRoute(path: AppRoutes.myTasks, builder: (context, state) => const MyTasksPage()),
          GoRoute(path: AppRoutes.activity, builder: (context, state) => const ActivityPage()),
          GoRoute(path: AppRoutes.search, builder: (context, state) => const SearchPage()),
          GoRoute(path: AppRoutes.account, builder: (context, state) => const AccountPage()),
          GoRoute(
            path: AppRoutes.boardPattern,
            builder: (context, state) => BoardPage(projectId: state.pathParameters['projectId']!),
          ),
          // Registered before the task page so `new` is not read as a task id.
          GoRoute(
            path: AppRoutes.newTaskPath,
            builder: (context, state) => NewTaskPage(
              projectId: state.uri.queryParameters['projectId'],
              status: state.uri.queryParameters['status'],
            ),
          ),
          GoRoute(
            path: AppRoutes.taskPattern,
            builder: (context, state) => TaskPage(taskId: state.pathParameters['taskId']!),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
