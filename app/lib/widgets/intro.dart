import 'dart:math' as math;
import 'dart:ui' as ui;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show SynchronousFuture, debugPrint, kDebugMode, kProfileMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../theme/motion.dart';
import '../theme/type.dart';
import 'app_shell.dart';
import 'code_rain.dart';
import 'hx.dart';

/// The mark of the native splash and the launcher icon, in dp inside the
/// 288 dp splash icon (Android 12 draws an icon with no background at 288 dp;
/// tools/gen_icons.py: step 2.06 of a 108 dp canvas).
const double kIntroStep = 2.06 * 288 / 108;
const double kIntroMarkWidth = 21 * kIntroStep;
const double kIntroMarkHeight = 25 * kIntroStep;

const _accent = Color(0xFFE78A53);
const _dark = Color(0xFF121113);
const _light = Color(0xFFFAFAF9);
const _foregroundDark = Color(0xFFC1C1C1);
const _foregroundLight = Color(0xFF1B1B1E);

/// The cold-start intro (PLAN-motion section 2): one controller, one painter.
/// It starts on the pixels of the native splash (same background, same mark,
/// same place), lights the dots in a diagonal sweep (0 to 420 ms), settles
/// with one pulse and the wordmark (420 to 560), and hands off (560 to 900):
/// on a phone the mark shrinks and the overlay fades; on a tablet the mark
/// flies to the rail's mark. A tap skips to the hand-off. With reduced motion
/// the full mark shows and fades in 150 ms. It never holds the app: the app is
/// built underneath from the first frame.
class HxIntro extends StatefulWidget {
  const HxIntro({super.key, required this.onDone});

  final VoidCallback onDone;

  static var _shown = false;

  /// Only once per process, and not when the app was opened on a deep link.
  static bool get shouldShow =>
      !_shown &&
      WidgetsBinding.instance.platformDispatcher.defaultRouteName == '/';

  static void markShown() => _shown = true;

  /// Starts at the beginning of main(): the timestamps in the log line.
  static final clock = Stopwatch();

  /// Completes when the user can see a frame (tests complete it at once).
  @visibleForTesting
  static Future<void> Function() firstFrame = () =>
      WidgetsBinding.instance.waitUntilFirstFrameRasterized;

  @visibleForTesting
  static void resetForTest() {
    _shown = false;
    firstFrame = () => SynchronousFuture<void>(null);
  }

  @override
  State<HxIntro> createState() => _HxIntroState();
}

