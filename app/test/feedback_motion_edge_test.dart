import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/theme/themes.dart';
import 'package:hyperox/widgets/hx.dart';
import 'package:hyperox/widgets/theme_crossfade.dart';
import 'package:material_ui/material_ui.dart';

import 'support/golden.dart';

void _reduce(WidgetTester t) {
  t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<void> _expectStrip(ui.Image img, String name) async {
  if (!autoUpdateGoldenFiles && !File('test/goldens/$name.png').existsSync()) {
    debugPrint('golden $name.png not generated yet: run app-goldens');
    return;
  }
  await expectLater(img, matchesGoldenFile('goldens/$name.png'));
}

Widget _themed(String id) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: themeData(themeById(id)),
  themeAnimationDuration: Duration.zero,
  builder: (context, child) =>
      ThemeCrossFade(maxCapture: const Duration(seconds: 5), child: child!),
  home: Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: const Center(child: Text('Theme')),
  ),
);

Widget _bannerPage({required bool show}) => Scaffold(
  body: SafeArea(
    child: Column(
      children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Machines')),
        HxBannerSlot(
          child: show
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: HxBanner(
                    title: 'devbox is offline',
                    message: 'Check that it is on and on your network.',
                    kind: HxBannerKind.offline,
                  ),
                )
              : null,
        ),
        const Padding(padding: EdgeInsets.all(16), child: Text('devbox')),
      ],
    ),
  ),
);

/// Pumps the banner page; the returned function shows or hides the banner.
Future<void Function(bool)> _pumpBanner(WidgetTester t, {bool show = false, double textScale = 1}) async {
  late StateSetter set;
  var shown = show;
  await pumpGolden(
    t,
    StatefulBuilder(
      builder: (context, setState) {
        set = setState;
        return _bannerPage(show: shown);
      },
    ),
    textScale: textScale,
  );
  return (bool v) => set(() => shown = v);
}

void main() {
  group('theme cross-fade', () {
    testWidgets('a quick switch back restarts the fade with one fresh picture', (t) async {
      await t.pumpWidget(_themed('paper'));
      await t.pumpWidget(_themed('darkmatter'));
      expect(find.byType(RawImage), findsOneWidget);
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpWidget(_themed('paper'));
      expect(find.byType(RawImage), findsOneWidget, reason: 'one overlay, not two');
      final img = t.widget<RawImage>(find.byType(RawImage)).image!;
      expect(img.debugDisposed, isFalse, reason: 'the shown picture is alive');
      // 200 ms after the second switch the first fade would be over: the
      // second one is still running (spec change: S1.4 400 ms reveal).
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byType(RawImage), findsOneWidget);
      await t.pump(const Duration(milliseconds: 260));
      await t.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('five switches in five frames: still one overlay, nothing left after', (t) async {
      final ids = ['paper', 'darkmatter', 'paper', 'darkmatter', 'paper', 'darkmatter'];
      for (final id in ids) {
        await t.pumpWidget(_themed(id));
        expect(find.byType(RawImage).evaluate().length, lessThanOrEqualTo(1));
      }
      await t.pump(const Duration(milliseconds: 450));
      await t.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('the same theme again is not a switch', (t) async {
      await t.pumpWidget(_themed('paper'));
      await t.pumpWidget(_themed('paper'));
      expect(find.byType(RawImage), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('the overlay never takes a tap', (t) async {
      var taps = 0;
      Widget app(String id) => MaterialApp(
        theme: themeData(themeById(id)),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) =>
            ThemeCrossFade(maxCapture: const Duration(seconds: 5), child: child!),
        home: Scaffold(
          body: Center(child: TextButton(onPressed: () => taps++, child: const Text('Tap'))),
        ),
      );
      await t.pumpWidget(app('paper'));
      await t.pumpWidget(app('darkmatter'));
      expect(find.byType(RawImage), findsOneWidget);
      await t.tap(find.text('Tap'));
      await t.pump();
      expect(taps, 1);
      await t.pump(const Duration(milliseconds: 300));
    });

    testWidgets('closing the app mid-fade leaves no ticker and no error', (t) async {
      await t.pumpWidget(_themed('paper'));
      await t.pumpWidget(_themed('darkmatter'));
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('reduced motion: no picture on any number of switches', (t) async {
      _reduce(t);
      for (final id in ['paper', 'darkmatter', 'paper']) {
        await t.pumpWidget(_themed(id));
        expect(find.byType(RawImage), findsNothing);
      }
    });
  });

  group('snackbar', () {
    Future<BuildContext> page(WidgetTester t) async {
      late BuildContext ctx;
      await pumpGolden(
        t,
        Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      return ctx;
    }

    testWidgets('two in a row queue: the second waits for the first to leave', (t) async {
      final ctx = await page(t);
      showHxSnack(ctx, const SnackBar(content: Text('First')));
      showHxSnack(ctx, const SnackBar(content: Text('Second')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsNothing);
      ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
      await t.pump();
      await t.pump(const Duration(milliseconds: 170));
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsOneWidget);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('comes in over 200 ms: still moving at 150, still at 210', (t) async {
      final ctx = await page(t);
      showHxSnack(ctx, const SnackBar(content: Text('Saved')));
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 150));
      expect(t.binding.transientCallbackCount, greaterThan(0));
      await t.pump(const Duration(milliseconds: 60));
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('reduced motion: in within 100 ms', (t) async {
      _reduce(t);
      final ctx = await page(t);
      showHxSnack(ctx, const SnackBar(content: Text('Saved')));
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 101));
      expect(find.text('Saved'), findsOneWidget);
      expect(t.binding.transientCallbackCount, 0);
      await t.pumpAndSettle(const Duration(seconds: 5));
    });
  });

  group('banner', () {
    testWidgets('it keeps its label while it grows in', (t) async {
      final h = t.ensureSemantics();
      final show = await _pumpBanner(t);
      show(true);
      await t.pump();
      for (final ms in [50, 50, 100]) {
        await t.pump(Duration(milliseconds: ms));
        expect(
          find.bySemanticsLabel('devbox is offline. Check that it is on and on your network.'),
          findsOneWidget,
          reason: 'during the grow-in',
        );
      }
      h.dispose();
    });

    testWidgets('reduced motion: no slide and no grow, only the fade', (t) async {
      _reduce(t);
      final show = await _pumpBanner(t);
      show(true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 30));
      final slide = t.widget<Transform>(
        find.ancestor(of: find.text('devbox is offline'), matching: find.byType(Transform)).first,
      );
      expect(slide.transform.getTranslation().y, 0.0, reason: 'no 8 dp slide when reduced');
      final grow = t.widget<Align>(
        find.ancestor(of: find.text('devbox is offline'), matching: find.byType(Align)).first,
      );
      expect(grow.heightFactor, 1.0, reason: 'no size animation when reduced');
      await t.pumpAndSettle();
    });

    testWidgets('it leaves with a fade and collapse (160 ms), not a cut', (t) async {
      final show = await _pumpBanner(t, show: true);
      show(false);
      await t.pump();
      expect(find.text('devbox is offline'), findsOneWidget, reason: 'still fading out');
      await t.pump(const Duration(milliseconds: 170));
      await t.pump();
      expect(find.text('devbox is offline'), findsNothing);
    });

    testWidgets('golden: the banner grows in at 200 % text, light', (t) async {
      final show = await _pumpBanner(t, textScale: 2);
      show(true);
      await t.pump();
      await _expectStrip(
        await strip(t, times: const [0, 50, 100, 150, 200], scale: 0.5),
        'banner_strip_text200_light',
      );
      await t.pumpAndSettle();
    });
  });
}
