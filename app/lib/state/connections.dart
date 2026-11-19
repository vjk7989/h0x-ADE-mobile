import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../conn/machine_connection.dart';
import '../conn/ssh/ssh_connection.dart';
import '../conn/ssh/ssh_transport.dart';
import '../data/ssh_machines_repo.dart';
import 'ssh.dart';

/// The connections the screens use: one per saved machine, started here.
/// Screens only see [MachineConnection]; tests override this with fakes.
final connectionsProvider = Provider<List<MachineConnection>>((ref) {
  final machines = ref.watch(sshMachinesProvider);
  final keys = ref.watch(sshKeysProvider);
  final known = ref.watch(knownHostsProvider);
  final conns = [
    for (final m in machines)
      SshMachineConnection(
        target: SshTarget(
          id: m.id,
          name: m.name,
          host: m.host,
          port: m.port,
          username: m.user,
          useKey: !m.tailscale,
        ),
        transport: dartssh2Transport,
        knownHosts: known,
        keys: keys,
      ),
  ];
  for (final c in conns) {
    c.start();
  }
  ref.onDispose(() {
    for (final c in conns) {
      c.close();
    }
  });
  return List<MachineConnection>.of(conns);
});
