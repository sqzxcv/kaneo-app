import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../core/core.dart';
import '../task/open_task.dart';
import 'legacy_html.dart';
import 'markdown_syntax.dart';
import 'markdown_urls.dart';

const double markdownTextSize = 15;
const double markdownLineHeight = 1.6;

/// The web caps an image it has not been told to resize at 44rem.
const double _maxImageWidth = 704;

/// Marks the box that stands in for an image while it loads.
const markdownImageLoadingKey = ValueKey('markdown-image-loading');

/// Shows task descriptions and comments, including Kaneo's own tags and old HTML descriptions.
class MarkdownView extends ConsumerWidget {
  const MarkdownView({super.key, required this.data, this.onTapText});

  final String data;

  /// Called on a tap on the text. A tap on a link still only opens the link.
  ///
  /// The renderer keeps what it built until [data] changes, so a different function passed later
  /// may never be called. Pass one function, and let it decide when to do nothing.
  final VoidCallback? onTapText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final style = _styleSheet(context);
    return MarkdownBody(
      data: isLegacyHtml(data) ? legacyHtmlToMarkdown(data) : data,
      selectable: true,
      onTapText: onTapText,
      fitContent: false,
      styleSheet: style,
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.start,
      syntaxHighlighter: _PlainCode(_codeBlockStyle(context)),
      blockSyntaxes: kaneoBlockSyntaxes,
      inlineSyntaxes: kaneoInlineSyntaxes(attachmentLabel: context.t('mobile:editor.attachment')),
      imageBuilder: (uri, title, alt) => _MarkdownImage(source: uri.toString(), alt: alt),
      checkboxBuilder: _Checkbox.new,
      bulletBuilder: (parameters) => _bullet(parameters, style.listBullet),
      builders: {
        KaneoTags.mention: _SpanBuilder(
          TextStyle(
            fontWeight: FontWeight.w500,
            color: colors.primary,
            backgroundColor: colors.primary.withValues(alpha: 0.12),
          ),
        ),
        KaneoTags.underline: _SpanBuilder(const TextStyle(decoration: TextDecoration.underline)),
        KaneoTags.sizedImage: _SizedImageBuilder(),
        KaneoTags.htmlBlock: _TransparentBlockBuilder(),
      },
      onTapLink: (text, href, title) => _openLink(context, ref, href),
    );
  }
}

/// Opens a link to a task of this server in the app, and anything else in the system.
Future<void> _openLink(BuildContext context, WidgetRef ref, String? href) async {
  final serverUrl = ref.read(sessionProvider)?.serverUrl;
  final taskId = linkedTaskId(serverUrl, href);
  if (taskId != null) {
    openTaskPage(context, taskId);
    return;
  }
  final target = resolveLink(serverUrl, href);
  var opened = false;
  if (target != null) {
    try {
      opened = await launchUrl(target);
    } on PlatformException {
      opened = false;
    }
  }
  if (!opened && context.mounted) {
    showToast(context, context.t('app:markdown.linkFailed'), kind: ToastKind.error);
  }
}

/// The web's prose styles (`.kaneo-tiptap-content` in `index.css`).
MarkdownStyleSheet _styleSheet(BuildContext context) {
  final colors = context.colors;
  final body = Theme.of(context).textTheme.bodyMedium!
      .copyWith(fontSize: markdownTextSize, height: markdownLineHeight, color: colors.foreground);
  TextStyle heading(double size) => body.copyWith(
    fontSize: size,
    height: 1.26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.02 * size,
  );
  const headingPadding = EdgeInsets.only(top: 10, bottom: 2);
  final divider = BorderSide(color: colors.border);
  return MarkdownStyleSheet(
    p: body,
    h1: heading(20),
    h1Padding: headingPadding,
    h2: heading(18),
    h2Padding: headingPadding,
    h3: heading(16),
    h3Padding: headingPadding,
    h4: heading(markdownTextSize),
    h4Padding: headingPadding,
    h5: heading(markdownTextSize),
    h5Padding: headingPadding,
    h6: heading(markdownTextSize),
    h6Padding: headingPadding,
    strong: const TextStyle(fontWeight: FontWeight.w600),
    em: const TextStyle(fontStyle: FontStyle.italic),
    del: const TextStyle(decoration: TextDecoration.lineThrough),
    a: TextStyle(
      color: colors.infoForeground,
      decoration: TextDecoration.underline,
      decorationColor: colors.infoForeground.withValues(alpha: 0.45),
    ),
    code: TextStyle(
      fontFamily: KaneoFonts.mono,
      fontSize: markdownTextSize * 0.84,
      backgroundColor: colors.codeHighlight,
    ),
    codeblockPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    codeblockDecoration: BoxDecoration(
      color: colors.code,
      border: Border.fromBorderSide(divider),
      borderRadius: BorderRadius.circular(KaneoRadius.md),
    ),
    blockquote: body.copyWith(color: colors.foreground.withValues(alpha: 0.78)),
    blockquotePadding: const EdgeInsets.only(left: 12),
    blockquoteDecoration: BoxDecoration(border: Border(left: divider.copyWith(width: 2))),
    horizontalRuleDecoration: BoxDecoration(border: Border(top: divider)),
    blockSpacing: 6,
    listIndent: 24,
    listBullet: body.copyWith(color: colors.foreground.withValues(alpha: 0.7)),
    listBulletPadding: const EdgeInsets.only(right: 4),
    tableHead: body.copyWith(fontWeight: FontWeight.w600),
    tableBody: body,
    tableHeadAlign: TextAlign.left,
    tableBorder: TableBorder.all(
      color: colors.border,
      borderRadius: BorderRadius.circular(KaneoRadius.md),
    ),
    // Columns keep their width and the table scrolls, so a phone doesn't squeeze them to a sliver.
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableVerticalAlignment: TableCellVerticalAlignment.top,
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    tableCellsDecoration: const BoxDecoration(),
    tableHeadCellsDecoration: BoxDecoration(color: colors.accent),
  );
}

