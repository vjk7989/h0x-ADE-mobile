import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/widgets/intro.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import 'support/golden.dart';

/// The first screen the intro covers (the app is built under it from frame 0).
class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Machines')));
}

Widget _gate({bool reduce = false}) => Builder(
  builder: (context) {
    final w = const IntroGate(child: _App());
    return reduce
        ? MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: w,
          )
        : w;
  },
);

const _times = [0, 150, 300, 450, 600, 900];

Future<void> _shot(WidgetTester t, ui.Image img, String name) async {
  await expectLater(img, matchesGoldenFile('goldens/$name.png'));
}

void main() {
  setUp(HxIntro.resetForTest);

  testWidgets('golden: the intro strip, dark phone', (t) async {
    await _pumpFresh(t, Brightness.dark);
    await _shot(t, await strip(t, times: _times), 'intro_strip_dark');
    await t.pumpAndSettle();
  });

  testWidgets('golden: the intro strip, light phone', (t) async {
    await _pumpFresh(t, Brightness.light);
    await _shot(t, await strip(t, times: _times), 'intro_strip_light');
    await t.pumpAndSettle();
  });

  testWidgets('golden: the intro strip, dark tablet (the mark flies to the rail)', (t) async {
    await _pumpFresh(t, Brightness.dark, frame: Frame.tablet);
    await _shot(t, await strip(t, times: _times, scale: 0.35), 'intro_strip_tablet_dark');
    await t.pumpAndSettle();
  });

  testWidgets('golden: reduced motion shows the full mark at t = 0', (t) async {
    await _pumpFresh(t, Brightness.dark, reduce: true);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/intro_reduce_motion_dark.png'),
    );
    // then a 150 ms fade
    await t.pump(const Duration(milliseconds: 160));
    await t.pumpAndSettle();
    expect(find.byType(HxIntro), findsNothing);
  });

  group('behaviour', () {
    testWidgets('a tap skips to the hand-off', (t) async {
      await _pumpFresh(t, Brightness.dark);
      await t.pump(const Duration(milliseconds: 100));
      double word() => t
          .widget<Opacity>(
            find.ancestor(of: find.text('HyperOx'), matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(word(), 0.0, reason: 'the wordmark is not up at 100 ms');
      await t.tapAt(const Offset(180, 400));
      await t.pump(const Duration(milliseconds: 1));
      expect(word(), 1.0, reason: 'a tap jumps to 560 ms: the wordmark is up');
      await t.pumpAndSettle();
      expect(find.byType(HxIntro), findsNothing);
    });

    test('it is shown once per process', () {
      expect(HxIntro.shouldShow, isTrue);
      HxIntro.markShown();
      expect(HxIntro.shouldShow, isFalse);
    });

    testWidgets('a second gate in the same process shows nothing', (t) async {
      await _pumpFresh(t, Brightness.dark);
      await t.pumpAndSettle();
      expect(find.byType(HxIntro), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        const MaterialApp(home: IntroGate(child: _App())),
      );
      expect(find.byType(HxIntro), findsNothing);
    });

    testWidgets('a deep link is not covered by the intro', (t) async {
      t.platformDispatcher.defaultRouteNameTestValue = '/m/studio';
      addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
      expect(HxIntro.shouldShow, isFalse);
      await t.pumpWidget(const MaterialApp(home: IntroGate(child: _App())));
      expect(find.byType(HxIntro), findsNothing);
    });

    testWidgets('no ticker is left running after it is done', (t) async {
      await _pumpFresh(t, Brightness.dark);
      expect(t.binding.transientCallbackCount, greaterThan(0));
      await t.pump(const Duration(milliseconds: 1000));
      await t.pumpAndSettle();
      expect(find.byType(HxIntro), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('the app underneath is there from the first frame', (t) async {
      await _pumpFresh(t, Brightness.dark);
      expect(find.text('Machines'), findsOneWidget);
    });
  });
}

/// Pumps a fresh gate (the flag reset) without running any animation frame.
Future<void> _pumpFresh(
  WidgetTester t,
  Brightness b, {
  Frame frame = Frame.phone,
  bool reduce = false,
}) async {
  HxIntro.resetForTest();
  await pumpGolden(
    t,
    _gate(reduce: reduce),
    brightness: b,
    frame: frame,
    settle: false,
    insets: false,
    frames: 0,
  );
}
