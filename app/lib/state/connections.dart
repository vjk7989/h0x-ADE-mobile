import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../conn/machine_connection.dart';
import '../conn/panel/panel_connection.dart';
import '../conn/ssh/ssh_connection.dart';
import '../conn/ssh/ssh_transport.dart';
import '../data/panel_machines_repo.dart';
import '../data/ssh_machines_repo.dart';
import 'ssh.dart';

/// The connections the screens use: one per saved machine, started here.
/// Screens only see [MachineConnection]; tests override this with fakes.
final connectionsProvider = Provider<List<MachineConnection>>((ref) {
  final panels = ref.watch(panelMachinesProvider);
  final panelRepo = ref.read(panelMachinesProvider.notifier);
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
          corePath: m.corePath,
        ),
        transport: dartssh2Transport,
        knownHosts: known,
        keys: keys,
      ),
  ];
  final panelConns = [
    for (final m in panels)
      PanelMachineConnection(panel: m, secrets: () => panelRepo.secrets(m.id)),
  ];
  for (final c in [...conns, ...panelConns]) {
    c.start();
  }
  ref.onDispose(() {
    for (final c in [...conns, ...panelConns]) {
      c.close();
    }
  });
  return <MachineConnection>[...conns, ...panelConns];
});

/// The live state of a paired panel machine, by its id (Machines screen).
final panelStateProvider = StreamProvider.family<ConnState, String>((ref, id) {
  for (final c in ref.watch(connectionsProvider)) {
    if (c.machine.id == id) return c.state;
  }
  return const Stream<ConnState>.empty();
});
