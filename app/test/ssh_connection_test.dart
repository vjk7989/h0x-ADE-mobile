import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/ssh/core_probe.dart';
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

  SshMachineConnection make({bool useKey = true, String corePath = ''}) => SshMachineConnection(
        target: SshTarget(
            id: 'm1',
            name: 'box',
            host: 'box.local',
            username: 'me',
            useKey: useKey,
            corePath: corePath),
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

    test('the unix login runs the one find-and-start command, once', () async {
      final c = await rig.up();
      expect(rig.transports.single.commands, [unixCommand('connect')]);
      await c.close();
    });

    // A Windows machine as the fake transport sees it: sh is not there, the
    // probe answers with [found], and the core runs from the path it printed.
    RemoteProcess Function(String) windows({
      String? found,
      String stderr = _notRecognized,
      void Function(String)? seen,
    }) =>
        (cmd) {
          seen?.call(cmd);
          if (cmd.startsWith('sh -c')) return ScriptedProcess(stderr: stderr, code: 1);
          if (cmd.startsWith('powershell')) {
            return ScriptedProcess(stdout: 'H0X_OS=windows\r\n${found ?? ''}', code: 0);
          }
          if (cmd.contains('bridge spaces')) {
            return ScriptedProcess(stdout: '[{"name":"a","folder":"C:\\\\x"}]', code: 0);
          }
          return FakeCoreProcess(rig.core);
        };

    const core = 'H0X_CORE=G:\\HyperOx\\core\\h0x-core.exe\r\nH0X_SHORT=G:\\HYPERO~1\\core\\H0X-CO~1.EXE\r\n';

    test('a Windows login: unix attempt, one probe, then the core from the probed path', () async {
      rig.exec = windows(found: core);
      final c = await rig.up();
      final cmds = rig.transports.single.commands;
      expect(cmds, hasLength(3));
      expect(cmds[0], unixCommand('connect'));
      expect(cmds[1], windowsProbeCommand());
      expect(cmds[2], r'cmd /d /c G:\HYPERO~1\core\H0X-CO~1.EXE connect');
      expect(c.machine.os, 'windows');
      // the spaces exec reuses the probed path: no second probe
      final v = await c.spaces();
      expect(rig.transports.single.commands.last,
          r'cmd /d /c G:\HYPERO~1\core\H0X-CO~1.EXE bridge spaces --show --json');
      expect(rig.transports.single.commands.where((x) => x.startsWith('powershell')), hasLength(1));
      expect(v.spaces.single.folder, r'C:\x');
      await c.close();
    });

    test('PowerShell as the login shell is told from cmd; a spaced path is called with &', () async {
      const spaced = 'H0X_CORE=G:\\Hyper Ox\\core\\h0x-core.exe\r\nH0X_SHORT=G:\\Hyper Ox\\core\\h0x-core.exe\r\n';
      const psError =
          "sh : The term 'sh' is not recognized as the name of a cmdlet, function, script file, or operable program.";
      rig.exec = windows(found: spaced, stderr: psError);
      final c = await rig.up();
      expect(rig.transports.single.commands.last, r"& 'G:\Hyper Ox\core\h0x-core.exe' connect");
      await c.close();
    });

    test('cmd as the login shell with a spaced path: quoted for cmd', () async {
      const spaced = 'H0X_CORE=G:\\Hyper Ox\\core\\h0x-core.exe\r\nH0X_SHORT=G:\\Hyper Ox\\core\\h0x-core.exe\r\n';
      rig.exec = windows(found: spaced);
      final c = await rig.up();
      expect(rig.transports.single.commands.last, r'cmd /d /c ""G:\Hyper Ox\core\h0x-core.exe" connect"');
      await c.close();
    });

    test('the override reaches the unix command and the Windows probe', () async {
      final seen = <String>[];
      rig.exec = windows(found: core, seen: seen.add);
      final c = rig.make(corePath: r'G:\HyperOx\core\h0x-core.exe');
      await c.start();
      expect(seen.first, unixCommand('connect', override: r'G:\HyperOx\core\h0x-core.exe'));
      expect(seen[1], windowsProbeCommand(override: r'G:\HyperOx\core\h0x-core.exe'));
      expect(seen.first, endsWith(r"sh 'G:\HyperOx\core\h0x-core.exe'"));
      await c.close();
    });

    test('missing everywhere on Windows: the core-missing state, no retry', () async {
      rig.exec = windows(found: '');
      final c = rig.make();
      final s = await c.start();
      expect(s, isA<CoreMissing>().having((f) => f.reason, 'reason', missingCoreMessage));
      expect(missingCoreMessage, contains('Advanced'));
      expect(rig.delays, isEmpty);
      await c.close();
    });

    test('missing everywhere on unix is the same state', () async {
      rig.exec = (_) => ScriptedProcess(stderr: '$coreNotHere\n', code: 127);
      final s = await rig.make().start();
      expect(s, isA<CoreMissing>());
    });

    test('a Windows probe that prints a banner but no core is missing', () async {
      rig.exec = windows(found: 'Welcome to WIN-BOX\r\n');
      final s = await rig.make().start();
      expect(s, isA<CoreMissing>());
    });

    test('a probe with no Windows marker (a unix box without powershell) keeps the unix error', () async {
      rig.exec = (cmd) => cmd.startsWith('powershell')
          ? ScriptedProcess(stderr: 'sh: 1: powershell: not found', code: 127)
          : ScriptedProcess(stderr: 'bash: line 1: weird failure', code: 2);
      final s = await rig.make().start();
      expect(s, isNot(isA<CoreMissing>()));
      expect((s as Failed).reason, contains('weird failure'));
    });

    test('Git sh on a Windows PATH found nothing: the Windows search runs, not CoreMissing', () async {
      rig.exec = (cmd) {
        if (cmd.startsWith('sh -c')) {
          return ScriptedProcess(stderr: '$coreNotHere\n$onWindowsMarker\n', code: 127);
        }
        if (cmd.startsWith('powershell')) {
          return ScriptedProcess(stdout: 'H0X_OS=windows\r\nH0X_CORE=G:\\HyperOx\\core\\h0x-core.exe\r\nH0X_SHORT=G:\\HYPERO~1\\core\\H0X-CO~1.EXE\r\n', code: 0);
        }
        return FakeCoreProcess(rig.core);
      };
      final c = rig.make();
      expect(await c.start(), isA<Ready>());
      expect(rig.transports.single.commands.last, r'cmd /d /c G:\HYPERO~1\core\H0X-CO~1.EXE connect');
      expect(c.machine.os, 'windows');
      await c.close();
    });

    test('another language: the shell error is not understood, the probe still finds Windows', () async {
      const german = 'Der Befehl "sh" ist entweder falsch geschrieben oder konnte nicht gefunden werden.\r\n';
      const spaced = 'H0X_CORE=G:\\Hyper Ox\\core\\h0x-core.exe\r\nH0X_SHORT=G:\\Hyper Ox\\core\\h0x-core.exe\r\n';
      final seen = <String>[];
      rig.exec = windows(found: spaced, stderr: german, seen: seen.add);
      final c = rig.make();
      expect(await c.start(), isA<Ready>());
      // shell unknown, path with spaces: the launch is the base64 PowerShell script
      expect(seen.last, startsWith('powershell -NoProfile -NonInteractive -NoLogo -EncodedCommand '));
      expect(seen.last, isNot(contains('Hyper Ox')));
      await c.close();
    });

    test('a failure that is not about the core is not reported as missing', () async {
      rig.exec = (_) => ScriptedProcess(stderr: 'sh: 1: boom', code: 3);
      final s = await rig.make().start();
      expect(s, isNot(isA<CoreMissing>()));
      expect((s as Failed).reason, contains('could not start h0x-core'));
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

    test('cmd.exe "is not recognized", probe finds no core: a missing core', () async {
      rig.exec = (cmd) => cmd.startsWith('powershell')
          ? ScriptedProcess(stdout: 'H0X_OS=windows\r\n', code: 0)
          : ScriptedProcess(stderr: _notRecognized, code: 1);
      final c = rig.make();
      final s = await c.start();
      expect((s as Failed).reason, missingCoreMessage);
      expect(rig.transports.single.commands, hasLength(2));
      await c.close();
    });

    test('the Windows line reporting no core (exit 127) is a missing core', () async {
      rig.exec = (cmd) {
        if (cmd.startsWith('sh -c')) return ScriptedProcess(stderr: _notRecognized, code: 1);
        if (cmd.startsWith('powershell')) {
          return ScriptedProcess(stdout: 'H0X_OS=windows\r\nH0X_CORE=C:\\a\\h0x-core.exe\r\n', code: 0);
        }
        return ScriptedProcess(stderr: '$coreNotHere \r\n', code: 127);
      };
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
      await c.writeFile('/x/a.md', '# A\n- [ ] one\n- [x] two\n- [ ] three\n');
      rig.core.pageLines = 2;
      expect(await c.readFile('/x/a.md'), '# A\n- [ ] one\n- [x] two\n- [ ] three\n');
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
