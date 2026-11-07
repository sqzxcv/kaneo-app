import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/core.dart';

/// The banner, for tests.
const serverBannerKey = ValueKey('server-banner');

/// [page] with a banner above it while the server can't be reached, which says so and offers to try
/// again. Pages keep showing what they last loaded, so without it nothing would tell the person
/// that it may be out of date.
///
/// The banner goes by itself once a request gets through, such as the one the realtime connection
/// makes when the network comes back.
class ServerBannerArea extends ConsumerWidget {
  const ServerBannerArea({super.key, required this.page, this.insetTop = false});

  final Widget page;

  /// Narrow pages draw the top of the screen's inset themselves. While the banner shows, it is the
  /// top of the screen instead, so it takes the inset over.
  final bool insetTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = !ref.watch(serverReachableProvider);
    const banner = _ServerBanner();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!offline)
          const SizedBox.shrink()
        else if (insetTop)
          const SafeArea(bottom: false, child: banner)
        else
          banner,
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: offline && insetTop,
            child: page,
          ),
        ),
      ],
    );
  }
}

class _ServerBanner extends ConsumerWidget {
  const _ServerBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        key: serverBannerKey,
        // The web app's warning alert: `border-warning/32 bg-warning/4 [&>svg]:text-warning`.
        decoration: BoxDecoration(
          color: Color.alphaBlend(c.warning.withValues(alpha: 0.04), c.background),
          border: Border(bottom: BorderSide(color: c.warning.withValues(alpha: 0.32))),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          child: Row(
            children: [
              Icon(LucideIcons.wifiOff, size: 16, color: c.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.t('mobile:errors.unreachable'),
                  style: TextStyle(fontSize: 13, color: c.foreground),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                // Loads every page on screen again. Whichever request gets through takes the banner
                // away.
                onPressed: () => ref.read(openQueriesProvider).refresh(),
                child: Text(context.t('mobile:common.retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
