import '../data/machine_status.dart';
import '../data/ssh_machines_repo.dart';
import 'machine_connection.dart';

/// One row of the Machines list.
class MachineEntry {
  const MachineEntry({
    required this.info,
    required this.address,
    required this.status,
    this.ssh,
  });

  final MachineInfo info;

  /// `user@host:port` for SSH; empty for an account machine.
  final String address;
  final MachineStatus? status;

  /// The saved SSH machine behind this row, null for an account machine.
  final SshMachine? ssh;

  ConnMode get mode => info.mode;
}

/// Merges account (cloud) machines and SSH machines into one list, grouped
/// by mode: account first, then SSH. It never merges two machines on its
/// own: a computer that is both an account machine and an SSH machine shows
/// twice, and the user removes the one they do not want.
class MachineDirectory {
  const MachineDirectory._();

  static List<MachineEntry> merge({
    required List<MachineInfo> cloud,
    required List<SshMachine> ssh,
    Map<String, MachineStatus> status = const {},
  }) => [
    for (final c in cloud)
      MachineEntry(info: c, address: '', status: null),
    for (final m in ssh)
      MachineEntry(
        info: MachineInfo(
          id: m.id,
          name: m.name,
          os: status[m.id]?.os ?? 'unknown',
          mode: ConnMode.ssh,
          online: status[m.id]?.online ?? false,
        ),
        address: m.address,
        status: status[m.id],
        ssh: m,
      ),
  ];
}
