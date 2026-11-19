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
import 'support/golden_expect.dart';
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
}) => pumpShellGolden(
  t,
  at,
  brightness: b,
  frame: frame,
  stored: storedMachines([devbox]),
  overrides: _overrides(),
);

Future<void> _expectImage(WidgetTester t, ui.Image img, String name) =>
    expectLater(img, matchesGoldenFile('goldens/$name.png'));

/// The sliding pill: the DecoratedBox inside the nav's AnimatedPositioned.
Finder get _pill => find.descendant(
  of: find.byType(AnimatedPositioned),
  matching: find.byType(DecoratedBox),
);

void main() {
  const times = [0, 50, 100, 150, 200];

  testWidgets('golden: the pill slides from Inbox to Machines, light', (t) async {
    await _open(t, '/inbox');
    await t.tap(find.text('Machines').last);
    await t.pump();
    await _expectImage(t, await strip(t, times: times), 'nav_pill_strip_light');
    await t.pumpAndSettle();
  });

  testWidgets('golden: the pill slides down the rail, dark tablet', (t) async {
    await _open(t, '/inbox', b: Brightness.dark, frame: Frame.tablet);
    await t.tap(find.text('Machines').first);
    await t.pump();
    await _expectImage(t, await strip(t, times: times, scale: 0.4), 'nav_rail_pill_strip_dark');
    await t.pumpAndSettle();
  });

  testWidgets('golden: a keyboard-focused nav item, light', (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await _open(t, '/machines');
    Focus.maybeOf(t.element(find.text('Spaces')))!.requestFocus();
    await t.pumpAndSettle();
    await expectGolden(find.byType(MaterialApp), 'nav_focus_light');
  });

  testWidgets('golden: reduced motion, the pill is on Machines at once, light', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _open(t, '/inbox');
    await t.tap(find.text('Machines').last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 1));
    await expectGolden(find.byType(MaterialApp), 'nav_reduce_motion_light');
  });

  group('pill motion', () {
    testWidgets('it moves between the items over 200 ms', (t) async {
      await _open(t, '/inbox');
      final x0 = t.getTopLeft(_pill.first).dx;
      await t.tap(find.text('Machines').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final mid = t.getTopLeft(_pill.first).dx;
      await t.pumpAndSettle();
      final x1 = t.getTopLeft(_pill.first).dx;
      expect(x1, greaterThan(x0));
      expect(mid, greaterThan(x0));
      expect(mid, lessThan(x1), reason: 'sliding, not jumping');
    });

    testWidgets('with reduced motion it jumps', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _open(t, '/inbox');
      final x0 = t.getTopLeft(_pill.first).dx;
      await t.tap(find.text('Machines').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 1));
      final x1 = t.getTopLeft(_pill.first).dx;
      await t.pumpAndSettle();
      expect(t.getTopLeft(_pill.first).dx, x1);
      expect(x1, greaterThan(x0));
    });

    testWidgets('on the rail the pill moves vertically', (t) async {
      await _open(t, '/inbox', frame: Frame.tablet);
      final y0 = t.getTopLeft(_pill.first).dy;
      await t.tap(find.text('Spaces').first);
      await t.pumpAndSettle();
      expect(t.getTopLeft(_pill.first).dy, greaterThan(y0));
    });

    testWidgets('every item is a labelled button and the selected one says so', (t) async {
      final h = t.ensureSemantics();
      await _open(t, '/machines');
      expect(find.bySemanticsLabel('Machines, selected'), findsOneWidget);
      expect(find.bySemanticsLabel('Spaces'), findsOneWidget);
      h.dispose();
    });
  });
}
