import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:kaneo_app/core/core.dart';

/// How long a motion takes, or none when the system asks for less motion.
Duration _motion(BuildContext context, int milliseconds) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// [child] lifted by [lift], from 0 lying in its list to 1 in the hand: as on the web, a little
/// larger, tilted, with a deeper shadow.
Widget _lifted(double lift, Widget child) => Transform.rotate(
  angle: math.pi / 180 * lift,
  child: Transform.scale(
    scale: 1 + 0.03 * lift,
    child: Material(
      color: Colors.transparent,
      elevation: 8 * lift,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KaneoRadius.lg)),
      child: child,
    ),
  ),
);

/// The card in the hand. It grows into its lifted look as it is picked up.
class LiftedCard extends StatelessWidget {
  const LiftedCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: _motion(context, 150),
    curve: Curves.easeOut,
    builder: (context, lift, child) => _lifted(lift, child!),
    child: child,
  );
}

/// A card let go of, settling from where it was in the hand, [from], into its place, [to]. Shown
/// in an overlay; [onDone] removes it.
class CardLanding extends StatefulWidget {
  const CardLanding({
    super.key,
    required this.from,
    required this.to,
    required this.onDone,
    required this.child,
  });

  final Rect from;
  final Rect to;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<CardLanding> createState() => _CardLandingState();
}

class _CardLandingState extends State<CardLanding> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted) return;
    _controller
      ..duration = _motion(context, 250)
      ..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final settled = Curves.easeOutCubic.transform(_controller.value);
      final rect = Rect.lerp(widget.from, widget.to, settled)!;
      // As tall as the card is drawn, which can change as it lands in another column.
      return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        child: IgnorePointer(child: _lifted(1 - settled, child!)),
      );
    },
    child: widget.child,
  );
}

/// Slides [child] into a new place in its list, as cards on the web board do, rather than jumping
/// there.
class SlideOnReflow extends StatefulWidget {
  const SlideOnReflow({super.key, this.hitWhereLaidOut = false, required this.child});

  /// Whether it is hit where it is laid out rather than where it is drawn. While a card is
  /// carried, that keeps what lies under it settled as the others make room.
  final bool hitWhereLaidOut;
  final Widget child;

  @override
  State<SlideOnReflow> createState() => _SlideOnReflowState();
}

class _SlideOnReflowState extends State<SlideOnReflow> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );

  /// Where it was laid out along its list, which scrolling leaves alone.
  double? _top;

  /// How far above its place it starts sliding.
  double _from = 0;

  double get _offset => _from * (1 - Curves.easeOutCubic.transform(_controller.value));

  void _measure(Duration _) {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final top = viewport.getOffsetToReveal(box, 0).offset;
    final last = _top;
    _top = top;
    if (last == null || (last - top).abs() < 0.5) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    // From where it is painted now, which may be partway through an earlier slide.
    setState(() => _from = _offset + last - top);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_measure);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _offset),
        transformHitTests: !widget.hitWhereLaidOut,
        child: child,
      ),
      child: widget.child,
    );
  }
}
