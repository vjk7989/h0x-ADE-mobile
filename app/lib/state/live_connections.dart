import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../conn/machine_connection.dart';
import '../data/ssh_gateway.dart';
import '../data/ssh_machines_repo.dart';

/// Keeps one started connection per saved SSH machine for as long as the
/// machine is saved, so a screen opens a terminal without connecting again.
class ConnectionPool {
  final _live = <String, MachineConnection>{};

  List<MachineConnection> sync(SshGateway gateway, List<SshMachine> machines) {
    final ids = {for (final m in machines) m.id};
    for (final id in _live.keys.where((id) => !ids.contains(id)).toList()) {
      unawaited(_live.remove(id)!.close());
    }
    for (final m in machines) {
      if (_live.containsKey(m.id)) continue;
      final c = gateway.connect(m);
      if (c != null) _live[m.id] = c;
    }
    return _live.values.toList();
  }

  Future<void> closeAll() async {
    for (final c in _live.values) {
      await c.close();
    }
    _live.clear();
  }
}

final _poolProvider = Provider<ConnectionPool>((ref) {
  final pool = ConnectionPool();
  ref.onDispose(() => unawaited(pool.closeAll()));
  return pool;
});

/// The started connections of the saved SSH machines (the app overrides
/// `connectionsProvider` with this).
final liveConnectionsProvider = Provider<List<MachineConnection>>((ref) {
  return ref
      .watch(_poolProvider)
      .sync(ref.watch(sshGatewayProvider), ref.watch(sshMachinesProvider));
});
