import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../conn/machine_connection.dart';
import 'ssh_gateway.dart';
import 'ssh_machines_repo.dart';

/// What the last probe of a machine found.
class MachineStatus {
  const MachineStatus(this.state, {this.os = 'unknown'});
  final ConnState state;
  final String os;

  bool get online => state is Ready;
  bool get hostKeyChanged => state is HostKeyChanged;
}

const kProbeTimeout = Duration(seconds: 12);

/// Probes each saved SSH machine once (connect, read the state, close). It
/// never trusts or replaces a host key: a new or changed key is only
/// reported, and the user decides on the Machines screen.
class MachineStatusController extends Notifier<Map<String, MachineStatus>> {
  @override
  Map<String, MachineStatus> build() => const {};

  Future<void> refresh() async {
    final machines = ref.read(sshMachinesProvider);
    await Future.wait([for (final m in machines) _probe(m)]);
  }

  void forget(String id) => state = {...state}..remove(id);

  Future<void> _probe(SshMachine m) async {
    final session = ref.read(sshGatewayProvider).open(m);
    ConnState? hostKey;
    final sub = session.state.listen((s) {
      if (s is HostKeyNew || s is HostKeyChanged) {
        hostKey = s;
        session.rejectHostKey();
      }
    });
    try {
      final end = await session.start().timeout(
        kProbeTimeout,
        onTimeout: () => const Failed('timed out'),
      );
      state = {
        ...state,
        m.id: MachineStatus(hostKey ?? end, os: session.os),
      };
    } catch (e) {
      state = {...state, m.id: MachineStatus(Failed('$e'))};
    } finally {
      await sub.cancel();
      await session.close();
    }
  }
}

final machineStatusProvider =
    NotifierProvider<MachineStatusController, Map<String, MachineStatus>>(
      MachineStatusController.new,
    );
