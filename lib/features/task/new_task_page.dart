import 'package:flutter/material.dart';

import '../../core/core.dart';

/// Placeholder until KAN-9.
class NewTaskPage extends StatelessWidget {
  const NewTaskPage({super.key, this.projectId, this.status});

  final String? projectId;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return PlaceholderPage(title: context.t('mobile:board.newTask'));
  }
}
