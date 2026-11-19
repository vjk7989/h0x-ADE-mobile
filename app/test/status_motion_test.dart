import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/widgets/status_motion.dart';
import 'package:material_ui/material_ui.dart';

import 'support/golden.dart';
import 'support/golden_expect.dart';

const _tone = Color(0xFFC9791F);
const _blue = Color(0xFF3B6FD4);
const _green = Color(0xFF2F8F5B);

Widget _board({bool done = false}) => Scaffold(
  body: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NeedsYouPulse(color: _tone, size: 12),
        const SizedBox(height: 24),
        const WorkingGlyph(color: _blue),
        const SizedBox(height: 24),
        DoneCheck(done: done, color: _green, size: 28),
        const SizedBox(height: 24),
        const StatusDot(color: _green, size: 12),
      ],
    ),
  ),
);

Future<void> _expectImage(WidgetTester t, ui.Image img, String name) =>
    expectLater(img, matchesGoldenFile('goldens/$name.png'));

void main() {
  setUp(() => StatusMotion.loops = true);
  tearDown(() => StatusMotion.loops = false);

  testWidgets('golden: pulse, spinner and the check draw, light', (t) async {
    var done = false;
    late StateSetter set;
    await pumpGolden(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          set = setState;
          return _board(done: done);
        },
      ),
      settle: false,
      frames: 1,
    );
    set(() => done = true);
    await t.pump();
    await _expectImage(
      t,
      await strip(t, times: const [0, 80, 160, 240, 400, 800, 1200], scale: 0.6),
      'status_strip_light',
    );
  });

  testWidgets('golden: reduced motion is static, light', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpGolden(t, _board(done: true), settle: false, frames: 1);
    await t.pump(const Duration(milliseconds: 500));
    expect(t.binding.transientCallbackCount, 0, reason: 'nothing runs');
    await expectGolden(find.byType(MaterialApp), 'status_reduce_motion_light');
  });

  group('limits', () {
    testWidgets('no more than 3 pulses run with 10 needs-you rows', (t) async {
      await pumpGolden(
        t,
        Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 10; i++)
                const SizedBox(height: 40, child: NeedsYouPulse(color: _tone)),
            ],
          ),
        ),
        settle: false,
        frames: 1,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(StatusMotion.activePulses, kMaxPulses);
    });

    testWidgets('the tickers stop when a route covers them', (t) async {
      await pumpGolden(
        t,
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const NeedsYouPulse(color: _tone),
                const WorkingGlyph(color: _blue),
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
        settle: false,
        frames: 1,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(t.binding.transientCallbackCount, greaterThan(0), reason: 'they run');
      await t.tap(find.text('cover'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('over'), findsOneWidget);
      expect(t.binding.transientCallbackCount, 0, reason: 'covered: no ticker runs');
    });

    testWidgets('a pulse scrolled out of the list stops and frees its slot', (t) async {
      final controller = ScrollController();
      await pumpGolden(
        t,
        Scaffold(
          body: ListView(
            controller: controller,
            children: const [
              SizedBox(height: 40, child: NeedsYouPulse(color: _tone)),
              SizedBox(height: 3000),
            ],
          ),
        ),
        settle: false,
        frames: 1,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(StatusMotion.activePulses, 1);
      controller.jumpTo(2000);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(StatusMotion.activePulses, 0);
    });
  });

  testWidgets('the done check draws only when the status changes', (t) async {
    var done = true;
    late StateSetter set;
    await pumpGolden(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          set = setState;
          return Center(child: DoneCheck(done: done, color: _green));
        },
      ),
      settle: false,
      frames: 1,
    );
    expect(t.binding.transientCallbackCount, 0, reason: 'first build: already drawn');
    set(() => done = false);
    await t.pump();
    set(() => done = true);
    await t.pump();
    expect(t.binding.transientCallbackCount, greaterThan(0), reason: 'now it draws');
    await t.pumpAndSettle();
  });
}
