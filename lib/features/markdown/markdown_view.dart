import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Shows task descriptions and comments.
///
/// KAN-32 replaces the body, adding Kaneo's tags and the rest of the formatting. Callers do not
/// change.
class MarkdownView extends StatelessWidget {
  const MarkdownView({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(data: data, selectable: true);
  }
}
