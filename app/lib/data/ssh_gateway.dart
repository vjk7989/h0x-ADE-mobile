import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../conn/machine_connection.dart';
import 'ssh_machines_repo.dart';

/// This phone's public key as the Add machine screen shows it.
class PhoneKeyInfo {
  const PhoneKeyInfo({
    required this.publicLine,
    required this.fingerprint,
    this.addAgain = false,
  });

  /// `ssh-ed25519 AAAA... hyperox-<device>`: the line for `authorized_keys`.
  final String publicLine;

  /// `SHA256:...`
  final String fingerprint;

  /// The key was regenerated: it must be added to every machine again.
  final bool addAgain;
}

/// One connection attempt to a saved machine. The screens only see this and
/// [ConnState]; lib/data/ssh_gateway_real.dart maps it onto the SSH
/// transport (SshMachineConnection).
abstract class SshSession {
  Stream<ConnState> get state;

  /// Starts connecting; completes with the first settled state (Ready or
  /// Failed). A host key waiting for the user does not settle it.
  Future<ConnState> start();

  /// `unix`, `windows` or `unknown`, once connected.
  String get os;

  void acceptHostKey();
  void replaceHostKey();
  void rejectHostKey();
  Future<void> close();
}

abstract class SshGateway {
  Future<PhoneKeyInfo> phoneKey();
  SshSession open(SshMachine machine);

  /// A started, long-lived connection for the screens (inbox, agent), or
  /// null when this build has no transport.
  MachineConnection? connect(SshMachine machine);

  /// The trusted host key fingerprint of [machine], if any.
  Future<String?> knownFingerprint(SshMachine machine);
}

/// Overridden in main() with the real gateway and in tests with a fake.
final sshGatewayProvider = Provider<SshGateway>(
  (ref) => throw UnimplementedError('sshGatewayProvider is not overridden'),
);
