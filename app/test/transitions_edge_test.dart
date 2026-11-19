import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperox/auth/app_lock.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/data/ssh_gateway.dart';
import 'package:hyperox/screens/agent_screen.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/inbox.dart';
import 'package:hyperox/state/ssh.dart';
import 'package:hyperox/widgets/hx_transitions.dart';
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

const _origin = HxOrigin(
  id: 'edge/row',
  rect: Rect.fromLTWH(16, 100, 328, 90),
  radius: 18,
  color: Colors.white,
);

/// A container transform over a row at [rowTop] (no row when null), both in
/// one Stack, driven by [ctrl]. [reduce] turns "remove animations" on.
Widget _scene(
  AnimationController ctrl,
  AnimationController secondary, {
  double? rowTop = 100,
  bool reduce = false,
  HxOrigin origin = _origin,
}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
      child: Stack(
        children: [
          if (rowTop != null)
            Positioned(
              left: 16,
              top: rowTop,
              width: 328,
              height: 90,
              child: SizedBox(key: HxRowRegistry.keyFor(origin.id)),
            ),
          Positioned.fill(
            child: Builder(
              builder: (context) => HxContainerPage.container(
                context,
                ctrl,
                secondary,
                const Text('page'),
                origin,
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

(AnimationController, AnimationController) _controllers(
  WidgetTester t, {
  double value = 0,
  Duration duration = const Duration(milliseconds: 350),
}) {
  final ctrl = AnimationController(vsync: const TestVSync(), duration: duration)
    ..value = value;
  final secondary = AnimationController(vsync: const TestVSync());
  addTearDown(ctrl.dispose);
  addTearDown(secondary.dispose);
  return (ctrl, secondary);
}

Finder get _clip => find.byType(ClipRRect);

/// The page's own opacity (the nearest Opacity above it).
double _pageOpacity(WidgetTester t) => t
    .widget<Opacity>(find.ancestor(of: find.text('page'), matching: find.byType(Opacity)).first)
    .opacity;

void main() {
  group('container transform', () {
    testWidgets('it starts on the row: same rect, same radius', (t) async {
      final (ctrl, sec) = _controllers(t);
      await t.pumpWidget(_scene(ctrl, sec));
      expect(t.getRect(_clip), _origin.rect);
      expect(t.widget<ClipRRect>(_clip).borderRadius, BorderRadius.circular(18));
      expect(_pageOpacity(t), 0.0, reason: 'the page shows through from 30 %');
    });

    testWidgets('it ends full screen with square corners', (t) async {
      final (ctrl, sec) = _controllers(t);
      await t.pumpWidget(_scene(ctrl, sec));
      ctrl.forward();
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      expect(t.getRect(_clip), Offset.zero & t.view.physicalSize / t.view.devicePixelRatio);
      expect(t.widget<ClipRRect>(_clip).borderRadius, BorderRadius.zero);
      expect(_pageOpacity(t), 1.0);
    });

    testWidgets('back shrinks to where the row is NOW, not where it was', (t) async {
      final (ctrl, sec) = _controllers(t, value: 1);
      await t.pumpWidget(_scene(ctrl, sec));
      // The list scrolled while the agent was open: the row is at 300.
      await t.pumpWidget(_scene(ctrl, sec, rowTop: 300));
      ctrl.reverse();
      await t.pump();
      await t.pump(const Duration(milliseconds: 349));
      final r = t.getRect(_clip);
      expect((r.top - 300).abs(), lessThan(2), reason: 'lands on the row at 300, got $r');
      await t.pump(const Duration(milliseconds: 10));
    });

    testWidgets('the row goes away mid-way back: shared axis, no throw', (t) async {
      final (ctrl, sec) = _controllers(t, value: 1);
      await t.pumpWidget(_scene(ctrl, sec));
      ctrl.reverse();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(_clip, findsOneWidget, reason: 'the row is there: container');
      await t.pumpWidget(_scene(ctrl, sec, rowTop: null));
      await t.pump(const Duration(milliseconds: 50));
      expect(t.takeException(), isNull);
      expect(_clip, findsNothing, reason: 'the row is gone: shared axis');
      expect(find.text('page'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 300));
    });

    testWidgets('a rotation mid-way: it still ends exactly full screen', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final (ctrl, sec) = _controllers(t);
      await t.pumpWidget(_scene(ctrl, sec));
      ctrl.forward();
      await t.pump();
      await t.pump(const Duration(milliseconds: 150));
      t.view.physicalSize = const Size(800, 360);
      await t.pump();
      await t.pump(const Duration(milliseconds: 250));
      expect(t.getRect(_clip), const Rect.fromLTWH(0, 0, 800, 360));
      expect(t.takeException(), isNull);
    });

    testWidgets('a rotation mid-way back: it lands on the row in the new layout', (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final (ctrl, sec) = _controllers(t, value: 1);
      await t.pumpWidget(_scene(ctrl, sec));
      ctrl.reverse();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      t.view.physicalSize = const Size(800, 360);
      await t.pumpWidget(_scene(ctrl, sec, rowTop: 40));
      await t.pump(const Duration(milliseconds: 249));
      final r = t.getRect(_clip);
      expect((r.top - 40).abs(), lessThan(2), reason: 'got $r');
      await t.pump(const Duration(milliseconds: 10));
    });

    testWidgets('reduced motion: a fade of at most 100 ms, no rect, no slide', (t) async {
      final (ctrl, sec) = _controllers(t);
      await t.pumpWidget(_scene(ctrl, sec, reduce: true));
      expect(_clip, findsNothing, reason: 'no container rect when reduced');
      ctrl.forward();
      await t.pump();
      await t.pump(const Duration(milliseconds: 101));
      expect(_pageOpacity(t), 1.0, reason: 'faded in within 100 ms (tokens 18)');
      final move = t.widget<Transform>(
        find.ancestor(of: find.text('page'), matching: find.byType(Transform)).first,
      );
      expect(move.transform.getTranslation().x, 0.0, reason: 'no slide');
      await t.pump(const Duration(milliseconds: 300));
    });

    testWidgets('reduced motion back: also at most 100 ms', (t) async {
      final (ctrl, sec) = _controllers(t, value: 1);
      await t.pumpWidget(_scene(ctrl, sec, reduce: true));
      ctrl.reverse();
      await t.pump();
      await t.pump(const Duration(milliseconds: 101));
      expect(_pageOpacity(t), 0.0, reason: 'faded out within 100 ms');
      await t.pump(const Duration(milliseconds: 300));
    });
  });

  group('shared axis', () {
    Widget axis(AnimationController a, AnimationController s, {bool reduce = false}) =>
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
              child: Builder(
                builder: (context) =>
                    HxSharedAxisPage.sharedAxis(context, a, s, const Text('page')),
              ),
            ),
          ),
        );

    double dx(WidgetTester t) => t
        .widget<Transform>(
          find.ancestor(of: find.text('page'), matching: find.byType(Transform)).first,
        )
        .transform
        .getTranslation()
        .x;

    testWidgets('enters from +30 dp and ends at 0', (t) async {
      final (a, s) = _controllers(t, duration: const Duration(milliseconds: 300));
      await t.pumpWidget(axis(a, s));
      expect(dx(t), 30.0);
      expect(_pageOpacity(t), 0.0);
      a.forward();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(dx(t), 0.0);
      expect(_pageOpacity(t), 1.0);
    });

    testWidgets('covered by the next page it leaves to -30 dp', (t) async {
      final (a, s) = _controllers(t, value: 1, duration: const Duration(milliseconds: 300));
      s.duration = const Duration(milliseconds: 300);
      await t.pumpWidget(axis(a, s));
      s.forward();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(dx(t), -30.0);
      expect(_pageOpacity(t), 0.0);
    });

    testWidgets('reduced: 99 ms is not yet in, 101 ms is in, never a slide', (t) async {
      final (a, s) = _controllers(t, duration: const Duration(milliseconds: 300));
      await t.pumpWidget(axis(a, s, reduce: true));
      a.forward();
      await t.pump();
      await t.pump(const Duration(milliseconds: 99));
      expect(_pageOpacity(t), lessThan(1.0));
      expect(dx(t), 0.0);
      await t.pump(const Duration(milliseconds: 2));
      expect(_pageOpacity(t), 1.0);
      expect(dx(t), 0.0);
    });
  });

  group('router', () {
    testWidgets('an agent opened without a row (deep link) slides in, no container', (t) async {
      await pumpShellGolden(
        t,
        '/inbox',
        stored: storedMachines([devbox, raspi]),
        overrides: _overrides(),
      );
      GoRouter.of(t.element(find.byType(Scaffold).first)).push('/agent/fake/t1');
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final agent = find.byType(AgentScreen);
      expect(agent, findsOneWidget);
      expect(find.ancestor(of: agent, matching: find.byType(ClipRRect)), findsNothing);
      final slide = t.widget<Transform>(
        find.ancestor(of: agent, matching: find.byType(Transform)).first,
      );
      expect(slide.transform.getTranslation().x, greaterThan(0), reason: 'still sliding in');
      await t.pumpAndSettle();
    });

    test('a row that is not on screen gives no origin', () {
      expect(
        HxRowRegistry.originOf('nowhere/none', radius: 18, color: Colors.white),
        isNull,
      );
    });

    test('the registry gives the same key for the same row every time', () {
      expect(identical(HxRowRegistry.keyFor('a/1'), HxRowRegistry.keyFor('a/1')), isTrue);
      expect(identical(HxRowRegistry.keyFor('a/1'), HxRowRegistry.keyFor('a/2')), isFalse);
    });
  });
}
