import 'dart:ui' as ui;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperox/auth/app_lock.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/data/ssh_gateway.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/inbox.dart';
import 'package:hyperox/state/ssh.dart';
import 'package:hyperox/widgets/hx_transitions.dart';
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
  stored: storedMachines([devbox, raspi]),
  overrides: _overrides(),
);

Future<void> _expectImage(WidgetTester t, ui.Image img, String name) =>
    expectLater(img, matchesGoldenFile('goldens/$name.png'));

void _back(WidgetTester t) =>
    GoRouter.of(t.element(find.byType(Scaffold).first)).pop();

void main() {
  const times = [0, 70, 140, 210, 280, 350];

  testWidgets('golden: an inbox row grows into the agent screen, light', (t) async {
    await _open(t, '/inbox');
    await t.tap(find.text('claude').first);
    await t.pump();
    await _expectImage(t, await strip(t, times: times, scale: 0.4), 'inbox_to_agent_strip_light');
    await t.pumpAndSettle();
  });

  testWidgets('golden: back shrinks the agent screen into its row, light', (t) async {
    await _open(t, '/inbox');
    await t.tap(find.text('claude').first);
    await t.pumpAndSettle();
    _back(t);
    await t.pump();
    await _expectImage(t, await strip(t, times: times, scale: 0.4), 'agent_back_strip_light');
    await t.pumpAndSettle();
    expect(find.text('Inbox'), findsWidgets);
  });

  testWidgets('golden: the machine detail pane cross-fades, dark tablet', (t) async {
    await _open(t, '/machines', b: Brightness.dark, frame: Frame.tablet);
    await t.tap(find.text('raspi').first);
    await t.pump();
    await _expectImage(
      t,
      await strip(t, times: const [0, 50, 100, 150, 200], scale: 0.3),
      'machines_tablet_select_strip_dark',
    );
    await t.pumpAndSettle();
  });

  testWidgets('golden: reduced motion is a short fade, light', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _open(t, '/inbox');
    await t.tap(find.text('claude').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
    await expectGolden(find.byType(MaterialApp), 'transitions_reduce_motion_light');
    await t.pumpAndSettle();
  });

  group('container transform', () {
    testWidgets('it falls back to a shared axis when the row is gone', (t) async {
      final ctrl = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 350),
      )..value = 1;
      addTearDown(ctrl.dispose);
      const origin = HxOrigin(
        id: 'gone/none',
        rect: Rect.fromLTWH(16, 100, 328, 90),
        radius: 18,
        color: Colors.white,
      );
      final secondary = AnimationController(vsync: const TestVSync());
      addTearDown(secondary.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => HxContainerPage.container(
              context,
              ctrl,
              secondary,
              const Text('page'),
              origin,
            ),
          ),
        ),
      );
      // Going forward, no row is needed: the container grows from its rect.
      expect(find.byType(ClipRRect), findsOneWidget);
      ctrl.reverse();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(ClipRRect), findsNothing, reason: 'the row is not on screen');
      expect(find.text('page'), findsOneWidget);
      await t.pumpAndSettle();
    });

    testWidgets('a row on screen gives its rect', (t) async {
      final key = HxRowRegistry.keyFor('row/1');
      await t.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, top: 20),
              child: SizedBox(key: key, width: 100, height: 40),
            ),
          ),
        ),
      );
      expect(HxRowRegistry.rectOf('row/1'), const Rect.fromLTWH(10, 20, 100, 40));
      expect(HxRowRegistry.rectOf('row/none'), isNull);
    });
  });
}
