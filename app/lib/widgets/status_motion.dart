import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/motion.dart';
import '../theme/type.dart';

/// A ticker that runs only while the widget is on screen: a covered route
/// stops it through [TickerMode], and a scroll position check stops it when
/// the widget has scrolled out of its list (no new dependency).
mixin VisibleTicker<T extends StatefulWidget> on State<T>, TickerProviderStateMixin<T> {
  ScrollPosition? _position;
  bool visible = true;

  /// Called when the widget enters or leaves the screen.
  void visibilityChanged(bool v);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _position) {
      _position?.removeListener(_check);
      _position = p?..addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (!mounted) return;
    final p = _position;
    final box = context.findRenderObject();
    var v = true;
    if (p != null && box is RenderBox && box.attached) {
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport != null) {
        final top = viewport.getOffsetToReveal(box, 0).offset;
        final bottom = top - p.viewportDimension + box.size.height;
        // On screen when the scroll offset is between both reveal offsets.
        v = p.pixels >= bottom - box.size.height && p.pixels <= top + box.size.height;
      }
    }
    if (v != visible) {
      visible = v;
      visibilityChanged(v);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }
}

/// How many pulses run at once; the others show a static ring.
const kMaxPulses = 3;
int _pulsing = 0;

/// Pulses that are on screen and want to run but found no free slot.
final _waiting = <_NeedsYouPulseState>{};

var _offerScheduled = false;

/// Slots were freed: hand them to waiting pulses that are still on screen
/// (next frame, never during a build or a dispose).
void _offerSlot() {
  if (_offerScheduled) return;
  _offerScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _offerScheduled = false;
    for (final w in [..._waiting]) {
      if (_pulsing >= kMaxPulses) return;
      if (!w.mounted) {
        _waiting.remove(w);
      } else {
        w.retry();
      }
    }
  });
}

class StatusMotion {
  StatusMotion._();

  /// The repeating loops (pulse, spinner) run. Tests that settle the tree
  /// switch this off (flutter_test_config.dart); the motion tests switch it on.
  static var loops = true;

  /// Pulses running now (at most [kMaxPulses]).
  @visibleForTesting
  static int get activePulses => _pulsing;
}

/// The needs-you dot with a ring that grows 1 -> 1.6 while it fades 0.5 -> 0
/// (1600 ms, repeating). At most [kMaxPulses] run at once. With reduced
/// motion: the dot and a static ring.
class NeedsYouPulse extends StatefulWidget {
  const NeedsYouPulse({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  State<NeedsYouPulse> createState() => _NeedsYouPulseState();
}

class _NeedsYouPulseState extends State<NeedsYouPulse>
    with TickerProviderStateMixin, VisibleTicker {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  var _owns = false;

  void _sync() {
    final want = visible && !HxMotion.reduced(context) && StatusMotion.loops;
    if (want && !_owns && _pulsing < kMaxPulses) {
      _pulsing++;
      _owns = true;
      _waiting.remove(this);
      _c.repeat();
    } else if (want && !_owns) {
      _waiting.add(this); // no slot now: wait for one
    } else if (!want) {
      _waiting.remove(this);
      if (_owns) _release();
    }
  }

  /// A slot is free: try to take it.
  void retry() => setState(_sync);

  void _release() {
    _pulsing--;
    _owns = false;
    _c.stop();
    _offerSlot();
  }

  @override
  void visibilityChanged(bool v) {
    setState(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    _waiting.remove(this);
    if (_owns) {
      _pulsing--;
      _owns = false;
      _offerSlot();
    }
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // The ring (1.5 dp) leaves the dot and grows to 2.2 x its radius
          // while it fades from 45 % to 0. When not pulsing: a static ring.
          final t = _owns ? _c.value : 0.0;
          final grow = _owns ? 1 + 1.2 * t : 1.6;
          final alpha = _owns ? 0.45 * (1 - t) : 0.3;
          return CustomPaint(
            painter: _PulsePainter(widget.color, grow, alpha),
          );
        },
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.color, this.grow, this.alpha);

  final Color color;
  final double grow;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      center,
      r * grow,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(center, r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.color != color || old.grow != grow || old.alpha != alpha;
}

const _braille = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

/// The braille spinner of a working agent, 100 ms per frame. Static (the
/// first frame) with reduced motion or when off screen.
class WorkingGlyph extends StatefulWidget {
  const WorkingGlyph({super.key, required this.color, this.style});

  final Color color;
  final TextStyle? style;

  @override
  State<WorkingGlyph> createState() => _WorkingGlyphState();
}

class _WorkingGlyphState extends State<WorkingGlyph>
    with TickerProviderStateMixin, VisibleTicker {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 100 * _braille.length),
  );

  void _sync() {
    if (visible && !HxMotion.reduced(context) && StatusMotion.loops) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void visibilityChanged(bool v) => _sync();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    // Mono 12 sp (never under 11), centred on the tag text beside it.
    builder: (context, _) => SizedBox(
      height: 16,
      child: Center(
        child: Text(
          _braille[(_c.value * _braille.length).floor() % _braille.length],
          textScaler: TextScaler.noScaling,
          style: (widget.style ?? HxType.mono).copyWith(
            color: widget.color,
            fontSize: 12,
            height: 1,
          ),
        ),
      ),
    ),
  );
}

/// A check mark. When [done] turns true after the first build, the stroke
/// draws once (240 ms); on first build it is already drawn.
class DoneCheck extends StatefulWidget {
  const DoneCheck({
    super.key,
    required this.done,
    required this.color,
    this.size = 14,
    this.drawIn = false,
    this.delay = Duration.zero,
  });

