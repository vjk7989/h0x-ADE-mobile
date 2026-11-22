import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/auth/app_lock.dart';
import 'package:hyperox/screens/unlock_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/golden.dart';

class _Deny implements BiometricGate {
  @override
  Future<bool> available() async => true;

  @override
  Future<bool> authenticate(String reason) async => false;
}

void main() {
  Future<void> show(WidgetTester t, {required bool locked, required List<int> taps}) async {
    await pumpGolden(
      t,
      AppLockScope(
        child: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => taps.add(1),
              child: const Text('Approve'),
            ),
          ),
        ),
      ),
      stored: {'lock.enabled': locked},
      overrides: [biometricGateProvider.overrideWithValue(_Deny())],
      settle: false,
    );
    await t.pump();
  }

  testWidgets('locked: the screen beneath is not in the semantics tree or tappable',
      (t) async {
    final handle = t.ensureSemantics();
    final taps = <int>[];
    await show(t, locked: true, taps: taps);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.bySemanticsLabel('Approve'), findsNothing);
    expect(find.text('Approve', skipOffstage: false).hitTestable(), findsNothing);
    await t.tap(find.text('Approve', skipOffstage: false), warnIfMissed: false);
    expect(taps, isEmpty);
    handle.dispose();
  });

  testWidgets('unlocked: the screen is reachable', (t) async {
    final handle = t.ensureSemantics();
    final taps = <int>[];
    await show(t, locked: false, taps: taps);
    expect(find.bySemanticsLabel('Approve'), findsOneWidget);
    await t.tap(find.text('Approve'));
    expect(taps, [1]);
    handle.dispose();
  });
}
