import 'dart:async';

import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/data/ssh_gateway.dart';
import 'package:hyperox/data/ssh_machines_repo.dart';

const kFakeKey = PhoneKeyInfo(
  publicLine: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForGoldens hyperox-pixel',
  fingerprint: 'SHA256:4mQe0rT7xLq9ZkP2vB8nYdW1cH5sA3uJ6fGtR0oEiXM',
);

/// What a [FakeSession] does when started.
class FakeBehavior {
  FakeBehavior({
    this.states = const [],
    this.end = const Ready(),
    this.os = 'linux',
    this.hold,
  });

  /// Emitted before the session settles (HostKeyNew and so on).
  final List<ConnState> states;
  final ConnState end;
  final String os;

  /// If set, start() waits for it (after the states).
  final Completer<void>? hold;
}

class FakeSession implements SshSession {
  FakeSession(this.machine, this.behavior);

  final SshMachine machine;
  final FakeBehavior behavior;
  final _state = StreamController<ConnState>.broadcast(sync: true);
  final _decision = Completer<bool>();
  final decisions = <String>[];
  var closed = false;

  @override
  Stream<ConnState> get state => _state.stream;

  @override
  String get os => behavior.os;

  @override
  Future<ConnState> start() async {
    await Future<void>.delayed(Duration.zero);
    for (final s in behavior.states) {
      _state.add(s);
      if (s is HostKeyNew || s is HostKeyChanged) {
        final ok = await _decision.future;
        if (!ok) return const Failed('host key refused');
      }
    }
    if (behavior.hold != null) await behavior.hold!.future;
    return behavior.end;
  }

  @override
  void acceptHostKey() {
    decisions.add('accept');
    if (!_decision.isCompleted) _decision.complete(true);
  }

  @override
  void replaceHostKey() {
    decisions.add('replace');
    if (!_decision.isCompleted) _decision.complete(true);
  }

  @override
  void rejectHostKey() {
    decisions.add('reject');
    if (!_decision.isCompleted) _decision.complete(false);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class FakeGateway implements SshGateway {
  FakeGateway({
    this.key = kFakeKey,
    Map<String, FakeBehavior> byHost = const {},
    this.fallback,
  }) : byHost = {...byHost};

  PhoneKeyInfo key;
  final Map<String, FakeBehavior> byHost;
  FakeBehavior? fallback;
  final sessions = <FakeSession>[];
  final known = <String, String>{};

  @override
  Future<PhoneKeyInfo> phoneKey() async => key;

  @override
  SshSession open(SshMachine machine) {
    final s = FakeSession(
      machine,
      byHost[machine.host] ?? fallback ?? FakeBehavior(),
    );
    sessions.add(s);
    return s;
  }

  @override
  MachineConnection? connect(SshMachine machine) => null;

  @override
  Future<String?> knownFingerprint(SshMachine machine) async =>
      known[machine.host];
}
