import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/panel/e2e.dart';
import 'package:hyperox/conn/panel/panel_connection.dart';
import 'package:hyperox/conn/panel/panel_link.dart';
import 'package:hyperox/data/panel_machines_repo.dart';

import 'fakes/fake_panel.dart';

const _base = 'https://pc.tail1234.ts.net:8377';

PanelMachine _machine(FakePanel p, {String base = _base}) =>
    PanelMachine(id: 'p1', name: 'pc', baseUrl: base, fp: p.fp);

Future<PanelSecrets> _pair(FakePanel panel) async => (await pairWithPanel(
  PanelLink(baseUrl: _base, code: 'CODE', fp: panel.fp),
  label: 'phone',
  connect: panel.connector,
)).secrets;

PanelMachineConnection _conn(
  FakePanel panel,
  Future<PanelSecrets?> Function() secrets, {
  PanelMachine? machine,
  PanelConnector? connect,
  Duration pingEvery = const Duration(seconds: 20),
  Duration idleLimit = const Duration(seconds: 50),
  Duration timeout = const Duration(seconds: 5),
  List<Duration>? waits,
}) => PanelMachineConnection(
  panel: machine ?? _machine(panel),
  secrets: secrets,
  connect: connect ?? panel.connector,
  delay: (d) async {
    waits?.add(d);
    await Future<void>.delayed(const Duration(milliseconds: 1));
  },
  pingEvery: pingEvery,
  idleLimit: idleLimit,
  timeout: timeout,
);

Future<PanelMachineConnection> _ready(FakePanel panel, {List<Duration>? waits}) async {
  final s = await _pair(panel);
  final c = _conn(panel, () async => s, waits: waits);
  expect(await c.start(), isA<Ready>());
  return c;
}

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 400 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ok(), isTrue, reason: 'condition not reached in time');
}

Iterable<Map<String, dynamic>> _cmds(FakePanel panel, String cmd) => [
  for (final c in panel.conns)
    ...c.received.where((m) => m['name'] == 'command' && (m['data'] as Map)['cmd'] == cmd),
];

/// The size of a sealed frame carrying [msg] (AES-GCM adds a 16-byte tag).
int _sealed(Map<String, Object?> msg) => utf8.encode(jsonEncode(msg)).length + 16;

