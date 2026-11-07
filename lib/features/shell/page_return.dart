import 'dart:async';

import 'package:flutter/widgets.dart';

/// Calls [onReturn] when the page around it is back on top, such as after closing a task opened from
/// it. The page stays open underneath, so its queries would not load again by themselves.
class PageReturn extends StatefulWidget {
  const PageReturn({super.key, required this.onReturn, required this.child});

  final VoidCallback onReturn;
  final Widget child;

  @override
  State<PageReturn> createState() => _PageReturnState();
}

class _PageReturnState extends State<PageReturn> {
  bool _onTop = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onTop = ModalRoute.isCurrentOf(context) ?? true;
    // A microtask, because this runs during a build and queries can't change then.
    if (onTop && !_onTop) scheduleMicrotask(_returned);
    _onTop = onTop;
  }

  void _returned() {
    if (mounted) widget.onReturn();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
