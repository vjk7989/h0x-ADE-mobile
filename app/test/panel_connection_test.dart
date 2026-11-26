import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/panel/e2e.dart';
import 'package:hyperox/conn/panel/panel_connection.dart';
import 'package:hyperox/conn/panel/panel_link.dart';
import 'package:hyperox/data/panel_machines_repo.dart';

import 'fakes/fake_panel.dart';
import 'support/connection_contract.dart';

const _base = 'https://pc.tail1234.ts.net:8377';

PanelLink _link(FakePanel p, {String code = 'CODE'}) =>
    PanelLink(baseUrl: _base, code: code, fp: p.fp);

PanelMachine _machine(FakePanel p) =>
    PanelMachine(id: 'p1', name: 'pc', baseUrl: _base, fp: p.fp);

/// Pairs against [panel] and returns the saved secrets.
Future<PanelSecrets> _pair(FakePanel panel) async =>
    (await pairWithPanel(_link(panel), label: 'phone', connect: panel.connector)).secrets;

PanelMachineConnection _conn(
  FakePanel panel,
  PanelSecrets? secrets, {
  PanelMachine? machine,
  Duration pingEvery = const Duration(seconds: 20),
  Duration idleLimit = const Duration(seconds: 50),
  Duration timeout = const Duration(seconds: 5),
  List<Duration>? waits,
}) => PanelMachineConnection(
  panel: machine ?? _machine(panel),
  secrets: () async => secrets,
  connect: panel.connector,
  // no real waiting between tries
  delay: (d) async {
    waits?.add(d);
    await Future<void>.delayed(const Duration(milliseconds: 1));
  },
  pingEvery: pingEvery,
  idleLimit: idleLimit,
  timeout: timeout,
);

Future<PanelMachineConnection> _ready(FakePanel panel) async {
  final c = _conn(panel, await _pair(panel));
  expect(await c.start(), isA<Ready>());
  return c;
}

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 400 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ok(), isTrue, reason: 'condition not reached in time');
}

