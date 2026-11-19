import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/theme/themes.dart';
import 'package:hyperox/widgets/hx.dart';
import 'package:hyperox/widgets/theme_crossfade.dart';
import 'package:material_ui/material_ui.dart';

import 'support/golden.dart';

Future<void> _expectImage(WidgetTester t, ui.Image img, String name) =>
    expectLater(img, matchesGoldenFile('goldens/$name.png'));

/// A banner under a title, shown by a button.
Widget _bannerPage({required bool show}) => Scaffold(
  body: SafeArea(
    child: Column(
      children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Machines')),
        if (show)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: HxBanner(
              title: 'devbox is offline',
              message: 'Check that it is on and on your network.',
              kind: HxBannerKind.offline,
            ),
          ),
        const Padding(padding: EdgeInsets.all(16), child: Text('devbox')),
      ],
    ),
  ),
);

Widget _themed(String id, {Duration maxCapture = const Duration(seconds: 5)}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: themeData(themeById(id)),
  themeAnimationDuration: Duration.zero,
  builder: (context, child) => ThemeCrossFade(maxCapture: maxCapture, child: child!),
  home: Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: const Center(child: Text('Theme')),
  ),
);

void main() {
  testWidgets('golden: a banner grows in with a short slide, light', (t) async {
    late StateSetter set;
    var show = false;
    await pumpGolden(
      t,
      StatefulBuilder(
        builder: (context, setState) {
          set = setState;
          return _bannerPage(show: show);
        },
      ),
    );
    set(() => show = true);
    await t.pump();
    await _expectImage(
      t,
      await strip(t, times: const [0, 50, 100, 150, 200], scale: 0.5),
      'banner_strip_light',
    );
    await t.pumpAndSettle();
  });

  testWidgets('a banner with reduced motion is there at once', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpGolden(t, _bannerPage(show: true), settle: false, frames: 1);
    expect(t.binding.transientCallbackCount, 0);
    expect(find.text('devbox is offline'), findsOneWidget);
  });

  testWidgets('golden: a snackbar comes in and goes out, dark', (t) async {
    await pumpGolden(
      t,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showHxSnack(context, const SnackBar(content: Text('Saved'))),
              child: const Text('Save'),
            ),
          ),
        ),
      ),
      brightness: Brightness.dark,
    );
    await t.tap(find.text('Save'));
    await t.pump();
    await _expectImage(
      t,
      await strip(t, times: const [0, 60, 120, 200], scale: 0.4),
      'snackbar_strip_dark',
    );
    await t.pumpAndSettle(const Duration(seconds: 5));
  });

  group('theme switch', () {
    testWidgets('golden: paper to darkmatter, a circle reveal over 400 ms', (t) async {
      t.view.physicalSize = Frame.phone.size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(_themed('paper'));
      await t.pumpWidget(_themed('darkmatter'));
      await _expectImage(
        t,
        await strip(t, times: const [0, 100, 200, 300, 400], scale: 0.4),
        'theme_switch_strip_light',
      );
      await t.pumpAndSettle();
    });

    testWidgets('the old frame is gone after 400 ms and no ticker is left', (t) async {
      await t.pumpWidget(_themed('paper'));
      await t.pumpWidget(_themed('darkmatter'));
      expect(find.byType(RawImage), findsOneWidget);
      await t.pump(const Duration(milliseconds: 450));
      await t.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('reduced motion switches at once', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await t.pumpWidget(_themed('paper'));
      await t.pumpWidget(_themed('darkmatter'));
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('a capture that takes too long is skipped', (t) async {
      await t.pumpWidget(_themed('paper', maxCapture: Duration.zero));
      await t.pumpWidget(_themed('darkmatter', maxCapture: Duration.zero));
      expect(find.byType(RawImage), findsNothing);
    });
  });
}
