// What a person, or a screen reader, can see on the screen: text, tooltips and semantics labels.
// The black-box tests find things only through these, never through the app's own keys or state.
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every node of the semantics tree that says something, one per line, indented by depth, with its
/// position on screen in logical pixels.
List<String> semanticsLines(WidgetTester tester) {
  final lines = <String>[];
  void visit(SemanticsNode node, int depth, Matrix4 parent) {
    final transform = parent.clone();
    if (node.transform != null) transform.multiply(node.transform!);
    final rect = MatrixUtils.transformRect(transform, node.rect);
    final data = node.getSemanticsData();
    final flags = data.flagsCollection;
    final parts = <String>[
      if (data.label.isNotEmpty) 'label=${_quote(data.label)}',
      if (data.tooltip.isNotEmpty) 'tooltip=${_quote(data.tooltip)}',
      if (data.value.isNotEmpty) 'value=${_quote(data.value)}',
      if (data.hint.isNotEmpty) 'hint=${_quote(data.hint)}',
      if (flags.isButton) 'button',
      if (flags.isTextField) 'textField',
      if (flags.isHeader) 'header',
      if (flags.isSelected == Tristate.isTrue) 'selected',
      if (flags.isChecked == CheckedState.isTrue) 'checked',
      if (flags.isChecked == CheckedState.isFalse) 'unchecked',
      if (flags.isEnabled == Tristate.isFalse) 'disabled',
    ];
    if (parts.isNotEmpty) {
      lines.add(
        '${'  ' * depth}${parts.join(' ')} '
        '@${rect.left.round()},${rect.top.round()} ${rect.width.round()}x${rect.height.round()}',
      );
    }
    node.visitChildren((child) {
      visit(child, depth + 1, transform);
      return true;
    });
  }

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root == null) continue;
    // The root's transform turns physical pixels into logical ones.
    visit(root, 0, Matrix4.identity());
  }
  return lines;
}

/// Every piece of text on screen, as the widgets draw it, with tooltips. Unlike [semanticsLines] it
/// includes text that a parent merges into one label, such as the parts of a card.
List<String> textLines(WidgetTester tester) {
  final lines = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final widget = element.widget as RichText;
    final text = widget.text.toPlainText();
    if (text.trim().isEmpty) continue;
    final box = element.renderObject as RenderBox?;
    final where = box != null && box.hasSize && box.attached
        ? box.localToGlobal(Offset.zero)
        : Offset.zero;
    lines.add('${_quote(text)} @${where.dx.round()},${where.dy.round()}');
  }
  for (final element in find.byType(EditableText).evaluate()) {
    final widget = element.widget as EditableText;
    lines.add('field ${_quote(widget.controller.text)}');
  }
  return lines;
}

String _quote(String text) => '"${text.replaceAll('\n', r'\n')}"';
