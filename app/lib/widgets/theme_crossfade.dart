import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../theme/motion.dart';

/// Where the next theme switch is revealed from: the centre of the tapped
/// theme row (the screen centre when nobody said).
class ThemeReveal {
  ThemeReveal._();

  static Offset? origin;

  /// Remember the centre of the widget at [context] as the next origin.
  static void from(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      origin = box.localToGlobal(box.size.center(Offset.zero));
    }
  }
}

/// When the theme changes, the new theme is revealed in a circle that grows
/// from the tapped row (400 ms, emphasized decel) to the far corner; the last
/// frame of the old theme stays visible outside the circle, so no frame mixes
/// the two. It is skipped with reduced motion, and when taking the picture
/// took longer than [maxCapture] (16 ms): a slow phone should switch at once
/// rather than stall.
class ThemeCrossFade extends StatefulWidget {
  const ThemeCrossFade({
    super.key,
    required this.child,
    this.maxCapture = const Duration(milliseconds: 16),
  });

  final Widget child;
  final Duration maxCapture;

  @override
  State<ThemeCrossFade> createState() => _ThemeCrossFadeState();
}

class _ThemeCrossFadeState extends State<ThemeCrossFade>
    with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  ui.Image? _old;
  ColorScheme? _scheme;
  Offset _center = Offset.zero;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) _drop();
    });

  void _drop() {
    if (_old == null) return;
    setState(() {
      _old!.dispose();
      _old = null;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scheme = Theme.of(context).colorScheme;
    final before = _scheme;
    _scheme = scheme;
    if (before == null || before == scheme || HxMotion.reduced(context)) return;
    // This runs before the new theme is painted: the boundary still holds the
    // last frame of the old one.
    final box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary || !box.hasSize || box.debugNeedsPaint) return;
    final watch = Stopwatch()..start();
    final shot = box.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
    if (watch.elapsed > widget.maxCapture) {
      shot.dispose();
      return;
    }
    _old?.dispose();
    _old = shot;
    _center = ThemeReveal.origin ?? box.size.center(Offset.zero);
    ThemeReveal.origin = null;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _old?.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (_old != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => ClipPath(
                  clipper: _OutsideCircle(
                    _center,
                    HxMotion.emphasizedDecel.transform(_c.value),
                  ),
                  child: RawImage(image: _old, scale: ratio, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Everything except a circle that grows from [center] to the farthest corner
/// ([t] is 0 to 1).
class _OutsideCircle extends CustomClipper<Path> {
  _OutsideCircle(this.center, this.t);

  final Offset center;
  final double t;

  @override
  Path getClip(Size size) {
    final far = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - center).distance).reduce((a, b) => a > b ? a : b);
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(Rect.fromCircle(center: center, radius: far * t)),
    );
  }

  @override
  bool shouldReclip(_OutsideCircle old) => old.t != t || old.center != center;
}
