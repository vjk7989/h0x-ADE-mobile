import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show StringCodec;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/widgets/intro.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import 'support/golden.dart';

/// The first screen under the intro, with a button that counts its taps.
class _App extends StatelessWidget {
  const _App({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(onPressed: onTap ?? () {}, child: const Text('Machines')),
    ),
  );
}

Widget _gate({bool reduce = false, VoidCallback? onTap}) => Builder(
  builder: (context) {
    final w = IntroGate(child: _App(onTap: onTap));
    return reduce
        ? MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: w,
          )
        : w;
  },
);

/// Pumps a fresh gate (the once-per-process flag reset), no animation frame.
Future<void> _pumpFresh(
  WidgetTester t, {
  Brightness b = Brightness.dark,
  Frame frame = Frame.phone,
  bool reduce = false,
  double textScale = 1,
  VoidCallback? onTap,
  Future<void> Function()? firstFrame,
}) async {
  HxIntro.resetForTest();
  if (firstFrame != null) HxIntro.firstFrame = firstFrame;
  await pumpGolden(
    t,
    _gate(reduce: reduce, onTap: onTap),
    brightness: b,
    frame: frame,
    textScale: textScale,
    settle: false,
    insets: false,
    frames: 0,
  );
}

/// The overlay's own opacity (the outermost Opacity of the intro).
double _overlay(WidgetTester t) => t
    .widget<Opacity>(
      find.descendant(of: find.byType(HxIntro), matching: find.byType(Opacity)).first,
    )
    .opacity;

/// The wordmark's opacity.
double _word(WidgetTester t) => t
    .widget<Opacity>(
      find.ancestor(of: find.text('HyperOx'), matching: find.byType(Opacity)).first,
    )
    .opacity;

/// The engine tells the app its lifecycle on this channel.
Future<void> _life(WidgetTester t, AppLifecycleState s) =>
    t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(s.toString()),
      (_) {},
    );

/// A strip golden that is skipped until app-goldens has made it.
Future<void> _expectStrip(ui.Image img, String name) async {
  if (!autoUpdateGoldenFiles && !File('test/goldens/$name.png').existsSync()) {
    debugPrint('golden $name.png not generated yet: run app-goldens');
    return;
  }
  await expectLater(img, matchesGoldenFile('goldens/$name.png'));
}