  /// Wait this long before the stroke starts (the tick fills first).
  final Duration delay;

  /// Draw the stroke when this widget is first built (the status just
  /// changed to done), instead of showing it drawn.
  final bool drawIn;
  final bool done;
  final Color color;
  final double size;

  @override
  State<DoneCheck> createState() => _DoneCheckState();
}

class _DoneCheckState extends State<DoneCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.delay + HxMotion.check,
    value: widget.drawIn ? 0 : 1,
  );

  double get _t => const Interval(0, 1).transform(
    ((_c.value * _c.duration!.inMilliseconds - widget.delay.inMilliseconds) /
            HxMotion.check.inMilliseconds)
        .clamp(0.0, 1.0),
  );

  @override
  void initState() {
    super.initState();
    if (widget.drawIn) _c.forward();
  }

  @override
  void didUpdateWidget(DoneCheck old) {
    super.didUpdateWidget(old);
    if (!old.done && widget.done && !HxMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: widget.done
        ? AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _CheckPainter(
                HxMotion.standard.transform(_t),
                widget.color,
              ),
            ),
          )
        : null,
  );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.55)
      ..lineTo(size.width * 0.42, size.height * 0.78)
      ..lineTo(size.width * 0.84, size.height * 0.26);
    final m = path.computeMetrics().first;
    canvas.drawPath(
      m.extractPath(0, m.length * t),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}

/// The online / offline dot: its colour tweens over 200 ms.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: HxMotion.d(context, HxMotion.stateChange, fade: true),
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A row or section that grows and fades in (200 ms), after [delay]. With
/// [animate] false, or reduced motion, it is simply there.
class Appear extends StatefulWidget {
  const Appear({
    super.key,
    required this.animate,
    this.delay = Duration.zero,
    required this.child,
  });

  final bool animate;
  final Duration delay;
  final Widget child;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _a;

  @override
  void initState() {
    super.initState();
    final total = widget.delay + HxMotion.stateChange;
    _c = AnimationController(vsync: this, duration: total, value: widget.animate ? 0 : 1);
    _a = CurvedAnimation(
      parent: _c,
      curve: Interval(
        widget.delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: HxMotion.standard,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.animate && !HxMotion.reduced(context) && _c.value == 0 && !_c.isAnimating) {
      _c.forward();
    } else if (HxMotion.reduced(context)) {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _a,
    axisAlignment: -1,
    child: FadeTransition(opacity: _a, child: widget.child),
  );
}

/// The desktop's list-done confetti: 36 pieces fall over 1500 ms, once. Not
/// shown with reduced motion.
class HxConfetti extends StatefulWidget {
  const HxConfetti({super.key});

  @override
  State<HxConfetti> createState() => _HxConfettiState();
}

class _HxConfettiState extends State<HxConfetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!HxMotion.reduced(context) && _c.value == 0 && !_c.isAnimating) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (HxMotion.reduced(context)) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _ConfettiPainter(
          _c.value,
          [c.primary, c.tertiary, c.secondary, const Color(0xFFE78A53)],
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.colors);

  final double t;
  final List<Color> colors;

  static const pieces = 36;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    for (var i = 0; i < pieces; i++) {
      // Fixed per piece (no random): spread, speed, spin and colour.
      final x = (i * 0.618034 % 1) * size.width;
      final speed = 0.6 + (i * 0.37 % 1) * 0.4;
      final y = -10 + (size.height + 20) * (t * speed);
      final sway = 14 * (i.isEven ? 1 : -1) * (t * (1 + i % 3));
      canvas.save();
      canvas.translate(x + sway, y);
      canvas.rotate(t * (2 + i % 5) * (i.isEven ? 1 : -1));
      canvas.drawRect(
        const Rect.fromLTWH(-3, -2, 6, 4),
        Paint()..color = colors[i % colors.length].withValues(alpha: (1 - t).clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
