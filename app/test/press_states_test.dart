import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/state/key_input.dart';
import 'package:hyperox/widgets/hx.dart';
import 'package:hyperox/widgets/key_bar.dart';
import 'package:material_ui/material_ui.dart' hide Key;

import 'support/golden.dart';
import 'support/golden_expect.dart';

const _kinds = [
  (HxButtonKind.primary, 'Save'),
  (HxButtonKind.secondary, 'Edit'),
  (HxButtonKind.outline, 'Skip'),
  (HxButtonKind.danger, 'Del'),
];

/// 4 kinds (rows) x rest / pressed / focused / disabled (columns).
Widget _grid({bool reduce = false}) => Builder(
  builder: (context) {
    final w = Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              for (final (kind, label) in _kinds)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    children: [
                      for (final state in ['rest', 'pressed', 'focused', 'disabled']) ...[
                        Expanded(
                          child: HxButton(
                            key: ValueKey('$label-$state'),
                            label: label,
                            kind: kind,
                            minHeight: 48,
                            focusRingForTesting: state == 'focused',
                            onPressed: state == 'disabled' ? null : () {},
                          ),
                        ),
                        if (state != 'disabled') const SizedBox(width: 12),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return reduce
        ? MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: w,
          )
        : w;
  },
);

Future<List<TestGesture>> _holdPressed(WidgetTester t) async {
  final gestures = <TestGesture>[];
  var pointer = 1;
  for (final (_, label) in _kinds) {
    gestures.add(
      await t.startGesture(t.getCenter(find.byKey(ValueKey('$label-pressed'))), pointer: pointer++),
    );
  }
  // 300 ms in: the 90 ms press scale has landed and the 200 ms state layer
  // fade is complete, so the pressed look is at full strength.
  await t.pump(const Duration(milliseconds: 300));
  return gestures;
}

void main() {
  for (final dark in [false, true]) {
    final tag = dark ? 'dark' : 'light';
    testWidgets('golden: button states, $tag', (t) async {
      await pumpGolden(
        t,
        _grid(),
        brightness: dark ? Brightness.dark : Brightness.light,
      );
      final gestures = await _holdPressed(t);
      await expectGolden(find.byType(MaterialApp), 'press_states_$tag');
      for (final g in gestures) {
        await g.cancel();
      }
      await t.pumpAndSettle();
    });
  }

  testWidgets('golden: pressed with reduced motion, state layer only, light', (t) async {
    await pumpGolden(t, _grid(reduce: true));
    expect(find.byType(AnimatedScale), findsNothing, reason: 'no scale when reduced');
    final gestures = await _holdPressed(t);
    await expectGolden(find.byType(MaterialApp), 'press_states_reduce_motion_light');
    for (final g in gestures) {
      await g.cancel();
    }
    await t.pumpAndSettle();
  });

  group('HxPressable', () {
    testWidgets('a press scales to 0.97 and back; a release taps', (t) async {
      var taps = 0;
      await pumpGolden(
        t,
        Scaffold(
          body: Center(
            child: HxButton(label: 'Go', onPressed: () => taps++),
          ),
        ),
      );
      double scale() => t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      expect(scale(), 1.0);
      final g = await t.startGesture(t.getCenter(find.text('Go')));
      await t.pump(const Duration(milliseconds: 100));
      expect(scale(), 0.97);
      await g.up();
      await t.pumpAndSettle();
      expect(scale(), 1.0);
      expect(taps, 1);
    });

    testWidgets('with reduced motion no scale widget is built for a press', (t) async {
      await pumpGolden(t, _grid(reduce: true));
      final g = await t.startGesture(t.getCenter(find.byKey(const ValueKey('Save-pressed'))));
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byType(AnimatedScale), findsNothing);
      await g.cancel();
    });

    testWidgets('the focus ring shows for keyboard focus, not for touch', (t) async {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await pumpGolden(
        t,
        Scaffold(body: Center(child: HxButton(label: 'Go', onPressed: () {}))),
      );
      final ring = find.byWidgetPredicate((w) => w is Positioned && w.left == -4);
      expect(ring, findsNothing);
      Focus.maybeOf(t.element(find.text('Go')))!.requestFocus();
      await t.pumpAndSettle();
      expect(ring, findsOneWidget, reason: 'keyboard mode');
      Focus.maybeOf(t.element(find.text('Go')))!.unfocus();
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      await t.pumpAndSettle();
      Focus.maybeOf(t.element(find.text('Go')))!.requestFocus();
      await t.pumpAndSettle();
      expect(ring, findsNothing, reason: 'touch mode');
    });

    testWidgets('a disabled button does not tap', (t) async {
      await pumpGolden(
        t,
        const Scaffold(body: Center(child: HxButton(label: 'Go', onPressed: null))),
      );
      await t.tap(find.text('Go'));
      await t.pump();
    });
  });

  group('KeyBar states', () {
    Widget bar(Modifiers m) => KeyBar(modifiers: m, onKeys: (_) {});

    testWidgets('golden: rest, Esc pressed, Ctrl one-shot, Ctrl locked, dark', (t) async {
      final once = Modifiers()..tapCtrl();
      final locked = Modifiers()
        ..tapCtrl()
        ..tapCtrl();
      await pumpGolden(
        t,
        Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              bar(Modifiers()),
              const SizedBox(height: 24),
              bar(Modifiers()),
              const SizedBox(height: 24),
              bar(once),
              const SizedBox(height: 24),
              bar(locked),
            ],
          ),
        ),
        brightness: Brightness.dark,
      );
      final g = await t.startGesture(t.getCenter(find.text('Esc').at(1)));
      await t.pump(const Duration(milliseconds: 300));
      await expectGolden(find.byType(MaterialApp), 'keybar_states_dark');
      await g.cancel();
      await t.pumpAndSettle();
    });

    testWidgets('a key press gives a selection click', (t) async {
      final calls = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'HapticFeedback.vibrate') calls.add('${c.arguments}');
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final pressed = <String>[];
      await pumpGolden(
        t,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: KeyBar(modifiers: Modifiers(), onKeys: (k) => pressed.add(k.first.name)),
          ),
        ),
      );
      await t.tap(find.text('Esc'));
      await t.pump();
      expect(calls, contains('HapticFeedbackType.selectionClick'));
      expect(pressed, ['esc']);
    });

    testWidgets('Ctrl goes rest, one-shot, locked, rest with the state animating', (t) async {
      final m = Modifiers();
      await pumpGolden(
        t,
        Scaffold(body: Align(alignment: Alignment.bottomCenter, child: bar(m))),
      );
      await t.tap(find.text('Ctrl'));
      await t.pump(const Duration(milliseconds: 60));
      expect(m.ctrl, Sticky.once);
      await t.pump(const Duration(milliseconds: 200));
      await t.tap(find.text('Ctrl'));
      await t.pumpAndSettle();
      expect(m.ctrl, Sticky.locked);
      await t.tap(find.text('Ctrl'));
      await t.pumpAndSettle();
      expect(m.ctrl, Sticky.off);
    });
  });
}
