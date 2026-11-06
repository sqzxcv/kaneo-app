import 'dart:ui' show FlutterView;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:kaneo_app/core/core.dart';

/// Uses the display rather than the window, which may be letterboxed or in split view.
bool isPhoneDisplay(TargetPlatform platform, Size pixels, double pixelRatio) =>
    (platform == TargetPlatform.android || platform == TargetPlatform.iOS) &&
    pixels.shortestSide / pixelRatio < wideLayoutMinShortestSide;

class BoardOrientation extends StatefulWidget {
  const BoardOrientation({
    super.key,
    required this.projectId,
    required this.child,
    this.enabled = true,
  });

  final String projectId;
  final bool enabled;
  final Widget child;

  @override
  State<BoardOrientation> createState() => _BoardOrientationState();
}

class _BoardOrientationState extends State<BoardOrientation> with WidgetsBindingObserver {
  FlutterView? _view;
  GoRouter? _router;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.of(context);
    final router = GoRouter.maybeOf(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_update);
      _router = router;
      router?.routerDelegate.addListener(_update);
    }
    _update();
  }

  @override
  void didUpdateWidget(BoardOrientation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void didChangeMetrics() => _update();

  void _update() {
    final display = _view?.display;
    final active = _router == null || _router!.state.uri.path == AppRoutes.board(widget.projectId);
    final lock =
        !kIsWeb &&
        widget.enabled &&
        active &&
        display != null &&
        isPhoneDisplay(defaultTargetPlatform, display.size, display.devicePixelRatio);
    if (_locked == lock) return;
    _locked = lock;
    SystemChrome.setPreferredOrientations(
      lock ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : [],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router?.routerDelegate.removeListener(_update);
    if (_locked) SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
