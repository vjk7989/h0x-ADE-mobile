import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/screens/agent_screen.dart';
import 'package:material_ui/material_ui.dart' hide Key;
import 'package:xterm/xterm.dart' show TerminalView;

import 'support/fake_connection.dart';
import 'support/golden.dart';

class _Flaky extends FakeConnection {
  final drop = StreamController<ConnState>.broadcast(sync: true);

  @override
  Stream<ConnState> get state => drop.stream;
}

Future<void> _open(
  WidgetTester t,
  FakeConnection fake, {
  Brightness b = Brightness.light,
  String id = 't2',
}) => pumpGolden(
  t,
  AgentScreen(machineId: 'fake', terminal: id, connection: fake),
  brightness: b,
  settle: false,
  frames: 1,
);

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Future<void> _expectImage(WidgetTester t, ui.Image img, String name) =>
    expectLater(img, matchesGoldenFile('goldens/$name.png'));

Finder get _bar => find.byType(LinearProgressIndicator);

void main() {
  testWidgets('golden: the replay bar fills, then fades out, light', (t) async {
    final fake = FakeConnection();
    await _open(t, fake);
    await t.pump(const Duration(milliseconds: 50));
    final chunk = utf8.encode('x' * 80 * 600);
    final shot = await strip(
      t,
      times: const [0, 100, 100, 100, 700, 900],
      scale: 0.4,
      before: (i) async {
        if (i >= 1 && i <= 3) {
          fake.emitView('t2', chunk);
          await t.pump(const Duration(milliseconds: 50));
        }
      },
    );
    await _expectImage(t, shot, 'agent_replay_strip_light');
    await _close(t);
  });

  testWidgets('the replay bar is thin, determinate and gone when replayed', (t) async {
    final fake = FakeConnection();
    await _open(t, fake);
    await t.pump(const Duration(milliseconds: 50));
    expect(_bar, findsOneWidget);
    expect(t.getSize(find.ancestor(of: _bar, matching: find.byType(SizedBox)).first).height, 2);
    expect(t.widget<LinearProgressIndicator>(_bar).value, isNotNull);
    fake.emitView('t2', utf8.encode('x' * 40000));
    await t.pump(const Duration(milliseconds: 50));
    final mid = t.widget<LinearProgressIndicator>(_bar).value!;
    expect(mid, greaterThan(0));
    expect(mid, lessThanOrEqualTo(0.95));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 300));
    expect(
      t.widget<AnimatedOpacity>(find.ancestor(of: _bar, matching: find.byType(AnimatedOpacity)).first).opacity,
      0,
      reason: 'replayed: faded out',
    );
    await _close(t);
  });

  testWidgets('golden: the reconnect ring runs down, dark', (t) async {
    final fake = _Flaky();
    await _open(t, fake, b: Brightness.dark);
    fake.drop.add(const Ready());
    await t.pump(const Duration(milliseconds: 1700));
    fake.emitView('t2', utf8.encode('output\r\n'));
    await t.pump(const Duration(milliseconds: 100));
    fake.drop.add(const Failed('connection lost', retryIn: Duration(seconds: 4)));
    await t.pump();
    await _expectImage(
      t,
      await strip(t, times: const [0, 1000, 2000, 3000, 3800], scale: 0.4),
      'agent_reconnect_strip_dark',
    );
    await _close(t);
  });

  testWidgets('the ring is full with reduced motion and the countdown is announced', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final fake = _Flaky();
    await _open(t, fake);
    fake.drop.add(const Ready());
    await t.pump(const Duration(milliseconds: 1700));
    fake.emitView('t2', utf8.encode('output\r\n'));
    await t.pump(const Duration(milliseconds: 100));
    fake.drop.add(const Failed('connection lost', retryIn: Duration(seconds: 4)));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(find.bySemanticsLabel('Retrying in 4 seconds'), findsNothing, reason: 'semantics are off');
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await _close(t);
  });

  testWidgets('100 output writes make no animation tick', (t) async {
    final fake = FakeConnection();
    await _open(t, fake);
    await t.pump(const Duration(milliseconds: 1700));
    await t.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 100; i++) {
      fake.emitView('t2', utf8.encode('line $i\r\n'));
    }
    // One frame writes them all; after it nothing is left running.
    await t.pump(const Duration(milliseconds: 16));
    await t.pump(const Duration(milliseconds: 16));
    expect(find.byType(TerminalView), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.binding.transientCallbackCount, 0, reason: 'no ticker for the output');
    await _close(t);
  });

  group('haptics', () {
    late List<String> calls;

    setUp(() => calls = []);

    void mock(WidgetTester t) {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'HapticFeedback.vibrate') calls.add('${c.arguments}');
        return null;
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
    }

    testWidgets('Approve is a medium impact', (t) async {
      mock(t);
      final fake = FakeConnection();
      await _open(t, fake);
      fake.emitView('t2', utf8.encode('Allow?\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Approve').first);
      await t.pump();
      expect(calls, contains('HapticFeedbackType.mediumImpact'));
      await _close(t);
    });

    testWidgets('Deny is a light impact', (t) async {
      mock(t);
      final fake = FakeConnection();
      await _open(t, fake);
      fake.emitView('t2', utf8.encode('Allow?\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Deny').first);
      await t.pump();
      expect(calls, contains('HapticFeedbackType.lightImpact'));
      await _close(t);
    });

    testWidgets('confirming Interrupt is a heavy impact; Cancel is none', (t) async {
      mock(t);
      final fake = FakeConnection();
      await _open(t, fake, id: 't1');
      fake.emitView('t1', utf8.encode('working
'));
      await t.pump(const Duration(milliseconds: 1700));
      await t.tap(find.byTooltip('Interrupt claude'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Cancel'));
      await t.pump(const Duration(milliseconds: 400));
      expect(calls, isNot(contains('HapticFeedbackType.heavyImpact')));
      await t.tap(find.byTooltip('Interrupt claude'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.widgetWithText(TextButton, 'Interrupt'));
      await t.pump(const Duration(milliseconds: 400));
      expect(calls, contains('HapticFeedbackType.heavyImpact'));
      await _close(t);
    });
  });
}
