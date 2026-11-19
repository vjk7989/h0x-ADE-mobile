import 'dart:async';

import '../conn/machine_connection.dart';
import 'ssh_gateway.dart';
import 'ssh_machines_repo.dart';

/// INTERIM: used by main() while lib/conn/ssh does not compile (see the
/// hand-off). It lets the app build and the screens run; nothing connects.
/// Delete this file and use RealSshGateway in main.dart once it compiles.
class StubSshGateway implements SshGateway {
  const StubSshGateway();

  static const _why = 'the SSH transport is not in this build yet';

  @override
  Future<PhoneKeyInfo> phoneKey() => Future.error(_why);

  @override
  SshSession open(SshMachine machine) => _StubSession();

  @override
  MachineConnection? connect(SshMachine machine) => null;

  @override
  Future<String?> knownFingerprint(SshMachine machine) async => null;
}

class _StubSession implements SshSession {
  @override
  Stream<ConnState> get state => const Stream.empty();

  @override
  Future<ConnState> start() async => const Failed('cannot connect: ${StubSshGateway._why}');

  @override
  String get os => 'unknown';

  @override
  void acceptHostKey() {}

  @override
  void replaceHostKey() {}

  @override
  void rejectHostKey() {}

  @override
  Future<void> close() async {}
}
