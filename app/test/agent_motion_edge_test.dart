import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/screens/agent_screen.dart';
import 'package:material_ui/material_ui.dart' hide Key;

import 'support/fake_connection.dart';
import 'support/golden.dart';

class _Flaky extends FakeConnection {
  final drop = StreamController<ConnState>.broadcast(sync: true);

  @override
  Stream<ConnState> get state => drop.stream;
}

Future<void> _open(WidgetTester t, FakeConnection fake, {String id = 't2'}) => pumpGolden(
  t,
  AgentScreen(machineId: 'fake', terminal: id, connection: fake),
  settle: false,
  frames: 1,
);

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

void _reduce(WidgetTester t) {
  t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Finder get _bar => find.byType(LinearProgressIndicator);

double? _barValue(WidgetTester t) => t.widget<LinearProgressIndicator>(_bar).value;

AnimatedOpacity _barFade(WidgetTester t) =>
    t.widget<AnimatedOpacity>(find.ancestor(of: _bar, matching: find.byType(AnimatedOpacity)).first);

/// Opens [fake] on t2, has it print a line, and waits until it is ready and
/// the replay is over, so a drop shows the reconnect banner.
Future<void> _ready(WidgetTester t, FakeConnection fake) async {
  await _open(t, fake);
  fake.emitView('t2', utf8.encode('output\r\n'));
  await t.pump(const Duration(milliseconds: 1700));
  await t.pump(const Duration(milliseconds: 300));
}

/// The ring, found by the label it gives itself (a widget lookup, so it works
/// whatever the banner does with its children's semantics).
Finder _ring([String? label]) => find.byWidgetPredicate(
  (w) =>
      w is Semantics &&
      (w.properties.label ?? '').startsWith('Retrying in') &&
      (label == null || w.properties.label == label),
);

void main() {
  group('replay bar', () {
    testWidgets('zero bytes: the bar ends with the settle wait and fades out', (t) async {
      final fake = FakeConnection();
      await _open(t, fake);
      expect(_barValue(t), 0.0);
      expect(_barFade(t).opacity, 1.0);
      await t.pump(const Duration(milliseconds: 1300));
      expect(_barFade(t).opacity, 1.0, reason: 'before the 1500 ms settle');
      await t.pump(const Duration(milliseconds: 300));
      expect(_barFade(t).opacity, 0.0, reason: 'a quiet terminal: replay over');
      expect(_barValue(t), 1.0);
      await t.pump(const Duration(milliseconds: 300));
      await _close(t);
    });

    testWidgets('huge history: the bar stops at 95 % until the bytes go quiet', (t) async {
      final fake = FakeConnection();
      await _open(t, fake);
      fake.emitView('t2', utf8.encode('x' * 500000));
      await t.pump();
      expect(_barValue(t), 0.95, reason: 'never past 95 % while replaying');
      fake.emitView('t2', utf8.encode('y' * 1000));
      await t.pump(const Duration(milliseconds: 399));
      expect(_barValue(t), 0.95);
      expect(_barFade(t).opacity, 1.0, reason: 'quiet for 399 ms: still replaying');
      await t.pump(const Duration(milliseconds: 2));
      expect(_barFade(t).opacity, 0.0, reason: 'quiet for 401 ms: done');
      expect(_barValue(t), 1.0);
      await t.pump(const Duration(seconds: 2));
      await _close(t);
    });

    testWidgets('a drop and a reconnect mid-replay start the bar again from 0', (t) async {
      final fake = _Flaky();
      await _open(t, fake);
      fake.drop.add(const Ready());
      fake.emitView('t2', utf8.encode('x' * 40000));
      await t.pump(const Duration(milliseconds: 50));
      expect(_barValue(t), closeTo(0.1, 1e-9));
      fake.drop.add(const Failed('connection lost', retryIn: Duration(seconds: 3)));
      await t.pump();
      fake.drop.add(const Ready());
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(t.takeException(), isNull);
      expect(_barValue(t), 0.0, reason: 'a fresh replay counts from 0');
      expect(_barFade(t).opacity, 1.0, reason: 'replaying again');
      await t.pump(const Duration(milliseconds: 1600));
      await t.pump(const Duration(milliseconds: 300));
      expect(_barFade(t).opacity, 0.0);
      await _close(t);
    });

    testWidgets('reduced motion: the bar fades in at most 100 ms', (t) async {
      _reduce(t);
      final fake = FakeConnection();
      await _open(t, fake);
      expect(_barFade(t).duration, const Duration(milliseconds: 100));
      await t.pump(const Duration(seconds: 2));
      await _close(t);
    });
  });

  group('reconnect ring', () {
    testWidgets('retry in 0 s: an empty ring at once, no ticker, a stable label', (t) async {
      final h = t.ensureSemantics();
      final fake = _Flaky();
      await _open(t, fake);
      fake.drop.add(const Ready());
      fake.emitView('t2', utf8.encode('output\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      await t.pump(const Duration(milliseconds: 300));
      fake.drop.add(const Failed('connection lost', retryIn: Duration.zero));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(_ring('Retrying in 0 seconds'), findsOneWidget);
      expect(t.binding.transientCallbackCount, 0);
      h.dispose();
      await _close(t);
    });

    testWidgets('no retry time: the banner, but no ring', (t) async {
      final h = t.ensureSemantics();
      final fake = _Flaky();
      await _open(t, fake);
      fake.drop.add(const Ready());
      fake.emitView('t2', utf8.encode('output\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      fake.drop.add(const Failed('connection lost'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Reconnecting to'), findsOneWidget);
      expect(_ring(), findsNothing);
      h.dispose();
      await _close(t);
    });

    testWidgets('TalkBack can read the ring: "Retrying in 4 seconds"', (t) async {
      final h = t.ensureSemantics();
      final fake = _Flaky();
      await _open(t, fake);
      fake.drop.add(const Ready());
      fake.emitView('t2', utf8.encode('output\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      fake.drop.add(const Failed('connection lost', retryIn: Duration(seconds: 4)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(_ring('Retrying in 4 seconds'), findsOneWidget);
      // The banner reads its title and message; the countdown must reach the
      // semantics tree too, or its label is never heard.
      expect(find.bySemanticsLabel(RegExp('Retrying in 4 seconds')), findsOneWidget);
      h.dispose();
      await _close(t);
    });

    testWidgets('a long wait (1 h): it runs, and the label does not tick', (t) async {
      final h = t.ensureSemantics();
      final fake = _Flaky();
      await _open(t, fake);
      fake.drop.add(const Ready());
      fake.emitView('t2', utf8.encode('output\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      fake.drop.add(const Failed('connection lost', retryIn: Duration(hours: 1)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(_ring('Retrying in 3600 seconds'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      expect(t.binding.transientCallbackCount, greaterThan(0), reason: 'still counting down');
      expect(_ring('Retrying in 3600 seconds'), findsOneWidget, reason: 'same label');
      h.dispose();
      await _close(t);
    });

    testWidgets('a second drop restarts the countdown', (t) async {
      final fake = _Flaky();
      await _open(t, fake);
      fake.drop.add(const Ready());
      fake.emitView('t2', utf8.encode('output\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      await t.pump(const Duration(milliseconds: 300));
      fake.drop.add(const Failed('connection lost', retryIn: Duration(seconds: 4)));
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      fake.drop.add(const Failed('connection lost', retryIn: Duration(seconds: 4)));
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      expect(t.binding.transientCallbackCount, greaterThan(0),
          reason: '5 s after the first drop, 2 s into the second wait');
      await t.pump(const Duration(milliseconds: 2100));
      expect(t.binding.transientCallbackCount, 0, reason: 'the second wait is over');
      await _close(t);
    });
  });

  group('terminal output', () {
    testWidgets('no ticker runs between writes while output streams', (t) async {
      final fake = FakeConnection();
      await _ready(t, fake);
      expect(t.binding.transientCallbackCount, 0, reason: 'at rest');
      for (var i = 0; i < 60; i++) {
        fake.emitView('t2', utf8.encode('line $i of the stream\r\n'));
        await t.pump(const Duration(milliseconds: 16));
        expect(t.binding.transientCallbackCount, 0, reason: 'after write $i');
      }
      await _close(t);
    });

    testWidgets('a burst bigger than one frame is written without any animation', (t) async {
      final fake = FakeConnection();
      await _ready(t, fake);
      for (var i = 0; i < 20; i++) {
        fake.emitView('t2', utf8.encode('${'z' * 4000}\r\n'));
      }
      await t.pump(const Duration(milliseconds: 16));
      await t.pump(const Duration(milliseconds: 16));
      expect(t.binding.transientCallbackCount, 0);
      expect(_barFade(t).opacity, 0.0, reason: 'live output is not a replay');
      await _close(t);
    });
  });
}