class _HxIntroState extends State<HxIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  var _reduced = false;

  static const _total = 900.0;
  static const _skipTo = 560.0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: HxMotion.intro)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          _log('done');
          widget.onDone();
        }
      });
  }

  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = HxMotion.reduced(context);
    _c.duration = _reduced ? HxMotion.introReduced : HxMotion.intro;
    // The first frame (dots at 25 %) is drawn first; t = 0 is the first frame
    // the user can see, not the first build.
    HxIntro.firstFrame().then((_) {
      if (!mounted) return;
      _log('firstFrameRasterized');
      _log('start');
      _c.forward(from: 0);
    });
  }

  final _marks = <String, int>{};

  /// One line in debug and profile builds: `HxIntro: firstFrameRasterized +Xms,
  /// start +Yms, done +Zms` (from main()).
  void _log(String what) {
    if (!kDebugMode && !kProfileMode) return;
    _marks[what] = HxIntro.clock.elapsedMilliseconds;
    if (what != 'done') return;
    final line =
        'HxIntro: firstFrameRasterized +${_marks['firstFrameRasterized']}ms, '
        'start +${_marks['start']}ms, done +${_marks['done']}ms';
    if (kDebugMode) {
      debugPrint(line);
    } else {
      developer.Timeline.instantSync(line);
      // ignore: avoid_print
      print(line);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (_reduced) return;
    if (_c.value * _total < _skipTo) _c.forward(from: _skipTo / _total);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // The app's resolved mode (the splash follows it too), not the system's.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final wide = size.width >= kRailBreakpoint;
    final top = MediaQuery.paddingOf(context).top;
    final ink = dark ? _foregroundDark : _foregroundLight;
    return Positioned.fill(
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _reduced ? 0.0 : _c.value * _total;
              final fade = _reduced
                  ? 1 - HxMotion.standard.transform(_c.value)
                  : 1 -
                      HxMotion.emphasizedDecel.transform(
                        ((t - 620) / 280).clamp(0.0, 1.0),
                      );
              final word = _reduced
                  ? 0.0
                  : HxMotion.standard.transform(((t - 420) / 140).clamp(0.0, 1.0));
              final center = Offset(size.width / 2, size.height / 2);
              return Opacity(
                opacity: fade.clamp(0.0, 1.0),
                child: ColoredBox(
                  color: dark ? _dark : _light,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // The code band, static at 6 %.
                      Opacity(
                        opacity: 0.6,
                        child: ProviderScope(
                          overrides: [codeRainAnimateProvider.overrideWithValue(false)],
                          child: const CodeRain(),
                        ),
                      ),
                      CustomPaint(
                        painter: _IntroPainter(
                          t: t,
                          reduced: _reduced,
                          size: size,
                          wide: wide,
                          top: top,
                          dark: dark,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: center.dy + kIntroMarkHeight / 2 + 24 + 8 * (1 - word),
                        child: Opacity(
                          opacity: word,
                          child: Text(
                            'HyperOx',
                            textAlign: TextAlign.center,
                            style: HxType.display.copyWith(
                              color: ink,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _IntroPainter extends CustomPainter {
  _IntroPainter({
    required this.t,
    required this.reduced,
    required this.size,
    required this.wide,
    required this.top,
    required this.dark,
  });

  final bool dark;
  final double t;
  final bool reduced;
  final Size size;
  final bool wide;
  final double top;

  @override
  void paint(Canvas canvas, Size _) {
    final center = Offset(size.width / 2, size.height / 2);
    var width = kIntroMarkWidth;
    var origin = center - const Offset(kIntroMarkWidth / 2, kIntroMarkHeight / 2);
    var scale = 1.0;
    if (!reduced) {
      if (t >= 420 && t < 560) {
        // Settle: one pulse, 1 -> 1.04 -> 1.
        scale = 1 + 0.04 * math.sin(math.pi * (t - 420) / 140);
      } else if (t >= 560) {
        final u = HxMotion.emphasizedDecel.transform(((t - 560) / 340).clamp(0.0, 1.0));
        if (wide) {
          // To the rail's mark: left 26, top inset + 16, 28 wide.
          width = ui.lerpDouble(kIntroMarkWidth, 28, u)!;
          final target = Offset(26, top + 16);
          origin = Offset.lerp(origin, target, u)!;
        } else {
          scale = ui.lerpDouble(1, 0.92, u)!;
        }
      }
    }
    final step = width / 21;
    final markH = step * 25;
    final box = Rect.fromLTWH(origin.dx, origin.dy, width, markH);
    canvas.save();
    if (scale != 1) {
      canvas.translate(box.center.dx, box.center.dy);
      canvas.scale(scale);
      canvas.translate(-box.center.dx, -box.center.dy);
    }
    // The wave colour: lighter on dark, darker on light (stays visible).
    final hot = dark
        ? Color.lerp(_accent, const Color(0xFFFFFFFF), 0.55)!
        : Color.lerp(_accent, const Color(0xFF000000), 0.25)!;
    final rows = HxMark.rows;
    // Icons use heavier dots than the in-app mark: 0.36 of the step.
    final radius = step * 0.36;
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < 21; c++) {
        if (rows[r][c] != '1') continue;
        // Lit like the native splash at t = 0. A highlight wave runs over
        // the dots: the dot on diagonal d = c + r starts at d x 6.8 ms, and
        // over 160 ms its intensity goes 0 -> 1 -> 0 (ease in and out).
        final u = reduced ? 0.0 : ((t - (c + r) * 6.8) / 160).clamp(0.0, 1.0);
        final h = 0.5 - 0.5 * math.cos(2 * math.pi * u);
        canvas.drawCircle(
          Offset(box.left + (c + 0.5) * step, box.top + (r + 0.5) * step),
          radius * (1 + 0.35 * h),
          Paint()..color = Color.lerp(_accent, hot, h)!,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IntroPainter old) =>
      old.t != t || old.dark != dark || old.size != size || old.wide != wide || old.reduced != reduced;
}

/// Shows [HxIntro] over [child] once per process on a cold start, then drops
/// it from the tree (no ticker is left running).
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.child});

  final Widget child;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  late var _show = HxIntro.shouldShow;

  @override
  void initState() {
    super.initState();
    if (_show) HxIntro.markShown();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_show) HxIntro(onDone: () => setState(() => _show = false)),
      ],
    );
  }
}
