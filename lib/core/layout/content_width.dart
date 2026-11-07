import 'package:flutter/widgets.dart';

import 'breakpoints.dart';

/// How wide reading pages grow on wide windows. The web app's settings and inbox pages stop at
/// `max-w-3xl`, which is this.
const double contentMaxWidth = 768;

/// Keeps a reading page, such as the account page or the inbox, from stretching across a wide
/// window. Fills the width on narrow windows.
///
/// The widgets are the same in both layouts, so whatever [child] holds survives crossing the
/// breakpoint. Do not branch on `context.isWide` around stateful content for the same reason.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.isWide ? contentMaxWidth : double.infinity),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
