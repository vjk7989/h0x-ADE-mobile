import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/themes.dart';

const _glyphs = r'01{}[]()<>=+-*/;:.$#&|_abcdefghijklmnopqrstuvwxyz0123456789';
const _colWidth = 9.6;
const _rowHeight = 15.0;
const _fontSize = 11.0;
const _stepEvery = Duration(milliseconds: 60);

/// The falling-code band behind the sign-in and unlock cards (design/tokens.md
/// section 8): JetBrains Mono 11, columns of about 9.6 dp, each a random run
/// that fades along its length with the head glyph in `accent`. It advances a
/// row every 60 ms (under 24 fps), and is still when the system asks for
/// fewer animations (or [codeRainAnimateProvider] is false, as in tests).
class CodeRain extends ConsumerStatefulWidget {
  const CodeRain({super.key, this.seed = 7, this.frame = 0});

  final int seed;

  /// The row offset when not animating.
  final int frame;

  @override
  ConsumerState<CodeRain> createState() => _CodeRainState();
}

/// Whether the band animates. Tests turn it off, with a fixed frame, so
/// goldens are stable and `pumpAndSettle` can settle.
final codeRainAnimateProvider = Provider<bool>((ref) => true);

class _CodeRainState extends ConsumerState<CodeRain>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _frame = widget.frame;
    _ticker = createTicker((elapsed) {
      final f = widget.frame + elapsed.inMilliseconds ~/ _stepEvery.inMilliseconds;
      if (f != _frame) setState(() => _frame = f);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        !ref.read(codeRainAnimateProvider) ||
        MediaQuery.disableAnimationsOf(context);
    if (still) {
      _ticker.stop();
      _frame = widget.frame;
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = dark ? c.accent : c.foreground;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
            stops: [0, 0.25, 0.6, 1],
          ).createShader(rect),
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _RainPainter(
                seed: widget.seed,
                frame: _frame,
                tint: tint,
                accent: c.accent,
                base: dark ? 0.10 : 0.08,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

final _painters = <String, TextPainter>{};

TextPainter _glyph(String ch, Color color) {
  final key = '$ch${color.toARGB32()}';
  return _painters.putIfAbsent(key, () {
    return TextPainter(
      text: TextSpan(
        text: ch,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: _fontSize,
          color: color,
          fontFeatures: const [FontFeature.disable('calt')],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  });
}

class _RainPainter extends CustomPainter {
  _RainPainter({
    required this.seed,
    required this.frame,
    required this.tint,
    required this.accent,
    required this.base,
  });

  final int seed;
  final int frame;
  final Color tint;
  final Color accent;

  /// The overall opacity: 0.10 on dark, 0.08 on light.
  final double base;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / _colWidth).ceil();
    final rows = (size.height / _rowHeight).ceil();
    for (var col = 0; col < cols; col++) {
      final rnd = Random(seed * 7919 + col);
      final run = 6 + rnd.nextInt(13);
      final speed = 1 + rnd.nextInt(2);
      final span = rows + run;
      final head = (rnd.nextInt(span) + frame * speed) % span;
      for (var k = 0; k < run; k++) {
        final row = head - k;
        if (row < 0 || row >= rows) continue;
        // A cell keeps its glyph while the run slides over it.
        final ch = _glyphs[(col * 31 + row * 17 + seed * 7 + row * col) % _glyphs.length];
        // 100 % at the head, fading to 35 % at the tail of the run.
        final fade = 1 - 0.65 * (k / max(run - 1, 1));
        final Color color;
        if (k == 0) {
          color = accent.withValues(alpha: base * 4);
        } else {
          color = tint.withValues(alpha: base * fade);
        }
        _glyph(ch, color).paint(
          canvas,
          Offset(col * _colWidth, row * _rowHeight),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) =>
      old.frame != frame ||
      old.seed != seed ||
      old.tint != tint ||
      old.accent != accent;
}
