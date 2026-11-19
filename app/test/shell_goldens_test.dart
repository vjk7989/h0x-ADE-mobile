import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/auth/app_lock.dart';
import 'package:hyperox/data/ssh_gateway.dart';
import 'package:hyperox/conn/machine_connection.dart';
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

List<Override> _overrides(FakeConnection conn) => [
  connectionsProvider.overrideWithValue(<MachineConnection>[conn]),
  sshGatewayProvider.overrideWithValue(FakeGateway(fallback: FakeBehavior())),
  inboxPollProvider.overrideWithValue(null),
  secretStoreProvider.overrideWithValue(MemSecrets()),
  biometricGateProvider.overrideWithValue(_Gate()),
];

/// Every tab inside the real navigation: the bottom bar on a phone, the
/// rail on a tablet (design boards: every tab screen has one).
void main() {
  const tabs = ['/inbox', '/machines', '/spaces', '/todo', '/settings'];
  for (final tab in tabs) {
    final name = tab.substring(1);
    testWidgets('shell $name phone light', (tester) async {
      await pumpShellGolden(
        tester,
        tab,
        stored: storedMachines([devbox]),
        overrides: _overrides(FakeConnection()),
      );
      await expectGolden(
        find.byType(MaterialApp),
        'shell_${name}_phone_light',
      );
    });

    testWidgets('shell $name tablet dark', (tester) async {
      await pumpShellGolden(
        tester,
        tab,
        frame: Frame.tablet,
        brightness: Brightness.dark,
        stored: storedMachines([devbox]),
        overrides: _overrides(FakeConnection()),
      );
      await expectGolden(
        find.byType(MaterialApp),
        'shell_${name}_tablet_dark',
      );
    });
  }
}
