import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/core.dart';

/// Lets the person pick another workspace, remembers it and moves the app to it. Every page reads
/// the current workspace, so they all follow.
///
/// Call it with the context of the control that was pressed, as with every picker.
Future<void> switchWorkspace(BuildContext context, WidgetRef ref, Workspace current) async {
  // Taken up front: the window can cross the breakpoint, and take the control away, while this is
  // open.
  final selection = ref.read(selectedWorkspaceIdProvider.notifier);
  final api = ref.read(kaneoApiProvider);
  final router = GoRouter.of(context);
  final picked = await pickOption<String>(
    context,
    title: context.t('navigation:workspaceSwitcher.workspaces'),
    selected: current.id,
    options: [
      for (final workspace in ref.read(workspacesQuery).value ?? const <Workspace>[])
        PickerOption(value: workspace.id, label: workspace.name),
    ],
  );
  if (picked == null || picked.value == current.id) return;
  await selection.select(picked.value);
  // Keeps the web app's active workspace in step. Nothing here depends on it, and API keys can't
  // set it, so a failure is not worth telling anyone about.
  unawaited(api.setActiveWorkspace(picked.value).catchError((Object _) {}));
  // The open page may belong to the workspace just left.
  router.go(AppRoutes.home);
}
