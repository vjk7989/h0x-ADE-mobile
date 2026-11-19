import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/widgets/status_motion.dart';
import 'package:material_ui/material_ui.dart';

import 'support/golden.dart';

const _tone = Color(0xFFC9791F);
const _blue = Color(0xFF3B6FD4);
const _green = Color(0xFF2F8F5B);

void _reduce(WidgetTester t) {
  t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Widget _pulseRow() => const SizedBox(height: 40, child: NeedsYouPulse(color: _tone));

Future<void> _pump(WidgetTester t, Widget w) async {
  await pumpGolden(t, w, settle: false, frames: 1);
}

void main() {
  setUp(() => StatusMotion.loops = true);
  tearDown(() => StatusMotion.loops = false);

  group('NeedsYouPulse cap', () {
    testWidgets('three lists of ten: still at most 3 pulse', (t) async {
      await _pump(
        t,
        Scaffold(
          body: Row(
            children: [
              for (var l = 0; l < 3; l++)
                Expanded(
                  child: ListView(children: [for (var i = 0; i < 10; i++) _pulseRow()]),
                ),
            ],
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(StatusMotion.activePulses, kMaxPulses);
    });

    testWidgets('exactly 3 rows: all 3 pulse; 2 rows: 2 pulse', (t) async {
      for (final n in [3, 2, 4]) {
        await t.pumpWidget(const SizedBox());
        expect(StatusMotion.activePulses, 0);
        await _pump(t, Scaffold(body: ListView(children: [for (var i = 0; i < n; i++) _pulseRow()])));
        await t.pump(const Duration(milliseconds: 100));
        expect(StatusMotion.activePulses, n < kMaxPulses ? n : kMaxPulses, reason: '$n rows');
      }
    });

    testWidgets('taking the rows away gives every slot back', (t) async {
      await _pump(t, Scaffold(body: ListView(children: [for (var i = 0; i < 10; i++) _pulseRow()])));
      await t.pump(const Duration(milliseconds: 100));
      expect(StatusMotion.activePulses, 3);
      await t.pumpWidget(const SizedBox());
      expect(StatusMotion.activePulses, 0, reason: 'no slot leaks after dispose');
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('a removed pulsing row frees its slot for a new row', (t) async {
      late StateSetter set;
      var rows = [0, 1, 2];
      await _pump(
        t,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Scaffold(
              body: Column(
                children: [
                  for (final r in rows)
                    SizedBox(
                      key: ValueKey(r),
                      height: 40,
                      child: const NeedsYouPulse(color: _tone),
                    ),
                ],
              ),
            );
          },
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(StatusMotion.activePulses, 3);
      set(() => rows = [1, 2]);
      await t.pump();
      expect(StatusMotion.activePulses, 2);
      set(() => rows = [1, 2, 7]);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(StatusMotion.activePulses, 3, reason: 'the new row takes the slot');
    });

    testWidgets('a slot freed by scrolling goes to a visible row that waited', (t) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      // Under the 32 dp status bar inset: rows at 32, 72, 112 (they take the
      // 3 slots), a gap, then rows at 232 and 272 that wait with a static ring.
      await _pump(
        t,
        Scaffold(
          body: ListView(
            controller: controller,
            children: [
              _pulseRow(),
              _pulseRow(),
              _pulseRow(),
              const SizedBox(height: 80),
              _pulseRow(),
              _pulseRow(),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(StatusMotion.activePulses, 3);
      // The first three scroll out; the two waiting rows stay on screen.
      controller.jumpTo(200);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(
        StatusMotion.activePulses,
        2,
        reason: 'the two visible needs-you rows should pulse once slots are free',
      );
    });

    testWidgets('scrolling back in takes a slot again', (t) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        t,
        Scaffold(
          body: ListView(
            controller: controller,
            children: [_pulseRow(), const SizedBox(height: 3000)],
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      controller.jumpTo(2000);
      await t.pump();
      expect(StatusMotion.activePulses, 0);
      controller.jumpTo(0);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(StatusMotion.activePulses, 1);
      expect(t.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('scroll edge: 1 px still on screen pulses, fully off does not', (t) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        t,
        Scaffold(
          body: ListView(
            controller: controller,
            children: [_pulseRow(), const SizedBox(height: 3000)],
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      // The row sits at 32..72 (the list pads for the 32 dp status bar).
      controller.jumpTo(71);
      await t.pump();
      expect(StatusMotion.activePulses, 1, reason: '1 dp of the row is still visible');
      controller.jumpTo(73);
      await t.pump();
      expect(StatusMotion.activePulses, 0, reason: 'fully scrolled out');
    });

    testWidgets('a covered route pauses, and the pulse runs again when uncovered', (t) async {
      await _pump(
        t,
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const NeedsYouPulse(color: _tone),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('over'))),
                  ),
                  child: const Text('cover'),
                ),
              ],
            ),
          ),
        ),
      );
      await t.tap(find.text('cover'));
      await t.pumpAndSettle();
      expect(t.binding.transientCallbackCount, 0, reason: 'covered: paused');
      Navigator.of(t.element(find.text('over'))).pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 16));
      expect(t.binding.transientCallbackCount, greaterThan(0), reason: 'uncovered: runs');
    });

    testWidgets('reduced motion: no pulse at all, no slot taken, static ring', (t) async {
      _reduce(t);
      await _pump(t, Scaffold(body: ListView(children: [for (var i = 0; i < 5; i++) _pulseRow()])));
      await t.pump(const Duration(milliseconds: 500));
      expect(StatusMotion.activePulses, 0);
      expect(t.binding.transientCallbackCount, 0);
    });
  });

  group('WorkingGlyph', () {
    testWidgets('100 ms per frame: 99 ms is the first glyph, 101 ms the second', (t) async {
      await t.pumpWidget(
        const MaterialApp(home: Scaffold(body: Center(child: WorkingGlyph(color: _blue)))),
      );
      await t.pump();
      expect(find.text('⠋'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 99));
      expect(find.text('⠋'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 2));
      expect(find.text('⠙'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('reduced motion: the first glyph, still', (t) async {
      _reduce(t);
      await _pump(t, const Scaffold(body: Center(child: WorkingGlyph(color: _blue))));
      await t.pump(const Duration(milliseconds: 750));
      expect(find.text('⠋'), findsOneWidget);
      expect(t.binding.transientCallbackCount, 0);
    });
  });

  group('DoneCheck', () {
    testWidgets('reduced motion: a check that draws in on first build is drawn at once', (t) async {
      _reduce(t);
      await _pump(
        t,
        const Scaffold(body: Center(child: DoneCheck(done: true, drawIn: true, color: _green))),
      );
      expect(t.binding.transientCallbackCount, 0, reason: 'reduced: static, no draw');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('reduced motion: a status change to done does not draw', (t) async {
      _reduce(t);
      var done = false;
      late StateSetter set;
      await _pump(
        t,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Center(child: DoneCheck(done: done, color: _green));
          },
        ),
      );
      set(() => done = true);
      await t.pump();
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('done flipped off and on mid-draw does not throw and ends drawn', (t) async {
      var done = false;
      late StateSetter set;
      await _pump(
        t,
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Center(child: DoneCheck(done: done, color: _green));
          },
        ),
      );
      set(() => done = true);
      await t.pump(const Duration(milliseconds: 60));
      set(() => done = false);
      await t.pump(const Duration(milliseconds: 20));
      set(() => done = true);
      await t.pump(const Duration(milliseconds: 20));
      expect(t.takeException(), isNull);
      await t.pump(const Duration(milliseconds: 250));
      await t.pump();
      expect(t.binding.transientCallbackCount, 0);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('with a delay the stroke waits, then takes 240 ms', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DoneCheck(
                done: true,
                drawIn: true,
                color: _green,
                delay: Duration(milliseconds: 150),
              ),
            ),
          ),
        ),
      );
      // It starts in the frame it is built in, and runs 150 + 240 ms.
      await t.pump(const Duration(milliseconds: 389));
      expect(t.binding.transientCallbackCount, greaterThan(0), reason: 'still drawing');
      await t.pump(const Duration(milliseconds: 2));
      expect(t.binding.transientCallbackCount, 0, reason: 'done after 390 ms');
    });
  });

  group('StatusDot, Appear, confetti', () {
    testWidgets('the dot colour tween is 200 ms, or a 100 ms fade when reduced', (t) async {
      await _pump(t, const Scaffold(body: Center(child: StatusDot(color: _green))));
      expect(t.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
          const Duration(milliseconds: 200));
      await t.pumpWidget(const SizedBox());
      _reduce(t);
      await _pump(t, const Scaffold(body: Center(child: StatusDot(color: _green))));
      expect(t.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
          const Duration(milliseconds: 100));
    });

    testWidgets('Appear: closed until its delay, open 200 ms after', (t) async {
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Appear(
              animate: true,
              delay: Duration(milliseconds: 48),
              child: SizedBox(height: 40, child: Text('row')),
            ),
          ),
        ),
      );
      double size() => t.widget<SizeTransition>(find.byType(SizeTransition)).sizeFactor.value;
      await t.pump();
      await t.pump(const Duration(milliseconds: 47));
      expect(size(), 0.0, reason: 'inside the 48 ms delay');
      await t.pump(const Duration(milliseconds: 202));
      expect(size(), 1.0);
      await t.pump();
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('Appear with reduced motion: open at once, no ticker', (t) async {
      _reduce(t);
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Appear(
              animate: true,
              delay: Duration(milliseconds: 144),
              child: SizedBox(height: 40, child: Text('row')),
            ),
          ),
        ),
      );
      expect(t.widget<SizeTransition>(find.byType(SizeTransition)).sizeFactor.value, 1.0);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('confetti: 1500 ms once, then nothing; none when reduced', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: HxConfetti())));
      await t.pump();
      await t.pump(const Duration(milliseconds: 1499));
      expect(t.binding.transientCallbackCount, greaterThan(0));
      await t.pump(const Duration(milliseconds: 2));
      await t.pump();
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpWidget(const SizedBox());
      _reduce(t);
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: HxConfetti())));
      expect(t.binding.transientCallbackCount, 0);
      expect(
        find.descendant(of: find.byType(HxConfetti), matching: find.byType(CustomPaint)),
        findsNothing,
      );
    });
  });
}
