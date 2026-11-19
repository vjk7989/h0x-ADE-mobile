import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/theme/motion.dart';
import 'package:material_ui/material_ui.dart';

/// Runs [body] with a context whose MediaQuery has [reduce] for
/// "remove animations".
Future<void> _withContext(
  WidgetTester t,
  bool reduce,
  void Function(BuildContext c) body,
) async {
  await t.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Builder(
        builder: (c) {
          body(c);
          return const SizedBox();
        },
      ),
    ),
  );
}

void main() {
  test('the tokens are the tokens.md section 18 values', () {
    expect(HxMotion.press, const Duration(milliseconds: 90));
    expect(HxMotion.fadeThrough, const Duration(milliseconds: 200));
    expect(HxMotion.sharedAxis, const Duration(milliseconds: 300));
    expect(HxMotion.container, const Duration(milliseconds: 350));
    expect(HxMotion.stagger, const Duration(milliseconds: 24));
    expect(HxMotion.staggerItems, 6);
    expect(HxMotion.stateChange, const Duration(milliseconds: 200));
    expect(HxMotion.check, const Duration(milliseconds: 240));
    expect(HxMotion.intro, const Duration(milliseconds: 900));
    expect(HxMotion.introReduced, const Duration(milliseconds: 150));
    expect(HxMotion.standard, const Cubic(0.2, 0, 0, 1));
    expect(HxMotion.emphasizedDecel, const Cubic(0.05, 0.7, 0.1, 1));
    expect(HxMotion.emphasizedAccel, const Cubic(0.3, 0, 0.8, 0.15));
    expect(HxMotion.hoverLayer, 0.08);
    expect(HxMotion.pressedLayer, 0.12);
    expect(HxMotion.focusedLayer, 0.12);
    expect(HxMotion.pressScale, 0.97);
  });

  group('HxMotion.d', () {
    testWidgets('full motion: every duration is kept, zero included', (t) async {
      await _withContext(t, false, (c) {
        expect(HxMotion.reduced(c), isFalse);
        for (final ms in [0, 1, 99, 100, 101, 900]) {
          final x = Duration(milliseconds: ms);
          expect(HxMotion.d(c, x), x);
          expect(HxMotion.d(c, x, fade: true), x);
        }
      });
    });

    testWidgets('reduced: a move is 0 at any length', (t) async {
      await _withContext(t, true, (c) {
        expect(HxMotion.reduced(c), isTrue);
        for (final ms in [0, 1, 99, 100, 101, 900]) {
          expect(HxMotion.d(c, Duration(milliseconds: ms)), Duration.zero);
        }
      });
    });

    testWidgets('reduced: a fade is capped at 100 ms, both sides of the cap', (t) async {
      await _withContext(t, true, (c) {
        Duration f(int ms) => HxMotion.d(c, Duration(milliseconds: ms), fade: true);
        expect(f(0), Duration.zero);
        expect(f(99), const Duration(milliseconds: 99));
        expect(f(100), const Duration(milliseconds: 100));
        expect(f(101), const Duration(milliseconds: 100));
        expect(f(250), const Duration(milliseconds: 100));
      });
    });

    testWidgets('reduced: sub-millisecond fades are not rounded up', (t) async {
      await _withContext(t, true, (c) {
        // 500 us is below 1 ms; the cap never makes a fade longer.
        final d = HxMotion.d(c, const Duration(microseconds: 500), fade: true);
        expect(d <= const Duration(microseconds: 500), isTrue);
      });
    });
  });
}
