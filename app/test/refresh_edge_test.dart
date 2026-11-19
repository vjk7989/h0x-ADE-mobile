import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/widgets/hx_refresh.dart';
import 'package:material_ui/material_ui.dart';

import 'support/golden.dart';

/// The list's context outside its viewport: notifications sent from here
/// reach HxRefresh at depth 0, like the list's own.
late BuildContext _list;

Widget _page(Future<void> Function() onRefresh) => Scaffold(
  appBar: AppBar(title: const Text('Inbox')),
  body: HxRefresh(
    onRefresh: onRefresh,
    child: Builder(
      builder: (context) {
        _list = context;
        return ListView(
          children: [for (var i = 0; i < 12; i++) ListTile(title: Text('Agent $i'))],
        );
      },
    ),
  ),
);

/// The list reports it is pulled [dp] down; [finger] when a finger drags it,
/// not when it springs back.
Future<void> _pullTo(
  WidgetTester t,
  double dp, {
  bool finger = true,
  AxisDirection axis = AxisDirection.down,
}) async {
  ScrollUpdateNotification(
    metrics: FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 400,
      pixels: -dp,
      viewportDimension: 600,
      axisDirection: axis,
      devicePixelRatio: 1,
    ),
    context: _list,
    scrollDelta: -1,
    dragDetails: finger ? DragUpdateDetails(globalPosition: const Offset(180, 300)) : null,
  ).dispatch(_list);
  await t.pump();
}

/// A finger that is down on the list for the whole pull, lifted by [_lift].
Future<TestGesture> _down(WidgetTester t) => t.startGesture(const Offset(180, 400));

Future<void> _lift(WidgetTester t, TestGesture g) async {
  await g.up();
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

List<String> _mockHaptics(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
    if (c.method == 'HapticFeedback.vibrate') calls.add('${c.arguments}');
    return null;
  });
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

Finder get _spinner => find.byType(CircularProgressIndicator);

void main() {
  group('threshold (80 dp)', () {
    for (final (dp, fires) in [(79.0, false), (80.0, true), (81.0, true)]) {
      testWidgets('a release at $dp dp ${fires ? 'refreshes' : 'does not refresh'}', (t) async {
        final haptics = _mockHaptics(t);
        var calls = 0;
        await pumpGolden(t, _page(() async => calls++));
        final g = await _down(t);
        await _pullTo(t, dp);
        expect(haptics, fires ? ['HapticFeedbackType.lightImpact'] : isEmpty);
        await _lift(t, g);
        expect(calls, fires ? 1 : 0);
        await t.pumpAndSettle();
      });
    }

    testWidgets('past the threshold, then back below it by finger: no refresh', (t) async {
      final haptics = _mockHaptics(t);
      var calls = 0;
      await pumpGolden(t, _page(() async => calls++));
      final g = await _down(t);
      await _pullTo(t, 95);
      await _pullTo(t, 79);
      await _lift(t, g);
      expect(calls, 0);
      expect(haptics, hasLength(1), reason: 'one tap when it armed');
    });

    testWidgets('past the threshold, then the spring back: still refreshes', (t) async {
      var calls = 0;
      await pumpGolden(t, _page(() async => calls++));
      final g = await _down(t);
      await _pullTo(t, 95);
      await _pullTo(t, 30, finger: false);
      await _lift(t, g);
      expect(calls, 1);
    });

    testWidgets('crossing the threshold twice by finger taps twice, refreshes once', (t) async {
      final haptics = _mockHaptics(t);
      var calls = 0;
      await pumpGolden(t, _page(() async => calls++));
      final g = await _down(t);
      await _pullTo(t, 85);
      await _pullTo(t, 60);
      await _pullTo(t, 85);
      await _lift(t, g);
      expect(haptics, ['HapticFeedbackType.lightImpact', 'HapticFeedbackType.lightImpact']);
      expect(calls, 1);
    });

    testWidgets('a cancelled pointer past the threshold counts as a release', (t) async {
      var calls = 0;
      await pumpGolden(t, _page(() async => calls++));
      final g = await _down(t);
      await _pullTo(t, 90);
      await g.cancel();
      await t.pump();
      expect(calls, 1);
      await t.pumpAndSettle();
    });

    testWidgets('a very long pull is fine (clamped), and refreshes once', (t) async {
      var calls = 0;
      await pumpGolden(t, _page(() async => calls++));
      final g = await _down(t);
      await _pullTo(t, 5000);
      expect(t.takeException(), isNull);
      await _lift(t, g);
      expect(calls, 1);
    });
  });

  group('while refreshing', () {
    testWidgets('a second pull does not start a second refresh', (t) async {
      var calls = 0;
      final done = Completer<void>();
      await pumpGolden(t, _page(() {
        calls++;
        return done.future;
      }));
      var g = await _down(t);
      await _pullTo(t, 90);
      await _lift(t, g);
      expect(calls, 1);
      g = await _down(t);
      await _pullTo(t, 120);
      await _lift(t, g);
      expect(calls, 1, reason: 'one refresh at a time');
      expect(_spinner, findsOneWidget, reason: 'one spinner');
      done.complete();
      await t.pumpAndSettle();
      expect(_spinner, findsNothing);
    });

    testWidgets('a pull after it finished refreshes again', (t) async {
      var calls = 0;
      await pumpGolden(t, _page(() async => calls++));
      for (var i = 1; i <= 2; i++) {
        final g = await _down(t);
        await _pullTo(t, 90);
        await _lift(t, g);
        await t.pumpAndSettle();
        expect(calls, i);
      }
    });

    testWidgets('an error from the refresh ends the spinner and is not thrown', (t) async {
      await pumpGolden(t, _page(() async => throw StateError('offline')));
      final g = await _down(t);
      await _pullTo(t, 90);
      await _lift(t, g);
      await t.pumpAndSettle();
      expect(_spinner, findsNothing, reason: 'back to rest');
      expect(t.takeException(), isNull);
    });

    testWidgets('the page closing mid-refresh, then the refresh ending: no error', (t) async {
      final done = Completer<void>();
      await pumpGolden(t, _page(() => done.future));
      final g = await _down(t);
      await _pullTo(t, 90);
      await _lift(t, g);
      await t.pumpWidget(const SizedBox());
      done.complete();
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });

  group('what it listens to', () {
    testWidgets('a sideways scroll never arms it', (t) async {
      var calls = 0;
      await pumpGolden(t, _page(() async => calls++));
      final g = await _down(t);
      await _pullTo(t, 120, axis: AxisDirection.right);
      await _lift(t, g);
      expect(calls, 0);
    });

    testWidgets('no pull: nothing above the list', (t) async {
      await pumpGolden(t, _page(() async {}));
      await _pullTo(t, 0);
      expect(_spinner, findsNothing);
      expect(
        find.descendant(
          of: find.byType(HxRefresh),
          matching: find.byWidgetPredicate((w) => w is Positioned && w.height == 40),
        ),
        findsNothing,
      );
    });
  });

  group('reduced motion', () {
    testWidgets('the spinner tracks the pull and is full at the threshold', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpGolden(t, _page(() async {}));
      final g = await _down(t);
      double? value() => t.widget<CircularProgressIndicator>(_spinner).value;
      await _pullTo(t, 40);
      expect(value(), closeTo(0.5, 1e-9));
      await _pullTo(t, 80);
      expect(value(), 1.0);
      await _pullTo(t, 200);
      expect(value(), 1.0, reason: 'clamped');
      await _lift(t, g);
      await t.pumpAndSettle();
    });
  });
}
