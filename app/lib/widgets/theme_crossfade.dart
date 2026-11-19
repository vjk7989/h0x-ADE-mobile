import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../theme/motion.dart';

/// When the theme changes, the last frame of the old theme is laid over the
/// new one and fades 1 -> 0 over 250 ms. It is skipped with reduced motion,
/// and when taking the picture took longer than [maxCapture] (16 ms): a slow
/// phone should switch at once rather than stall.
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
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
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
                builder: (context, _) => Opacity(
                  opacity: (1 - _c.value).clamp(0.0, 1.0),
                  child: RawImage(image: _old, scale: ratio, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