void main() {
  connectionContract('PanelMachineConnection', () => _ready(FakePanel()),
      terminalView: false, files: false);

  group('pairing', () {
    test('pairs with the code and gives the session and the device key', () async {
      final panel = FakePanel();
      final p = await pairWithPanel(_link(panel), label: 'phone', connect: panel.connector);
      expect(p.secrets.token, startsWith('s1'));
      expect(panelUnb64(p.secrets.deviceKey), hasLength(32));
      expect(p.device, 'phone');
      expect(panel.urls.single.toString(), 'wss://pc.tail1234.ts.net:8377/ws');
    });

    test('a wrong or used code is refused with the computer message', () async {
      final panel = FakePanel();
      await expectLater(
        pairWithPanel(_link(panel, code: 'NOPE'), label: 'p', connect: panel.connector),
        throwsA(isA<PanelPairException>()),
      );
      await _pair(panel);
      await expectLater(
        pairWithPanel(_link(panel), label: 'p', connect: panel.connector),
        throwsA(isA<PanelPairException>()),
      );
    });

    test('a wrong fingerprint is a hard stop before anything is sent', () async {
      final panel = FakePanel();
      final bad = PanelLink(baseUrl: _base, code: 'CODE', fp: FakePanel(keyByte: 0x22).fp);
      await expectLater(
        pairWithPanel(bad, label: 'p', connect: panel.connector),
        throwsA(isA<PanelFingerprintMismatch>()),
      );
      expect(panel.conns.single.received, isEmpty);
      expect(panel.pairCode, 'CODE', reason: 'the code was not used up');
    });

    test('nothing answers: times out', () async {
      final silent = FakePanel();
      Future<PanelSocket> connect(Uri u) async => _Silent();
      await expectLater(
        pairWithPanel(_link(silent), label: 'p', connect: connect, timeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('connection', () {
    test('auth with the saved session makes it ready and sends the session once', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      expect(c.machine.online, isTrue);
      final auths = panel.conns.last.received.where((m) => m['name'] == 'auth').toList();
      expect(auths, hasLength(1));
      await c.close();
    });

    test('the sessions command returns the structured list', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      final list = await c.sessions();
      expect(list.map((s) => s.terminal), ['t1', 't2', 't3']);
      expect(list[1].blockedKind, 'permission');
      expect(list[1].message, 'Allow rm -rf?');
      await c.close();
    });

    test('a wrong fingerprint is a hard stop and never retries', () async {
      final panel = FakePanel();
      final secrets = await _pair(panel);
      final other = FakePanel(keyByte: 0x22);
      final c = PanelMachineConnection(
        panel: _machine(panel),
        secrets: () async => secrets,
        connect: other.connector,
        delay: (_) async {},
      );
      final s = await c.start();
      expect(s, isA<Failed>().having((f) => f.retryIn, 'retryIn', isNull));
      expect(s, isNot(isA<ScanAgain>()));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(other.connects, 1);
      expect(other.conns.single.received, isEmpty, reason: 'the session token was never sent');
      await c.close();
    });

    test('a revoked or expired session says scan again and stops', () async {
      final panel = FakePanel();
      final secrets = await _pair(panel);
      panel.revoked = true;
      final before = panel.connects; // the pairing above used one
      final c = _conn(panel, secrets);
      expect(await c.start(), isA<ScanAgain>());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(panel.connects, before + 1, reason: 'no retry loop');
      await c.close();
    });

    test('missing secrets say scan again without touching the network', () async {
      final panel = FakePanel();
      final c = _conn(panel, null);
      expect(await c.start(), isA<ScanAgain>());
      expect(panel.connects, 0);
      await c.close();
    });

    test('a session from another device key is refused', () async {
      final panel = FakePanel();
      final secrets = await _pair(panel);
      final stolen = PanelSecrets(token: secrets.token, deviceKey: panelB64(PanelChannel.newDeviceSecret()));
      final c = _conn(panel, stolen);
      expect(await c.start(), isA<ScanAgain>());
      await c.close();
    });

    test('a restart or a network drop reconnects with the saved session', () async {
      final panel = FakePanel();
      final waits = <Duration>[];
      final c = _conn(panel, await _pair(panel), waits: waits);
      await c.start();
      final states = <ConnState>[];
      final sub = c.state.listen(states.add);
      await panel.dropAll();
      await _until(() => panel.connects == 3 && states.last is Ready);
      expect(states.whereType<Failed>().single.retryIn, const Duration(seconds: 1));
      expect(waits, [const Duration(seconds: 1)]);
      expect((await c.sessions()), isNotEmpty);
      await sub.cancel();
      await c.close();
    });

    test('while the panel is down it retries with growing waits, then recovers', () async {
      final panel = FakePanel();
      final waits = <Duration>[];
      final c = _conn(panel, await _pair(panel), waits: waits);
      await c.start();
      panel.refuse = 3;
      await panel.dropAll();
      await _until(() => panel.conns.length == 3 && c.machine.online);
      expect(waits, [const Duration(seconds: 1), const Duration(seconds: 2), const Duration(seconds: 4), const Duration(seconds: 8)]);
      await c.close();
    });

    test('a pending command fails when the connection drops', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      panel.mute = true;
      final pending = c.send('t1', 'x');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await panel.dropAll();
      expect(await pending, isA<ReplyFailed>());
      await c.close();
    });

    test('a command with no answer times out as a failed reply', () async {
      final panel = FakePanel();
      final c = _conn(panel, await _pair(panel), timeout: const Duration(milliseconds: 60));
      await c.start();
      panel.mute = true;
      expect(await c.send('t1', 'x'), isA<ReplyFailed>());
      await c.close();
    });

    test('a silent panel is dropped after the idle limit and reconnected', () async {
      final panel = FakePanel();
      final c = _conn(
        panel,
        await _pair(panel),
        pingEvery: const Duration(milliseconds: 20),
        idleLimit: const Duration(milliseconds: 60),
        timeout: const Duration(milliseconds: 200),
      );
      await c.start();
      panel.mute = true; // pings are no longer answered
      await _until(() => panel.connects >= 2);
      panel.mute = false;
      await _until(() => c.machine.online);
      await c.close();
    });

    test('pings keep an answering panel connected', () async {
      final panel = FakePanel();
      final c = _conn(
        panel,
        await _pair(panel),
        pingEvery: const Duration(milliseconds: 20),
        idleLimit: const Duration(milliseconds: 80),
      );
      final before = panel.connects; // the pairing above used one
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(panel.connects, before + 1);
      expect(panel.conns.single.received.where((m) => m['name'] == 'ping'), isNotEmpty);
      await c.close();
    });

    test('notices arrive on the notices stream', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      final got = c.notices().first;
      panel.notice('t2', 'needs_you', 'Allow?');
      final n = await got;
      expect((n.terminal, n.kind, n.excerpt, n.agent), ('t2', 'needs_you', 'Allow?', 'claude'));
      await c.close();
    });

    test('spaces and files are not offered; terminal view is unsupported', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      expect((await c.spaces()).supported, isFalse);
      await expectLater(c.view('t1'), throwsA(isA<UnsupportedError>()));
      await expectLater(c.appHome(), throwsA(isA<UnsupportedError>()));
      await c.close();
    });

    test('commands before ready fail instead of throwing', () async {
      final panel = FakePanel();
      final c = _conn(panel, await _pair(panel));
      expect(await c.send('t1', 'x'), isA<ReplyFailed>());
      await c.close();
    });
  });

  group('frames', () {
    Future<(PanelMachineConnection, FakePanel)> up() async {
      final panel = FakePanel();
      return (await _ready(panel), panel);
    }

    test('a replayed frame closes the connection and it reconnects', () async {
      final (c, panel) = await up();
      panel.conns.last.replayLast();
      await _until(() => panel.connects >= 2);
      await _until(() => c.machine.online);
      await c.close();
    });

    test('an out-of-order frame closes the connection', () async {
      final (c, panel) = await up();
      panel.conns.last.pushOutOfOrder();
      await _until(() => panel.connects >= 2);
      await c.close();
    });

    test('a frame over 64 KB closes the connection', () async {
      final (c, panel) = await up();
      panel.conns.last.pushRaw(panelMaxFrame + 1);
      await _until(() => panel.connects >= 2);
      await c.close();
    });

    test('a text frame after the hello closes the connection', () async {
      final (c, panel) = await up();
      panel.conns.last.pushText('{"name":"heartbeat"}');
      await _until(() => panel.connects >= 2);
      await c.close();
    });

    test('a message over 64 KB is refused before it is sent', () async {
      final (c, panel) = await up();
      final r = await c.send('t1', 'x' * panelMaxFrame);
      expect(r, isA<ReplyFailed>());
      final sent = panel.conns.last.received.where((m) => m['name'] == 'command');
      expect(sent, isEmpty);
      await c.close();
    });

    test('a message just under the limit is sent', () async {
      final (c, _) = await up();
      expect(await c.send('t1', 'x' * (panelMaxFrame - 200)), isA<Done>());
      await c.close();
    });
  });

  group('approve is bound to the prompt seen', () {
    test('without a shown prompt it is refused and nothing is sent', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      final r = await c.approve('t2');
      expect(r, isA<ReplyFailed>().having((f) => f.message, 'message', contains('review the prompt first')));
      expect(panel.conns.last.received.where((m) => (m['data'] as Map)['cmd'] == 'approve'), isEmpty);
      await c.close();
    });

    test('a changed prompt is refused', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      await c.sessions();
      panel.terminals['t2']!['msg'] = 'something else';
      final r = await c.approve('t2');
      expect(r, isA<ReplyFailed>().having((f) => f.message, 'message', contains('prompt changed')));
      expect(panel.conns.last.received.where((m) => (m['data'] as Map)['cmd'] == 'approve'), isEmpty);
      await c.close();
    });

    test('an unchanged prompt is approved once; the second needs a new look', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      await c.sessions();
      expect(await c.approve('t2'), isA<Done>());
      expect(await c.approve('t2'), isA<ReplyFailed>());
      await c.close();
    });

    test('a terminal that is no longer blocked is refused', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      await c.sessions();
      panel.terminals['t2']!['status'] = 'working';
      expect(await c.deny('t2'), isA<ReplyFailed>());
      await c.close();
    });
  });
}

/// A socket that never answers.
class _Silent implements PanelSocket {
  final _c = StreamController<Object?>();
  @override
  Stream<Object?> get messages => _c.stream;
  @override
  void send(Object data) {}
  @override
  Future<void> close() async {
    if (!_c.isClosed) await _c.close();
  }
}
