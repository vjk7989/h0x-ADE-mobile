import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/widgets/hx_refresh.dart';
import 'package:material_ui/material_ui.dart';

import 'support/golden.dart';

Widget _list(Future<void> Function() onRefresh) => Scaffold(
  appBar: AppBar(title: const Text('Inbox')),
  body: HxRefresh(
    onRefresh: onRefresh,
    child: ListView(
      children: [
        for (var i = 0; i < 12; i++) ListTile(title: Text('Agent $i')),
      ],
    ),
  ),
);

double _pull(WidgetTester t) =>
    -t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

/// Drags the finger down until the list is pulled [dp] dp (the spring makes
/// the finger travel further than the list).
Future<void> _pullTo(WidgetTester t, TestGesture g, double dp) async {
  var guard = 0;
  while (_pull(t) < dp && guard++ < 200) {
    await g.moveBy(const Offset(0, 4));
    await t.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('golden: pulling lights the dots, then the spinner, light', (t) async {
    final done = Completer<void>();
    await pumpGolden(t, _list(() => done.future));
    final g = await t.startGesture(const Offset(180, 300));
    const pulls = [20.0, 40.0, 60.0, 80.0];
    final shot = await strip(
      t,
      times: const [0, 0, 0, 0, 0],
      scale: 0.5,
      before: (i) async {
        if (i < pulls.length) {
          await _pullTo(t, g, pulls[i]);
        } else {
          await g.up();
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));
        }
      },
    );
    await expectLater(shot, matchesGoldenFile('goldens/refresh_strip_light.png'));
    done.complete();
    await t.pumpAndSettle();
  });

  group('behaviour', () {
    testWidgets('a release past the threshold refreshes, then snaps back', (t) async {
      var calls = 0;
      final done = Completer<void>();
      await pumpGolden(
        t,
        _list(() {
          calls++;
          return done.future;
        }),
      );
      final g = await t.startGesture(const Offset(180, 300));
      await _pullTo(t, g, kRefreshThreshold + 5);
      await g.up();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'the spinner');
      done.complete();
      await t.pump();
      await t.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a short pull does not refresh', (t) async {
      var calls = 0;
      await pumpGolden(
        t,
        _list(() async {
          calls++;
        }),
      );
      final g = await t.startGesture(const Offset(180, 300));
      await _pullTo(t, g, 30);
      await g.up();
      await t.pumpAndSettle();
      expect(calls, 0);
    });

    testWidgets('a light tap at the threshold', (t) async {
      final haptics = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'HapticFeedback.vibrate') haptics.add('${c.arguments}');
        return null;
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final done = Completer<void>()..complete();
      await pumpGolden(t, _list(() => done.future));
      final g = await t.startGesture(const Offset(180, 300));
      await _pullTo(t, g, 40);
      expect(haptics, isEmpty);
      await _pullTo(t, g, kRefreshThreshold + 2);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('with reduced motion there is a spinner and no mark', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final done = Completer<void>()..complete();
      await pumpGolden(t, _list(() => done.future));
      final g = await t.startGesture(const Offset(180, 300));
      await _pullTo(t, g, 30);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await g.up();
      await t.pumpAndSettle();
    });
  });
}
