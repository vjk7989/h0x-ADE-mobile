import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/ssh/core_rpc.dart';
import 'package:hyperox/conn/ssh/known_hosts.dart';
import 'package:hyperox/conn/ssh/ssh_connection.dart';
import 'package:hyperox/conn/ssh/ssh_keys.dart';
import 'package:hyperox/conn/ssh/ssh_transport.dart';

import 'support/connection_contract.dart';
import 'support/fake_core.dart';
import 'support/mem_link.dart' show settle;

const _notRecognized = "'sh' is not recognized as an internal or external command,\r\n";

class Rig {
  final core = FakeCoreState();
  final secrets = MemSecrets();
  final transports = <FakeSshTransport>[];
  final delays = <Duration>[];
  var spacesProcess = () => ScriptedProcess(stdout: '{"spaces":[],"agents":[]}', code: 0);
  late RemoteProcess Function(String cmd) exec;
  Object? Function(int attempt)? connectError;
  late final KnownHosts known = KnownHosts(secrets);

  Rig() {
    exec = (cmd) => cmd.contains('bridge spaces') ? spacesProcess() : FakeCoreProcess(core);
  }

  SshMachineConnection make({bool useKey = true}) => SshMachineConnection(
        target: SshTarget(
            id: 'm1', name: 'box', host: 'box.local', username: 'me', useKey: useKey),
        transport: ({required host, required port, required username, required key, required verify}) {
          final t = FakeSshTransport(
            onExec: (c) => exec(c),
            verify: verify,
            connectError: connectError?.call(transports.length),
          );
          transports.add(t);
          return t;
        },
        knownHosts: known,
        keys: SshKeys(secrets),
        delay: (d) async => delays.add(d),
        readyTimeout: const Duration(milliseconds: 200),
      );

  Future<SshMachineConnection> up() async {
    final c = make();
    await c.start();
    await c.state.firstWhere((s) => s is Ready);
    // a pre-trusted host: no prompt
    return c;
  }
}

Future<void> waitFor(bool Function() cond) async {
  for (var i = 0; i < 500 && !cond(); i++) {
    await settle();
  }
  expect(cond(), isTrue, reason: 'timed out waiting');
}

Future<ConnState> until(SshMachineConnection c, bool Function(ConnState) test) =>
    c.state.firstWhere(test).timeout(const Duration(seconds: 5));

