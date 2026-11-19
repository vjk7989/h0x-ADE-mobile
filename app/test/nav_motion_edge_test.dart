import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/auth/app_lock.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/data/ssh_gateway.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/inbox.dart';
import 'package:hyperox/state/ssh.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_connection.dart';
import 'support/fake_core.dart';
import 'support/fake_gateway.dart';
import 'support/golden.dart';
import 'support/machines_fixture.dart';

class _Gate implements BiometricGate {
  @override
  Future<bool> available() async => true;

  @override
  Future<bool> authenticate(String reason) async => true;
}

List<Override> _overrides() => [
  connectionsProvider.overrideWithValue(<MachineConnection>[FakeConnection()]),
  sshGatewayProvider.overrideWithValue(FakeGateway(fallback: FakeBehavior())),
  inboxPollProvider.overrideWithValue(null),
  secretStoreProvider.overrideWithValue(MemSecrets()),
  biometricGateProvider.overrideWithValue(_Gate()),
];

Future<void> _open(
  WidgetTester t,
  String at, {
  Brightness b = Brightness.light,
  Frame frame = Frame.phone,
  double textScale = 1,
}) => pumpShellGolden(
  t,
  at,
  brightness: b,
  frame: frame,
  textScale: textScale,
  stored: storedMachines([devbox]),
  overrides: _overrides(),
);

void _reduce(WidgetTester t) {
  t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// The nav label of [tab] (the bar is after the body in the tree).
Finder _tab(String tab) => find.text(tab).last;

/// The outgoing tab's snapshot.
Finder get _snapshot => find.byType(RawImage);

/// The opacity of the outgoing snapshot (0 when there is none).
double _out(WidgetTester t) {
  if (_snapshot.evaluate().isEmpty) return 0;
  return t
      .widget<Opacity>(find.ancestor(of: _snapshot, matching: find.byType(Opacity)).first)
      .opacity;
}

/// The opacity of the incoming body: the fade-through's Opacity over its
/// Transform.scale (the first in the tree: the body comes before the bar).
double _in(WidgetTester t) => t
    .widget<Opacity>(
      find.byWidgetPredicate((w) => w is Opacity && w.child is Transform).first,
    )
    .opacity;

Future<void> _expectStrip(ui.Image img, String name) async {
  if (!autoUpdateGoldenFiles && !File('test/goldens/$name.png').existsSync()) {
    debugPrint('golden $name.png not generated yet: run app-goldens');
    return;
  }
  await expectLater(img, matchesGoldenFile('goldens/$name.png'));
}

void main() {
  group('fade-through', () {
    testWidgets('the two tabs are never both visible (R3), every 10 ms', (t) async {
      await _open(t, '/inbox');
      await t.tap(_tab('Machines'));
      await t.pump();
      var sawOut = false;
      var sawIn = false;
      for (var ms = 0; ms <= 200; ms += 10) {
        final out = _out(t);
        final inn = _in(t);
        if (out > 0) sawOut = true;
        if (inn > 0 && _snapshot.evaluate().isNotEmpty) sawIn = true;
        expect(out == 0 || inn == 0, isTrue, reason: 'at $ms ms: out $out, in $inn');
        await t.pump(const Duration(milliseconds: 10));
      }
      expect(sawOut, isTrue, reason: 'the old tab did fade out');
      expect(sawIn, isTrue, reason: 'the new tab faded in while the snapshot was up');
      await t.pumpAndSettle();
    });

    testWidgets('rapid taps over four tabs: one snapshot at a time, none after', (t) async {
      await _open(t, '/inbox');
      for (final tab in ['Machines', 'Spaces', 'To-do', 'Settings']) {
        await t.tap(_tab(tab));
        await t.pump();
        expect(_snapshot.evaluate().length, lessThanOrEqualTo(1), reason: 'after $tab');
        await t.pump(const Duration(milliseconds: 30));
        expect(_snapshot.evaluate().length, lessThanOrEqualTo(1), reason: '30 ms after $tab');
      }
      await t.pump(const Duration(milliseconds: 200));
      await t.pump();
      expect(_snapshot, findsNothing, reason: 'the last snapshot is dropped');
      expect(_in(t), 1.0, reason: 'the last tab is fully in');
      final h = t.ensureSemantics();
      expect(find.bySemanticsLabel('Settings, selected'), findsOneWidget);
      h.dispose();
    });

    testWidgets('a tap on the tab that is already selected does not fade', (t) async {
      await _open(t, '/machines');
      await t.tap(_tab('Machines'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(_snapshot, findsNothing);
      expect(_in(t), 1.0);
    });

    testWidgets('a tap back to the first tab mid-fade ends on the first tab', (t) async {
      await _open(t, '/inbox');
      await t.tap(_tab('Machines'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      await t.tap(_tab('Inbox'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      await t.pump();
      expect(_snapshot, findsNothing);
      expect(_in(t), 1.0);
      final h = t.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp(r'^Inbox, selected')), findsOneWidget);
      h.dispose();
    });

    testWidgets('reduced motion: a cross-fade of at most 100 ms, no scale', (t) async {
      _reduce(t);
      await _open(t, '/inbox');
      await t.tap(_tab('Machines'));
      // The frame where the tab changes (the snapshot is taken in it).
      for (var i = 0; i < 5 && _snapshot.evaluate().isEmpty; i++) {
        await t.pump();
      }
      expect(_snapshot, findsOneWidget, reason: 'a cross-fade, not a cut');
      await t.pump(); // the fade's first tick
      await t.pump(const Duration(milliseconds: 50));
      final scale = t.widget<Transform>(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is Opacity && w.child is Transform).first,
          matching: find.byType(Transform),
        ).first,
      );
      expect(scale.transform.getMaxScaleOnAxis(), 1.0, reason: 'no scale when reduced');
      await t.pump(const Duration(milliseconds: 51));
      await t.pump();
      expect(_snapshot, findsNothing, reason: 'over by 100 ms');
      expect(t.binding.transientCallbackCount, 0);
    });

    testWidgets('the nav labels stay right during the slide and the fade', (t) async {
      final h = t.ensureSemantics();
      await _open(t, '/inbox');
      await t.tap(_tab('Machines'));
      await t.pump();
      for (final ms in [0, 50, 100, 150, 200]) {
        if (ms > 0) await t.pump(const Duration(milliseconds: 50));
        expect(find.bySemanticsLabel('Machines, selected'), findsOneWidget, reason: '$ms ms');
        expect(find.bySemanticsLabel(RegExp(r'^Inbox, selected')), findsNothing, reason: '$ms ms');
        expect(find.bySemanticsLabel(RegExp(r'^Inbox')), findsWidgets, reason: '$ms ms');
      }
      await t.pumpAndSettle();
      h.dispose();
    });

    testWidgets('the rail fades through too, and leaves nothing behind', (t) async {
      await _open(t, '/inbox', frame: Frame.tablet);
      await t.tap(find.text('Spaces').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 30));
      expect(_snapshot.evaluate().length, lessThanOrEqualTo(1));
      await t.tap(find.text('Settings').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      await t.pump();
      expect(_snapshot, findsNothing);
      expect(_in(t), 1.0);
    });
  });

  testWidgets('golden: the pill strip at 200 % text, dark', (t) async {
    await _open(t, '/inbox', b: Brightness.dark, textScale: 2);
    await t.tap(_tab('Machines'));
    await t.pump();
    await _expectStrip(
      await strip(t, times: const [0, 50, 100, 150, 200]),
      'nav_pill_strip_text200_dark',
    );
    await t.pumpAndSettle();
  });
}
