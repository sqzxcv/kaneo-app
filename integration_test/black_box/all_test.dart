// Every KAN-52 module in one run, so that a device builds the app once. Each module also runs on its
// own, as its own file.
import 'package:flutter_test/flutter_test.dart';

import 'board_test.dart' as board;
import 'filter_test.dart' as filter;
import 'fold_test.dart' as fold;
import 'home_test.dart' as home;
import 'layout_test.dart' as layout;
import 'login_test.dart' as login;
import 'markdown_test.dart' as markdown;
import 'new_task_test.dart' as new_task;
import 'platform_test.dart' as platform;
import 'task_test.dart' as task;

void main() {
  group('login', login.main);
  group('layout', layout.main);
  group('board', board.main);
  group('fold', fold.main);
  group('filter', filter.main);
  group('markdown', markdown.main);
  group('task', task.main);
  group('new task', new_task.main);
  group('home', home.main);
  group('platform', platform.main);
}
