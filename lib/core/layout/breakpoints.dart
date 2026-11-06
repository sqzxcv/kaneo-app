import 'package:flutter/widgets.dart';

/// Windows whose shorter side reaches this are wide, whichever way round they are.
const double wideLayoutMinShortestSide = 600;

/// Whether [size] uses the wide layout. A phone is narrow in both orientations and an iPad is wide
/// in both.
bool isWideSize(Size size) => size.shortestSide >= wideLayoutMinShortestSide;

extension LayoutContext on BuildContext {
  /// Whether this window uses the wide layout. Rebuilds the caller when the window size changes.
  bool get isWide => isWideSize(MediaQuery.sizeOf(this));
}
