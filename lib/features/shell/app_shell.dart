import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';

class _Destination {
  const _Destination(this.path, this.labelKey, this.icon);

  final String path;
  final String labelKey;
  final IconData icon;
}

const _destinations = [
  _Destination(AppRoutes.home, 'mobile:nav.home', LucideIcons.house),
  _Destination(AppRoutes.inbox, 'mobile:nav.inbox', LucideIcons.inbox),
  _Destination(AppRoutes.myTasks, 'mobile:nav.tasks', LucideIcons.circleCheck),
  _Destination(AppRoutes.activity, 'mobile:nav.activity', LucideIcons.activity),
  _Destination(AppRoutes.account, 'mobile:home.account', LucideIcons.user),
];

/// Minimal navigation until KAN-25: a rail on wide windows and bottom tabs on narrow ones. Narrow
/// windows hide the tabs on pushed pages, such as the board and task pages.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final Uri location;
  final Widget child;

  int? get _selectedIndex {
    final index = _destinations.indexWhere((d) => d.path == location.path);
    return index < 0 ? null : index;
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex;
    void go(int index) => context.go(_destinations[index].path);

    if (context.isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.icon), label: Text(context.t(d.labelKey))),
              ],
            ),
            VerticalDivider(width: 1, color: context.colors.sidebarBorder),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      body: child,
      bottomNavigationBar: selected == null
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: go,
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(icon: Icon(d.icon), label: context.t(d.labelKey)),
              ],
            ),
    );
  }
}