void main() {
  setUp(HxIntro.resetForTest);
  tearDown(HxIntro.resetForTest);

  group('t = 0', () {
    testWidgets('the first frame is the static mark: overlay opaque, no wordmark', (t) async {
      await _pumpFresh(t);
      expect(_overlay(t), 1.0);
      expect(_word(t), 0.0);
      await t.pumpAndSettle();
    });

    testWidgets('the first frame is the same on a tablet (no fly-out yet)', (t) async {
      await _pumpFresh(t, frame: Frame.tablet);
      expect(_overlay(t), 1.0);
      expect(_word(t), 0.0);
      await t.pumpAndSettle();
    });

    testWidgets('reduced motion: the full mark, opaque, at t = 0', (t) async {
      await _pumpFresh(t, reduce: true);
      expect(_overlay(t), 1.0);
      expect(_word(t), 0.0, reason: 'no wordmark rise with reduced motion');
      await t.pumpAndSettle();
    });

    testWidgets('nothing moves until the first frame is visible', (t) async {
      final visible = Completer<void>();
      await _pumpFresh(t, firstFrame: () => visible.future);
      await t.pump(const Duration(milliseconds: 600));
      expect(_overlay(t), 1.0, reason: 'held at t = 0 while the splash is still up');
      expect(_word(t), 0.0);
      visible.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      await t.pump(const Duration(milliseconds: 500));
      expect(_word(t), greaterThan(0), reason: 'now it runs');
      await t.pumpAndSettle();
      expect(find.byType(HxIntro), findsNothing);
    });
  });

  group('skip', () {
    testWidgets('a tap before the first visible frame is not undone by it', (t) async {
      final visible = Completer<void>();
      await _pumpFresh(t, firstFrame: () => visible.future);
      await t.tapAt(const Offset(180, 400));
      await t.pump(const Duration(milliseconds: 1));
      visible.complete();
      await t.pump();
      await t.pump(const Duration(milliseconds: 1));
      // The skip must hold: the intro may not restart from 0 when the first
      // frame arrives after the tap.
      expect(_word(t), 1.0, reason: 'skipped to the hand-off, not restarted');
      await t.pumpAndSettle();
    });

    testWidgets('a tap at t = 0 jumps to the hand-off', (t) async {
      await _pumpFresh(t);
      await t.tapAt(const Offset(10, 10));
      await t.pump(const Duration(milliseconds: 1));
      expect(_word(t), 1.0);
      // 560 -> 900 is 340 ms: done by then, not later.
      await t.pump(const Duration(milliseconds: 345));
      await t.pump();
      expect(find.byType(HxIntro), findsNothing);
    });

    testWidgets('a second tap does not go back to 560 ms', (t) async {
      await _pumpFresh(t);
      await t.pump(const Duration(milliseconds: 100));
      await t.tapAt(const Offset(180, 400));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      final before = _overlay(t);
      expect(before, lessThan(1.0), reason: 'fading out at 760 ms');
      await t.tapAt(const Offset(180, 400));
      await t.pump(const Duration(milliseconds: 1));
      expect(_overlay(t), lessThanOrEqualTo(before), reason: 'never backwards');
      await t.pumpAndSettle();
    });

    testWidgets('a tap during the hand-off neither rewinds nor extends it', (t) async {
      await _pumpFresh(t);
      await t.pump(const Duration(milliseconds: 700));
      final before = _overlay(t);
      await t.tapAt(const Offset(180, 400));
      await t.pump(const Duration(milliseconds: 1));
      expect(_overlay(t), lessThanOrEqualTo(before));
      // Still ends at 900 ms.
      await t.pump(const Duration(milliseconds: 205));
      await t.pump();
      expect(find.byType(HxIntro), findsNothing);
    });

    testWidgets('reduced motion: a tap does not extend the 150 ms fade', (t) async {
      await _pumpFresh(t, reduce: true);
      await t.pump(const Duration(milliseconds: 100));
      await t.tapAt(const Offset(180, 400));
      await t.pump(const Duration(milliseconds: 55));
      await t.pump();
      expect(find.byType(HxIntro), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('reduced motion: 149 ms still covers, 151 ms is gone', (t) async {
      await _pumpFresh(t, reduce: true);
      await t.pump(const Duration(milliseconds: 149));
      expect(find.byType(HxIntro), findsOneWidget);
      await t.pump(const Duration(milliseconds: 2));
      await t.pump();
      expect(find.byType(HxIntro), findsNothing);
      expect(t.binding.transientCallbackCount, 0, reason: 'no ticker left');
    });
  });

  group('when it plays', () {
    testWidgets('not again on a resume', (t) async {
      await _pumpFresh(t);
      await t.pumpAndSettle();
      expect(find.byType(HxIntro), findsNothing);
      await _life(t, AppLifecycleState.inactive);
      await _life(t, AppLifecycleState.paused);
      await t.pump();
      await _life(t, AppLifecycleState.inactive);
      await _life(t, AppLifecycleState.resumed);
      await t.pump();
      expect(find.byType(HxIntro), findsNothing);
      expect(HxIntro.shouldShow, isFalse);
    });

    testWidgets('not on a resume while it is still playing either (one controller)', (t) async {
      await _pumpFresh(t);
      await t.pump(const Duration(milliseconds: 100));
      await _life(t, AppLifecycleState.inactive);
      await _life(t, AppLifecycleState.resumed);
      await t.pump();
      expect(find.byType(HxIntro), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.byType(HxIntro), findsNothing);
    });

    testWidgets('any route but "/" is a deep link', (t) async {
      addTearDown(t.platformDispatcher.clearDefaultRouteNameTestValue);
      for (final route in ['/inbox', '/agent/devbox/t1', '/m/x', '//', '']) {
        t.platformDispatcher.defaultRouteNameTestValue = route;
        expect(HxIntro.shouldShow, isFalse, reason: 'route "$route"');
      }
      t.platformDispatcher.defaultRouteNameTestValue = '/';
      expect(HxIntro.shouldShow, isTrue);
    });
  });

  group('the first screen', () {
    testWidgets('is never blocked: it builds under the intro and gets taps after', (t) async {
      var taps = 0;
      await _pumpFresh(t, onTap: () => taps++);
      expect(find.text('Machines'), findsOneWidget);
      // During the intro a tap is the skip; it does not reach the app.
      await t.tap(find.text('Machines'), warnIfMissed: false);
      await t.pump();
      expect(taps, 0);
      await t.pumpAndSettle();
      expect(find.byType(HxIntro), findsNothing);
      await t.tap(find.text('Machines'));
      await t.pump();
      expect(taps, 1);
    });

    testWidgets('TalkBack hears the first screen, never the intro', (t) async {
      final h = t.ensureSemantics();
      await _pumpFresh(t);
      for (final ms in [0, 300, 200]) {
        await t.pump(Duration(milliseconds: ms));
        expect(find.bySemanticsLabel('Machines'), findsOneWidget, reason: 'at $ms ms');
        expect(find.bySemanticsLabel('HyperOx'), findsNothing, reason: 'at $ms ms');
      }
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Machines'), findsOneWidget);
      h.dispose();
    });

    testWidgets('the overlay goes away and leaves no ticker, light and dark', (t) async {
      for (final b in Brightness.values) {
        await t.pumpWidget(const SizedBox());
        await _pumpFresh(t, b: b);
        expect(find.byType(HxIntro), findsOneWidget, reason: '$b');
        await t.pump(const Duration(milliseconds: 905));
        await t.pump();
        expect(find.byType(HxIntro), findsNothing, reason: '$b');
        expect(t.binding.transientCallbackCount, 0, reason: '$b');
      }
    });
  });

  testWidgets('golden: the intro strip at 200 % text, light phone', (t) async {
    await _pumpFresh(t, b: Brightness.light, textScale: 2);
    await _expectStrip(
      await strip(t, times: const [0, 150, 300, 450, 600, 900]),
      'intro_strip_text200_light',
    );
    await t.pumpAndSettle();
  });
}
