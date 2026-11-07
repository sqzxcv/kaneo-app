import 'package:flutter/material.dart';

import '../../core/core.dart';
import 'markdown_view.dart';

/// The plain text box for Markdown source, with no formatting tools.
///
/// What it holds is what gets saved, so it must not change the text by itself or disturb an input
/// method:
///
/// - Smart quotes and dashes stay off, because they rewrite Markdown syntax as it is typed.
/// - There are no input formatters or length limit, because they reset the text being composed and
///   make Chinese candidates repeat.
/// - Suggestions stay on, because turning them off gives Android a password keyboard with no Chinese.
///
/// Never set [controller]'s value as a result of typing, for the same reason. Only something the
/// person asked for by pressing a button may do that, such as inserting a mention.
class MarkdownField extends StatelessWidget {
  const MarkdownField({
    super.key,
    required this.controller,
    required this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    this.minLines = 4,
    this.hintText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final bool readOnly;
  final int minLines;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: markdownTextSize,
      height: markdownLineHeight,
      color: context.colors.foreground,
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      readOnly: readOnly,
      style: style,
      minLines: minLines,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textCapitalization: TextCapitalization.sentences,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      // Keeps what is under the text box above the keyboard.
      scrollPadding: const EdgeInsets.all(48),
      decoration: InputDecoration(hintText: hintText, contentPadding: const EdgeInsets.all(12)),
      // Touch screens don't leave a text box on a tap elsewhere unless told to.
      onTapOutside: (_) => focusNode.unfocus(),
    );
  }
}
