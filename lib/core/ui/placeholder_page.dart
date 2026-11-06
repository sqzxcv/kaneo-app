import 'package:flutter/material.dart';

import '../i18n/i18n.dart';

/// The frame of a page whose real implementation comes with a later task.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, this.actions, this.child});

  final String title;
  final List<Widget>? actions;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.t('app:placeholder.notice'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (child != null) Expanded(child: child!),
        ],
      ),
    );
  }
}