void main() {
  connectionContract('SshMachineConnection over a fake core', () async {
    final rig = Rig();
    await rig.known.trust('box.local', 22, 'SHA256:hostkey');
    return rig.up();
  });

  group('SshMachineConnection', () {
    late Rig rig;
    setUp(() async {
      rig = Rig();
      await rig.known.trust('box.local', 22, 'SHA256:hostkey');
    });

    test('unix login: the unix command is used, os unix, state ready', () async {
      final c = await rig.up();
      expect(rig.transports.single.commands.single, unixCommand('connect'));
      expect(c.machine.os, 'unix');
      expect(c.machine.online, isTrue);
      expect(c.machine.mode, ConnMode.ssh);
      await c.close();
    });

    test('the unix command finds core on PATH, then ~/.local/bin, and keeps stdout clean', () {
      final cmd = unixCommand('connect');
      expect(cmd, contains(r'command -v h0x-core'));
      expect(cmd, contains(r'$HOME/.local/bin/h0x-core'));
      expect(cmd, contains('exit 127'));
      expect(cmd, contains('>&2'));
      expect(cmd, endsWith(r'exec "$p" connect' "'"));
    });

    test('a Windows login (cmd or PowerShell) falls back to the Windows command', () async {
      rig.exec = (cmd) {
        if (cmd.startsWith('sh -c')) return ScriptedProcess(stderr: _notRecognized, code: 1);
        if (cmd.contains('bridge spaces')) {
          return ScriptedProcess(stdout: '[{"name":"a","folder":"C:\\\\x"}]', code: 0);
        }
        return FakeCoreProcess(rig.core);
      };
      final c = await rig.up();
      final cmds = rig.transports.single.commands;
      expect(cmds, [unixCommand('connect'), windowsCommand('connect')]);
      expect(cmds[1], startsWith('cmd /d /c "if exist'));
      expect(cmds[1], contains(r'.\AppData\Local\Programs\h0x-core\h0x-core.exe'));
      expect(c.machine.os, 'windows');
      // the second exec (spaces) uses the Windows line too
      final v = await c.spaces();
      expect(rig.transports.single.commands.last, windowsCommand('bridge spaces --show --json'));
      expect(v.spaces.single.folder, r'C:\x');
      await c.close();
    });

    test('exit 127 with core own marker: not on the PATH message, no retry', () async {
      rig.exec = (_) => ScriptedProcess(stderr: '$coreNotHere\n', code: 127);
      final c = rig.make();
      final s = await c.start();
      expect(s, isA<Failed>().having((f) => f.reason, 'reason', missingCoreMessage));
      expect(rig.transports.single.commands, hasLength(1));
      expect(rig.delays, isEmpty, reason: 'a missing core is not retried');
      await c.close();
    });

    test('exit 127 without a message is also a missing core', () async {
      rig.exec = (_) => ScriptedProcess(code: 127);
      final s = await rig.make().start();
      expect((s as Failed).reason, missingCoreMessage);
    });

    test('cmd.exe "is not recognized" on both lines is a missing core', () async {
      rig.exec = (_) => ScriptedProcess(stderr: _notRecognized, code: 1);
      final c = rig.make();
      final s = await c.start();
      expect((s as Failed).reason, missingCoreMessage);
      expect(rig.transports.single.commands, hasLength(2));
      await c.close();
    });

    test('the Windows line reporting no core (exit 127) is a missing core', () async {
      rig.exec = (cmd) => cmd.startsWith('sh -c')
          ? ScriptedProcess(stderr: _notRecognized, code: 1)
          : ScriptedProcess(stderr: '$coreNotHere \r\n', code: 127);
      final s = await rig.make().start();
      expect((s as Failed).reason, missingCoreMessage);
    });

    test('a login banner on stdout is reported, not retried', () async {
      rig.exec = (_) => ScriptedProcess(stdout: 'Welcome to box, authorised use only\n');
      final c = rig.make();
      final s = await c.start();
      expect((s as Failed).reason, bannerMessage);
      expect(rig.delays, isEmpty);
      await c.close();
    });

    test('another protocol generation is reported with what to do', () async {
      rig.exec = (_) => FakeCoreProcess(rig.core, generation: 2);
      final s = await rig.make().start();
      expect((s as Failed).reason, contains('protocol generation'));
    });

    test('approve on a permission sends enter, deny sends esc', () async {
      final c = await rig.up();
      expect(await c.approve('t2'), isA<Done>());
      expect(await c.deny('t2'), isA<Done>());
      expect(
          rig.core.calls.where((x) => x.startsWith('terminal.keys')),
          [
            'terminal.keys {"terminal":"t2","keys":["enter"]}',
            'terminal.keys {"terminal":"t2","keys":["esc"]}',
          ]);
      await c.close();
    });

    test('approve on a question is refused and sends nothing', () async {
      final c = await rig.up();
      final r = await c.approve('t3');
      expect(r, isA<ReplyFailed>().having((f) => f.message, 'message', contains('refused')));
      expect(rig.core.calls.where((x) => x.startsWith('terminal.keys')), isEmpty);
      await c.close();
    });

    test('an unknown terminal gives a failed reply carrying core own message', () async {
      final c = await rig.up();
      final r = await c.interrupt('nope') as ReplyFailed;
      expect(r.message, 'no such terminal');
      await expectLater(c.read('nope'), throwsA(isA<CoreRpcException>()));
      await c.close();
    });

    test('a Windows cwd is passed through unchanged, after a confirm', () async {
      final c = await rig.up();
      final r = await c.run(r'C:\Users\x\proj', 'dir') as NeedsConfirm;
      expect(rig.core.calls.where((x) => x.startsWith('terminal.run')), isEmpty,
          reason: 'nothing runs before confirm');
      expect(await c.confirm(r.token), isA<Done>());
      expect(rig.core.calls.last,
          'terminal.run ${jsonEncode({'line': 'dir', 'cwd': r'C:\Users\x\proj'})}');
      await c.close();
    });

    test('kill asks first, then kills once', () async {
      final c = await rig.up();
      final r = await c.kill('t1') as NeedsConfirm;
      expect(rig.core.terminals, contains('t1'));
      expect(await c.confirm(r.token), isA<Done>());
      expect(rig.core.terminals, isNot(contains('t1')));
      expect(await c.confirm(r.token), isA<ReplyFailed>());
      await c.close();
    });

    test('sessions carry agent, folder, status and group', () async {
      final c = await rig.up();
      final s = {for (final x in await c.sessions()) x.terminal: x};
      expect(s['t2']!.agent, 'codex');
      expect(s['t2']!.folder, '/srv/b');
      expect(s['t2']!.blockedKind, 'permission');
      expect(s['t2']!.group, AgentGroup.needsYou);
      expect(s['t1']!.group, AgentGroup.working);
      rig.core.terminals['t4'] = terminal('t4', 'old', 'working', live: false);
      expect((await c.sessions()).firstWhere((x) => x.terminal == 't4').group, AgentGroup.idle);
      await c.close();
    });

    test('spaces: parsed from the second exec; an old core says unsupported', () async {
      final c = await rig.up();
      rig.spacesProcess = () => ScriptedProcess(
          stdout: jsonEncode({
            'spaces': [
              {
                'name': 'app',
                'folder': '/srv/a',
                'tabs': [
                  {'name': 'main', 'panes': ['build']}
                ]
              }
            ],
            'agents': [
              {'slot': 1, 'name': 'claude', 'command': 'claude'}
            ]
          }),
          code: 0);
      final v = await c.spaces();
      expect(rig.transports.single.commands.last, unixCommand('bridge spaces --show --json'));
      expect(v.supported, isTrue);
      expect(v.spaces.single.tabs.single.panes, ['build']);
      expect(v.agents.single.command, 'claude');

      rig.spacesProcess =
          () => ScriptedProcess(stderr: "error: unrecognized subcommand 'spaces'", code: 2);
      expect((await c.spaces()).supported, isFalse);

      rig.spacesProcess = () => ScriptedProcess(stderr: 'disk on fire', code: 1);
      await expectLater(c.spaces(), throwsStateError);
      await c.close();
    });

    test('view streams raw bytes and sizes; closing detaches', () async {
      final c = await rig.up();
      final v = await c.view('t1', history: 100);
      expect(rig.core.calls.last,
          'terminal.attach ${jsonEncode({'terminal': 't1', 'cols': 80, 'rows': 24, 'history': 100, 'observe': true, 'resize_notifications': true})}');
      expect(v.initial, const TermSize(100, 30));
      final got = <int>[];
      final sizes = <TermSize>[];
      v.bytes.listen(got.addAll);
      v.sizes.listen(sizes.add);
      rig.core.process!.pushResize(1, 90, 20);
      rig.core.process!.pushData(1, utf8.encode('\x1b[32mgreen\x1b[0m'));
      await waitFor(() => got.isNotEmpty && sizes.isNotEmpty);
      expect(utf8.decode(got), '\x1b[32mgreen\x1b[0m');
      expect(sizes.single, const TermSize(90, 20));
      await v.close();
      await waitFor(() => rig.core.closedChannels.contains(1));
      await c.close();
    });

    test('size reads cols and rows from terminal.get', () async {
      final c = await rig.up();
      expect(await c.size('t2'), const TermSize(100, 30));
      await c.close();
    });

    test('a flood with a paused UI stops being acknowledged', () async {
      final c = await rig.up();
      final v = await c.view('t1');
      final sub = v.bytes.listen((_) {});
      sub.pause();
      final p = rig.core.process!;
      for (var i = 0; i < 70; i++) {
        p.pushData(1, List.filled(1000, 65));
      }
      await settle();
      await settle();
      expect(p.creditsReceived, 0);
      sub.resume();
      await waitFor(() => p.creditsReceived >= 65536);
      await c.close();
    });

    test('the Windows command tries %LOCALAPPDATA% first, quoted, then the home path', () {
      final cmd = windowsCommand('connect');
      const local = r'"%LOCALAPPDATA%\Programs\h0x-core\h0x-core.exe"';
      const home = r'.\AppData\Local\Programs\h0x-core\h0x-core.exe';
      expect(cmd.indexOf(local), greaterThan(0));
      expect(cmd.indexOf(local), lessThan(cmd.indexOf(home)));
      expect(cmd, startsWith('cmd /d /c "if exist $local ($local connect) else if exist $home'));
      expect(cmd, endsWith('exit /b 127)"'));
    });

    test('notices: blocked, done, error and finished only, with agent and folder', () async {
      final c = await rig.up();
      final got = <Notice>[];
      final sub = c.notices().listen(got.add);
      await waitFor(() => rig.core.process!.subscribedChannel != null);
      final p = rig.core.process!;
      p.pushEvent({'type': 'status', 'terminal': 't1', 'seq': 1, 'data': {'status': {'state': 'working'}}});
      p.pushEvent({'type': 'title', 'terminal': 't1', 'seq': 2, 'data': {}});
      p.pushEvent({
        'type': 'status',
        'terminal': 't2',
        'seq': 3,
        'data': {'status': {'state': 'blocked', 'kind': 'permission', 'msg': 'allow rm?'}}
      });
      p.pushEvent({'type': 'finished', 'terminal': 't1', 'seq': 4, 'data': {}});
      p.pushEvent({'seq': 4}, method: 'heartbeat');
      await waitFor(() => got.length == 2);
      expect(got[0].kind, 'needs_you');
      expect(got[0].terminal, 't2');
      expect(got[0].agent, 'codex');
      expect(got[0].folder, '/srv/b');
      expect(got[0].excerpt, 'allow rm?');
      expect(got[1].kind, 'finished');
      await sub.cancel();
      await c.close();
    });

    test('files: app home from core, missing is null, writes round trip, long files page', () async {
      final c = await rig.up();
      expect(await c.appHome(), '/home/me/.config/h0x-ade');
      expect(await c.readFile('/x/none.md'), isNull);
      await c.writeFile('/x/a.md', '# A
- [ ] one
- [x] two
- [ ] three
');
      rig.core.pageLines = 2;
      expect(await c.readFile('/x/a.md'), '# A
- [ ] one
- [x] two
- [ ] three
');
      await c.writeFile('/x/e.md', '');
      expect(await c.readFile('/x/e.md'), '');
      await c.close();
    });

    test('calls after close fail cleanly as replies', () async {
      final c = await rig.up();
      await c.close();
      expect(await c.send('t1', 'x'), isA<ReplyFailed>());
    });
  });

  group('host keys', () {
    late Rig rig;
    setUp(() => rig = Rig());

    test('first sight: HostKeyNew with the SHA256 fingerprint, accept, then remembered', () async {
      final c = rig.make();
      final first = c.start();
      final s = await until(c, (s) => s is HostKeyNew);
      expect((s as HostKeyNew).fingerprint, 'SHA256:hostkey');
      c.acceptHostKey();
      expect(await first, isA<Ready>());
      expect(await rig.known.lookup('box.local', 22), 'SHA256:hostkey');
      await c.close();

      // the next connection does not ask
      final again = rig.make();
      final states = <ConnState>[];
      final sub = again.state.listen(states.add);
      expect(await again.start(), isA<Ready>());
      expect(states.whereType<HostKeyNew>(), isEmpty);
      await sub.cancel();
      await again.close();
    });

    test('rejecting a new key fails with no retry and stores nothing', () async {
      final c = rig.make();
      final first = c.start();
      await until(c, (s) => s is HostKeyNew);
      c.rejectHostKey();
      expect(await first, isA<Failed>());
      expect(await rig.known.lookup('box.local', 22), isNull);
      expect(rig.delays, isEmpty);
      await c.close();
    });

    test('a changed key blocks: only an explicit replace continues', () async {
      await rig.known.trust('box.local', 22, 'SHA256:old');
      final c = rig.make();
      final first = c.start();
      final s = await until(c, (s) => s is HostKeyChanged) as HostKeyChanged;
      expect(s.known, 'SHA256:old');
      expect(s.offered, 'SHA256:hostkey');
      c.acceptHostKey(); // the new-key button must not pass a changed key
      await settle();
      await settle();
      expect(await c.state.first, isA<HostKeyChanged>());
      expect(await rig.known.lookup('box.local', 22), 'SHA256:old');
      c.replaceHostKey();
      expect(await first, isA<Ready>());
      expect(await rig.known.lookup('box.local', 22), 'SHA256:hostkey');
      await c.close();
    });

    test('a changed key that is not replaced fails and keeps the old entry', () async {
      await rig.known.trust('box.local', 22, 'SHA256:old');
      final c = rig.make();
      final first = c.start();
      await until(c, (s) => s is HostKeyChanged);
      c.rejectHostKey();
      expect(await first, isA<Failed>());
      expect(await rig.known.lookup('box.local', 22), 'SHA256:old');
      await c.close();
    });
  });

  group('connecting', () {
    late Rig rig;
    setUp(() async {
      rig = Rig();
      await rig.known.trust('box.local', 22, 'SHA256:hostkey');
    });

    test('a refused login is fatal: the message is shown, nothing is retried', () async {
      rig.connectError = (_) => SshFatal('login refused: add the phone key');
      final s = await rig.make().start();
      expect((s as Failed).reason, 'login refused: add the phone key');
      await settle();
      expect(rig.transports, hasLength(1));
      expect(rig.delays, isEmpty);
    });

    test('a network error retries with backoff and then connects', () async {
      rig.connectError = (n) => n < 2 ? const SocketException('unreachable') : null;
      final c = rig.make();
      final states = <ConnState>[];
      c.state.listen(states.add);
      await c.start();
      await until(c, (s) => s is Ready);
      expect(rig.transports, hasLength(3));
      expect(rig.delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);
      expect(states.whereType<Failed>(), isNotEmpty);
      await c.close();
    });

    test('a dropped link reconnects and is ready again; backoff resets after ready', () async {
      final c = rig.make();
      final states = <ConnState>[];
      c.state.listen(states.add);
      await c.start();
      rig.core.process!.drop();
      await waitFor(() => rig.transports.length == 2 && states.last is Ready);
      expect(states.whereType<Failed>().first.reason, 'connection lost');
      expect(rig.delays, [const Duration(seconds: 1)]);
      rig.core.process!.drop();
      await waitFor(() => rig.transports.length == 3 && states.last is Ready);
      expect(rig.delays, [const Duration(seconds: 1), const Duration(seconds: 1)]);
      await c.close();
    });

    test('a tailscale target offers no key', () async {
      Object? seen = 'unset';
      final c = SshMachineConnection(
        target: const SshTarget(
            id: 'm', name: 'ts', host: 'box.local', username: 'me', useKey: false),
        transport: ({required host, required port, required username, required key, required verify}) {
          seen = key;
          return FakeSshTransport(onExec: (_) => FakeCoreProcess(rig.core), verify: verify);
        },
        knownHosts: rig.known,
        keys: SshKeys(rig.secrets),
        delay: (d) async {},
      );
      await c.start();
      expect(seen, isNull);
      expect(rig.secrets.map, isNot(contains(SshKeys.storeKey)), reason: 'no key was generated');
      await c.close();
    });

    test('with a key target the phone key is generated on first use', () async {
      await rig.up();
      expect(rig.secrets.map, contains(SshKeys.storeKey));
    });

    test('calls after a fatal failure throw a state error naming the reason', () async {
      rig.exec = (_) => ScriptedProcess(stdout: 'Welcome\n');
      final c = rig.make();
      await c.start();
      await expectLater(
          c.sessions(),
          throwsA(isA<StateError>().having((e) => e.message, 'message', contains(bannerMessage))));
      await c.close();
    });
  });

  test('Backoff doubles to a 30 s ceiling and resets', () {
    final b = Backoff();
    expect([for (var i = 0; i < 8; i++) b.next().inSeconds], [1, 2, 4, 8, 16, 30, 30, 30]);
    b.reset();
    expect(b.next().inSeconds, 1);
  });
}
