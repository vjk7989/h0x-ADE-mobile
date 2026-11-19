import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Icon;

/// Motion tokens (design/tokens.md section 18). Every animation reads its
/// duration and curve from here: no literals in widgets.
class HxMotion {
  HxMotion._();

  // Durations.
  static const press = Duration(milliseconds: 90);
  static const keyPress = Duration(milliseconds: 60);
  static const sticky = Duration(milliseconds: 120);
  static const fadeThrough = Duration(milliseconds: 200);
  static const sharedAxis = Duration(milliseconds: 300);
  static const container = Duration(milliseconds: 350);
  static const stagger = Duration(milliseconds: 24);
  static const stateChange = Duration(milliseconds: 200);
  static const check = Duration(milliseconds: 240);
  static const intro = Duration(milliseconds: 900);
  static const introReduced = Duration(milliseconds: 150);

  /// At most this many items of a list stagger on first load.
  static const staggerItems = 6;

  // Curves.
  static const standard = Cubic(0.2, 0, 0, 1);
  static const emphasizedDecel = Cubic(0.05, 0.7, 0.1, 1);
  static const emphasizedAccel = Cubic(0.3, 0, 0.8, 0.15);

  // State layers (opacity of `foreground` over the control's fill).
  static const hoverLayer = 0.08;
  static const pressedLayer = 0.12;
  static const focusedLayer = 0.12;

  /// The press scale of a button, chip or key.
  static const pressScale = 0.97;

  /// "Remove animations" is on: no scale, slide or stagger; fades are short.
  static bool reduced(BuildContext c) => MediaQuery.disableAnimationsOf(c);

  /// [x], or 0 when motion is reduced, or at most 100 ms for a fade.
  static Duration d(BuildContext c, Duration x, {bool fade = false}) {
    if (!reduced(c)) return x;
    if (!fade) return Duration.zero;
    return Duration(milliseconds: math.min(x.inMilliseconds, 100));
  }
}
