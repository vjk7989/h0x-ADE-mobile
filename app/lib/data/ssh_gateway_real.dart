import 'dart:async';

import '../conn/machine_connection.dart';
import '../conn/ssh/known_hosts.dart';
import '../conn/ssh/ssh_connection.dart';
import '../conn/ssh/ssh_keys.dart';
import '../conn/ssh/ssh_transport.dart';
import 'ssh_gateway.dart';
import 'ssh_machines_repo.dart';

/// The production gateway: the phone key and known hosts in secure storage,
/// connections over dartssh2 (developer S's lib/conn/ssh).
class RealSshGateway implements SshGateway {
  RealSshGateway([SecretStore? store])
    : _store = store ?? FlutterSecretStore();

  final SecretStore _store;
  late final SshKeys _keys = SshKeys(_store);
  late final KnownHosts _known = KnownHosts(_store);

  @override
  Future<PhoneKeyInfo> phoneKey() async {
    final r = await _keys.ensure();
    return PhoneKeyInfo(
      publicLine: r.key.publicLine,
      fingerprint: r.key.fingerprint,
      addAgain: r.addAgain,
    );
  }

  @override
  SshSession open(SshMachine m) => _RealSession(
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
      knownHosts: _known,
      keys: _keys,
    ),
  );

  @override
  MachineConnection connect(SshMachine m) {
    final c = SshMachineConnection(
      target: SshTarget(
        id: m.id,
        name: m.name,
        host: m.host,
        port: m.port,
        username: m.user,
        useKey: !m.tailscale,
      ),
      transport: dartssh2Transport,
      knownHosts: _known,
      keys: _keys,
    );
    unawaited(c.start());
    return c;
  }

  @override
  Future<String?> knownFingerprint(SshMachine m) =>
      _known.lookup(m.host, m.port);
}

class _RealSession implements SshSession {
  _RealSession(this._c);

  final SshMachineConnection _c;

  @override
  Stream<ConnState> get state => _c.state;

  @override
  Future<ConnState> start() => _c.start();

  @override
  String get os => _c.machine.os;

  @override
  void acceptHostKey() => _c.acceptHostKey();

  @override
  void replaceHostKey() => _c.replaceHostKey();

  @override
  void rejectHostKey() => _c.rejectHostKey();

  @override
  Future<void> close() => _c.close();
}