void main() {
  group('pairing edges', () {
    test('edge: a malformed or altered fingerprint stops pairing before the code is sent', () async {
      final panel = FakePanel();
      final good = panel.fp;
      final i = good.indexOf(RegExp('[a-zA-Z]'));
      final flipped = good.substring(0, i) +
          (good[i] == good[i].toUpperCase() ? good[i].toLowerCase() : good[i].toUpperCase()) +
          good.substring(i + 1);
      for (final fp in ['not-a-fingerprint', '$good=', flipped, good.substring(1), ' $good']) {
        await expectLater(
          pairWithPanel(PanelLink(baseUrl: _base, code: 'CODE', fp: fp), label: 'p', connect: panel.connector),
          throwsA(isA<PanelFingerprintMismatch>()),
          reason: fp,
        );
      }
      expect(panel.conns.every((c) => c.received.isEmpty), isTrue, reason: 'the code never left the phone');
      expect(panel.conns.every((c) => c.closed), isTrue, reason: 'every refused socket is closed');
      expect(panel.pairCode, 'CODE');
    });

    test('edge: a binary frame before the hello is refused', () async {
      Future<PanelSocket> connect(Uri u) async => _Scripted([Uint8List(32)]);
      await expectLater(
        pairWithPanel(PanelLink(baseUrl: _base, code: 'CODE', fp: FakePanel().fp), label: 'p', connect: connect),
        throwsA(isA<PanelE2eError>()),
      );
    });

    test('edge: a socket closed before the hello is an error, not a hang', () async {
      Future<PanelSocket> connect(Uri u) async => _Scripted(const [], closeAfter: true);
      await expectLater(
        pairWithPanel(
          PanelLink(baseUrl: _base, code: 'CODE', fp: FakePanel().fp),
          label: 'p',
          connect: connect,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('urls', () {
    test('edge: ipv6, ts.net without a port and punycode hosts become wss /ws urls', () async {
      for (final (base, want) in [
        ('https://[fd7a:115c:a1e0::1]:8377', 'wss://[fd7a:115c:a1e0::1]:8377/ws'),
        ('https://pc.tail1234.ts.net', 'wss://pc.tail1234.ts.net/ws'),
        ('https://xn--bcher-kva.example:8377', 'wss://xn--bcher-kva.example:8377/ws'),
      ]) {
        final panel = FakePanel();
        final s = await _pair(panel);
        final c = _conn(panel, () async => s, machine: _machine(panel, base: base));
        expect(await c.start(), isA<Ready>(), reason: base);
        expect(panel.urls.last.toString(), want);
        await c.close();
      }
    });
  });

  group('reconnect edges', () {
    test('edge: a computer whose key changed after a restart is a hard stop; the token is never sent to it', () async {
      final panel = FakePanel();
      final impostor = FakePanel(keyByte: 0x22);
      var target = panel;
      final s = await _pair(panel);
      final c = _conn(panel, () async => s, connect: (u) => target.connector(u));
      expect(await c.start(), isA<Ready>());
      final states = <ConnState>[];
      final sub = c.state.listen(states.add);
      target = impostor;
      await panel.dropAll();
      await _until(() => states.last is Failed && (states.last as Failed).retryIn == null);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(impostor.connects, 1, reason: 'no retry after a key mismatch');
      expect(impostor.conns.single.received, isEmpty, reason: 'no auth with the session token');
      expect(states.last, isNot(isA<ScanAgain>()));
      expect(c.machine.online, isFalse);
      await sub.cancel();
      await c.close();
    });

    test('edge: a session revoked while connected ends in Scan again and stops retrying', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      final states = <ConnState>[];
      final sub = c.state.listen(states.add);
      panel.revoked = true;
      await panel.dropAll();
      await _until(() => states.last is ScanAgain);
      expect(states.whereType<Failed>().last.retryIn, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(panel.connects, 3, reason: 'pair + first auth + one refused auth, then nothing');
      await sub.cancel();
      await c.close();
    });

    test('edge: secrets removed while connected: the next try says Scan again without connecting', () async {
      final panel = FakePanel();
      PanelSecrets? s = await _pair(panel);
      final c = _conn(panel, () async => s);
      expect(await c.start(), isA<Ready>());
      s = null;
      await panel.dropAll();
      await _until(() => c.machine.online == false);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(await c.state.first, isA<ScanAgain>());
      expect(panel.connects, 2, reason: 'pair + first connect only');
      await c.close();
    });

    test('edge: backoff is bounded at 30 s and resets after a good connect', () async {
      final panel = FakePanel();
      final waits = <Duration>[];
      final c = await _ready(panel, waits: waits);
      panel.refuse = 9;
      await panel.dropAll();
      await _until(() => c.machine.online && panel.refuse == 0);
      expect(waits.map((d) => d.inSeconds), [1, 2, 4, 8, 16, 30, 30, 30, 30, 30]);
      waits.clear();
      await panel.dropAll();
      await _until(() => waits.isNotEmpty && c.machine.online);
      expect(waits, [const Duration(seconds: 1)]);
      await c.close();
    });

    test('edge: a heartbeat timeout reconnects through the backoff and fails pending commands', () async {
      final panel = FakePanel();
      final waits = <Duration>[];
      final s = await _pair(panel);
      final c = _conn(
        panel,
        () async => s,
        waits: waits,
        pingEvery: const Duration(milliseconds: 20),
        idleLimit: const Duration(milliseconds: 60),
        timeout: const Duration(milliseconds: 300),
      );
      await c.start();
      panel.mute = true;
      final pending = c.send('t1', 'x');
      await _until(() => panel.connects >= 3);
      expect(await pending, isA<ReplyFailed>());
      expect(waits.first, const Duration(seconds: 1));
      panel.mute = false;
      await _until(() => c.machine.online);
      await c.close();
    });

    test('edge: close while the secrets are still being read leaves no socket open', () async {
      final panel = FakePanel();
      final s = await _pair(panel);
      final gate = Completer<PanelSecrets?>();
      final c = _conn(panel, () => gate.future);
      unawaited(c.start());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await c.close();
      gate.complete(s);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        panel.conns.skip(1).every((x) => x.closed),
        isTrue,
        reason: 'a connection opened after close() must not stay open',
      );
      expect(c.machine.online, isFalse);
    });

    test('edge: close twice is safe and commands after close fail as replies', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      await c.close();
      await c.close();
      expect(await c.send('t1', 'x'), isA<ReplyFailed>());
      expect(await c.approve('t2'), isA<ReplyFailed>());
      expect(panel.conns.last.closed, isTrue);
    });
  });

  group('frame edges', () {
    Map<String, Object?> notice(String excerpt) => {
      'terminal': 't1',
      'agent': 'claude',
      'folder': '/srv/a',
      'kind': 'done',
      'excerpt': excerpt,
    };

    test('edge: a frame of exactly 64 KB is accepted, one byte more closes the connection', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      final got = <Notice>[];
      final sub = c.notices().listen(got.add);
      final pad = panelMaxFrame - _sealed({'name': 'notice', 'data': notice('')});
      expect(_sealed({'name': 'notice', 'data': notice('x' * pad)}), panelMaxFrame);
      panel.conns.last.push('notice', notice('x' * pad));
      await _until(() => got.length == 1);
      expect(panel.connects, 2, reason: 'still the same connection');
      panel.conns.last.push('notice', notice('y' * (pad + 1)));
      await _until(() => panel.connects >= 3);
      expect(got, hasLength(1), reason: 'the oversized notice is never delivered');
      await sub.cancel();
      await c.close();
    });

    test('edge: a message of exactly 64 KB is sent, one byte more is refused before sending', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      Map<String, Object?> msg(int id, String text) =>
          {'name': 'command', 'data': {'cmd': 'send', 'id': id, 'terminal': 't1', 'text': text}};
      final pad = panelMaxFrame - _sealed(msg(1, ''));
      expect(await c.send('t1', 'x' * pad), isA<Done>());
      expect(await c.send('t1', 'x' * (pad + 1)), isA<ReplyFailed>());
      expect(_cmds(panel, 'send'), hasLength(1));
      expect(c.machine.online, isTrue, reason: 'a refused send does not drop the link');
      await c.close();
    });

    test('edge: an empty binary frame closes the connection', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      panel.conns.last.pushRaw(0);
      await _until(() => panel.connects >= 3);
      await c.close();
    });

    test('edge: a replayed notice is delivered once', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      final got = <Notice>[];
      final sub = c.notices().listen(got.add);
      panel.conns.last.push('notice', notice('once'));
      await _until(() => got.length == 1);
      panel.conns.last.replayLast();
      await _until(() => panel.connects >= 3);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(got, hasLength(1));
      await sub.cancel();
      await c.close();
    });

    test('edge: a frame that skips a counter is not delivered and later frames on that link are ignored', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      final got = <Notice>[];
      final sub = c.notices().listen(got.add);
      final old = panel.conns.last;
      old.sendCtr++;
      old.push('notice', notice('skipped'));
      old.push('notice', notice('after'));
      await _until(() => panel.connects >= 3);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(got, isEmpty);
      await sub.cancel();
      await c.close();
    });

    test('edge: replies with an unknown or non-integer id are ignored', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      panel.conns.last.push('reply', {'id': 999, 'kind': 'done', 'text': 'stray'});
      panel.conns.last.push('reply', {'id': '1', 'kind': 'done', 'text': 'stray'});
      panel.conns.last.push('mystery', {'x': 1});
      final r = await c.read('t1');
      expect(r, 'hello t1');
      expect(panel.connects, 2);
      await c.close();
    });
  });

  group('approve edges', () {
    test('edge: deny without a shown prompt is refused too', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      expect(
        await c.deny('t2'),
        isA<ReplyFailed>().having((f) => f.message, 'message', contains('review the prompt first')),
      );
      expect(_cmds(panel, 'deny'), isEmpty);
      await c.close();
    });

    test('edge: two approves of one shown prompt at once send exactly one', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      await c.sessions();
      final r = await Future.wait([c.approve('t2'), c.approve('t2')]);
      expect(r.whereType<Done>(), hasLength(1));
      expect(r.whereType<ReplyFailed>(), hasLength(1));
      expect(_cmds(panel, 'approve'), hasLength(1));
      await c.close();
    });

    test('edge: a terminal that disappeared after it was shown is refused', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      await c.sessions();
      panel.terminals.remove('t2');
      expect(await c.approve('t2'), isA<ReplyFailed>());
      expect(_cmds(panel, 'approve'), isEmpty);
      await c.close();
    });

    test('edge: a shown question prompt still cannot be approved', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      await c.sessions();
      expect(await c.approve('t3'), isA<ReplyFailed>());
      expect(_cmds(panel, 'approve'), isEmpty);
      await c.close();
    });

    test('edge: the same prompt on another terminal is not a licence to approve this one', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      panel.terminals.remove('t2');
      await c.sessions();
      panel.terminals['t2'] = {
        ...panel.terminals['t3']!,
        'address': 't2',
        'kind': 'permission',
        'msg': 'Which one?',
      };
      expect(await c.approve('t2'), isA<ReplyFailed>());
      expect(_cmds(panel, 'approve'), isEmpty);
      await c.close();
    });

    test('edge: approve while offline fails and the prompt must be reviewed again', () async {
      final panel = FakePanel();
      final c = await _ready(panel);
      await c.sessions();
      panel.refuse = 1000;
      await panel.dropAll();
      await _until(() => !c.machine.online);
      expect(await c.approve('t2'), isA<ReplyFailed>());
      panel.refuse = 0;
      await _until(() => c.machine.online);
      expect(
        await c.approve('t2'),
        isA<ReplyFailed>().having((f) => f.message, 'message', contains('review the prompt first')),
      );
      expect(_cmds(panel, 'approve'), isEmpty);
      await c.close();
    });

    test('edge: approve allowed when the shown prompt still matches, with an empty excerpt too', () async {
      final panel = FakePanel();
      panel.terminals['t2']!['msg'] = '';
      final c = await _ready(panel);
      await c.sessions();
      expect(await c.approve('t2'), isA<Done>());
      expect(_cmds(panel, 'approve').single['data'], containsPair('terminal', 't2'));
      await c.close();
    });
  });

  group('secrets are never logged', () {
    test('edge: pairing, connecting and failing print nothing with the token or device key', () async {
      final printed = <String>[];
      final states = <ConnState>[];
      late PanelSecrets s;
      await runZoned(
        () async {
          final panel = FakePanel();
          s = await _pair(panel);
          final c = _conn(panel, () async => s);
          final sub = c.state.listen(states.add);
          await c.start();
          await c.sessions();
          await c.send('t1', 'x');
          panel.refuse = 2;
          await panel.dropAll();
          await _until(() => panel.refuse == 0 && c.machine.online);
          panel.revoked = true;
          await panel.dropAll();
          await _until(() => states.last is ScanAgain);
          await sub.cancel();
          await c.close();
          final wrong = _conn(FakePanel(keyByte: 0x33), () async => s, machine: _machine(panel));
          states.add(await wrong.start());
          await wrong.close();
        },
        zoneSpecification: ZoneSpecification(print: (_, _, _, line) => printed.add(line)),
      );
      final secrets = [s.token, s.deviceKey];
      for (final line in [...printed, for (final x in states) if (x is Failed) x.reason]) {
        for (final secret in secrets) {
          expect(line.contains(secret), isFalse, reason: 'secret leaked in: $line');
        }
      }
      expect(s.toString(), isNot(contains(s.token)));
      expect(s.toString(), isNot(contains(s.deviceKey)));
    });

    test('edge: the panel code paths have no print, debugPrint or log calls', () {
      final back = String.fromCharCode(92);
      final call = RegExp(r'(^|[^\w.])(print|debugPrint|log)\s*\(|developer\.log\s*\(|stderr\.write|stdout\.write');
      final files = [
        ...Directory('lib/conn/panel').listSync(recursive: true).whereType<File>(),
        File('lib/data/panel_machines_repo.dart'),
        File('lib/screens/scan_screen.dart'),
        File('lib/state/connections.dart'),
      ];
      final bad = <String>[];
      for (final f in files) {
        final path = f.path.replaceAll(back, '/');
        if (!path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].trimLeft();
          if (code.startsWith('//')) continue;
          if (call.hasMatch(lines[i])) bad.add('$path:${i + 1}');
        }
      }
      expect(bad, isEmpty, reason: 'logging in the panel paths: $bad');
    });
  });
}

/// A socket that plays [frames] after the client hello, then maybe closes.
class _Scripted implements PanelSocket {
  _Scripted(this.frames, {this.closeAfter = false});
  final List<Object> frames;
  final bool closeAfter;
  final _c = StreamController<Object?>();

  @override
  Stream<Object?> get messages => _c.stream;

  @override
  void send(Object data) {
    if (_c.isClosed) return;
    frames.forEach(_c.add);
    if (closeAfter) _c.close();
  }

  @override
  Future<void> close() async {
    if (!_c.isClosed) await _c.close();
  }
}