TextStyle _codeBlockStyle(BuildContext context) => TextStyle(
  fontFamily: KaneoFonts.mono,
  fontSize: 13.5,
  height: 1.5,
  color: context.colors.codeForeground,
);

/// Code blocks aren't highlighted. This keeps the inline code background off them.
class _PlainCode implements SyntaxHighlighter {
  const _PlainCode(this.style);

  final TextStyle style;

  @override
  TextSpan format(String source) => TextSpan(style: style, text: source);
}

Widget _bullet(MarkdownBulletParameters parameters, TextStyle? style) {
  final isOrdered = parameters.style == BulletStyle.orderedList;
  const bullets = ['•', '◦', '▪'];
  final level = parameters.nestLevel.clamp(0, bullets.length - 1);
  return Text(
    isOrdered ? '${parameters.index + 1}.' : bullets[level],
    textAlign: isOrdered ? TextAlign.right : TextAlign.center,
    softWrap: false,
    overflow: TextOverflow.visible,
    style: style,
  );
}

class _Checkbox extends StatelessWidget {
  const _Checkbox(this.checked);

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        // Centers the box on the first line of text.
        padding: const EdgeInsets.only(top: (markdownTextSize * markdownLineHeight - 16) / 2),
        child: Semantics(
          checked: checked,
          child: Icon(
            checked ? LucideIcons.squareCheck : LucideIcons.square,
            size: 16,
            color: checked ? colors.primary : colors.mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// Styles a run of text. Returning `Text` keeps it in the line with the text around it.
class _SpanBuilder extends MarkdownElementBuilder {
  _SpanBuilder(this.style);

  final TextStyle style;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => Text.rich(
    TextSpan(text: element.textContent, style: (parentStyle ?? const TextStyle()).merge(style)),
  );
}

class _SizedImageBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) => _MarkdownImage(
    source: element.attributes['src']!,
    alt: element.attributes['alt'],
    width: double.parse(element.attributes['width']!),
  );
}

/// A block with no look of its own. Returning null makes the renderer lay out its children.
class _TransparentBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;
}

class _MarkdownImage extends ConsumerWidget {
  const _MarkdownImage({required this.source, this.alt, this.width});

  final String source;
  final String? alt;
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final target = resolveImage(session?.serverUrl, source);
    final image = switch (target) {
      null => _failed(context),
      Uri(scheme: 'data') => _memoryImage(context, target),
      _ => Image.network(
        target.toString(),
        headers: session != null && isOnServer(target, session.serverUrl)
            ? credentialHeaders(session.credentialType, session.token)
            : null,
        width: width,
        fit: BoxFit.contain,
        semanticLabel: alt,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            frame == null && !wasSynchronouslyLoaded ? _placeholder(context) : child,
        errorBuilder: (context, error, stack) => _failed(context),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width ?? _maxImageWidth),
        child: ClipRRect(borderRadius: BorderRadius.circular(KaneoRadius.md), child: image),
      ),
    );
  }

  Widget _memoryImage(BuildContext context, Uri target) {
    try {
      return Image.memory(
        target.data!.contentAsBytes(),
        width: width,
        fit: BoxFit.contain,
        semanticLabel: alt,
        errorBuilder: (context, error, stack) => _failed(context),
      );
    } on FormatException {
      return _failed(context);
    }
  }

  Widget _placeholder(BuildContext context) => SizedBox(
    key: markdownImageLoadingKey,
    width: width ?? 240,
    height: 135,
    child: ColoredBox(color: context.colors.muted),
  );

  Widget _failed(BuildContext context) {
    final colors = context.colors;
    final label = alt == null || alt!.isEmpty ? context.t('app:markdown.imageFailed') : alt!;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(LucideIcons.imageOff, size: 16, color: colors.mutedForeground),
          ),
          TextSpan(text: ' $label'),
        ],
      ),
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.mutedForeground),
    );
  }
}
