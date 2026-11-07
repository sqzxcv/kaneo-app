import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';
import 'app_sidebar.dart';

/// Marks the page next to the navigation, so that tests can look inside the page only.
const shellPageKey = ValueKey('shell-page');

class _Tab {
  const _Tab(this.path, this.labelKey, this.icon);

  final String path;
  final String labelKey;
  final IconData icon;
}

/// The four tabs of the current app, in its order. The account page opens from the home page.
const _tabs = [
  _Tab(AppRoutes.home, 'mobile:nav.home', LucideIcons.house),
  _Tab(AppRoutes.myTasks, 'mobile:nav.tasks', LucideIcons.circleCheck),
  _Tab(AppRoutes.inbox, 'mobile:nav.inbox', LucideIcons.inbox),
  _Tab(AppRoutes.activity, 'mobile:nav.activity', LucideIcons.activity),
];

/// The navigation around every page: a sidebar on wide windows and bottom tabs on narrow ones.
/// Narrow windows hide the tabs on pages below the tabs, such as the board and task pages.
///
/// [child] holds the open pages. It keeps its state when the window crosses the breakpoint, because
/// go_router gives it a global key, so the two layouts are free to place it differently.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final Uri location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final page = KeyedSubtree(key: shellPageKey, child: child);
    if (context.isWide) return _WideShell(location: location, page: page);
    return _NarrowShell(location: location, page: page);
  }
}

class _WideShell extends StatelessWidget {
  const _WideShell({required this.location, required this.page});

  final Uri location;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.sidebar,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSidebar(location: location),
            Expanded(
              // The web app's inset panel: the page floats on the sidebar's color.
              child: Container(
                margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.background,
                  borderRadius: BorderRadius.circular(KaneoRadius.xl),
                  boxShadow: const [
                    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
                  ],
                ),
                child: page,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NarrowShell extends StatelessWidget {
  const _NarrowShell({required this.location, required this.page});

  final Uri location;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final index = _tabs.indexWhere((tab) => tab.path == location.path);
    return Scaffold(
      // Pages draw their own top and bottom insets. A phone on its side has a notch on one side.
      body: SafeArea(top: false, bottom: false, child: page),
      bottomNavigationBar: index < 0
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.colors.border)),
              ),
              child: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (selected) => context.go(_tabs[selected].path),
                destinations: [
                  for (final tab in _tabs)
                    NavigationDestination(icon: Icon(tab.icon), label: context.t(tab.labelKey)),
                ],
              ),
            ),
    );
  }
}
