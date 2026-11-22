import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/ssh/ssh_connection.dart' show missingCoreMessage;
import 'package:hyperox/data/ssh_gateway.dart';
import 'package:hyperox/data/ssh_machines_repo.dart';
import 'package:hyperox/screens/add_machine_screen.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:hyperox/theme/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/a11y.dart';
import 'support/fake_gateway.dart';
import 'support/golden.dart';
import 'support/machines_fixture.dart';

/// Pumps Add machine inside a router, so a save can navigate.
Future<(ProviderContainer, FakeGateway)> _pumpRouted(
  WidgetTester tester, {
  FakeBehavior? behavior,
  Map<String, Object> stored = const {},
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final gw = FakeGateway(fallback: behavior ?? FakeBehavior());
  final c = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sshGatewayProvider.overrideWithValue(gw),
    ],
  );
  addTearDown(c.dispose);
  final router = GoRouter(
    initialLocation: '/machines/add',
    routes: [
      GoRoute(path: '/machines', builder: (_, _) => const Text('MACHINES')),
      GoRoute(
        path: '/machines/add',
        builder: (_, _) => const AddMachineScreen(),
      ),
    ],
  );
  tester.view.physicalSize = const Size(411, 919);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        theme: themeData(themeById('paper')),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (c, gw);
}

Future<void> _fill(
  WidgetTester tester, {
  String host = 'devbox.tail3a1f.ts.net',
  String user = 'dev',
  String port = '22',
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), host);
  await tester.enterText(fields.at(1), user);
  await tester.enterText(fields.at(2), port);
}

/// Frames by hand: a spinner animates while connecting, so pumpAndSettle
/// would never settle.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _connect(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Connect'));
  await tester.tap(find.text('Connect'));
  await _frames(tester);
}

void main() {
  group('explainFailure', () {
    ({String title, String hint}) ex(String r, {bool ts = false}) =>
        explainFailure(r, host: 'devbox', port: 22, tailscale: ts);

    test('auth refused', () {
      expect(
        ex('login refused: add the phone key to ~/.ssh/authorized_keys').title,
        'Permission denied (publickey)',
      );
      expect(
        ex('login refused: x', ts: true).title,
        'Tailscale SSH refused the login',
      );
    });
    test('host unreachable', () {
      expect(ex('cannot connect: SocketException').title, 'Cannot reach devbox:22');
      expect(ex('timed out').title, 'Cannot reach devbox:22');
    });
    test('core missing', () {
      expect(
        ex(missingCoreMessage).title,
        'HyperOx core not found',
      );
    });
    test('banner', () {
      expect(
        ex('the login prints text; see docs/machines.md').title,
        'The login prints text',
      );
    });
    test('host key refused and unknown', () {
      expect(ex('host key refused').title, 'Host key not trusted');
      final u = ex('something odd');
      expect(u.title, 'Could not connect');
      expect(u.hint, 'something odd');
    });
  });

  group('AddMachineScreen', () {
    testWidgets('shows this phone\'s key, Copy and Share, and the command', (
      tester,
    ) async {
      await _pumpRouted(tester);
      expect(find.textContaining('ssh-ed25519 AAAA'), findsWidgets);
      expect(find.byTooltip('Copy command with key'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.textContaining("echo 'ssh-ed25519"), findsOneWidget);
      expect(find.textContaining('administrators_authorized_keys'), findsOneWidget);
    });

    testWidgets('validation: empty host, bad port, user with a space', (
      tester,
    ) async {
      await _pumpRouted(tester);
      await _fill(tester, host: '', user: 'de v', port: '0');
      await _connect(tester);
      expect(find.text('Enter a host, IP or Tailscale name'), findsOneWidget);
      expect(find.text('A user name has no spaces'), findsOneWidget);
      expect(find.text('Port is 1 to 65535'), findsOneWidget);
      for (final p in ['65536', 'abc']) {
        await _fill(tester, host: 'devbox', user: 'dev', port: p);
        await _connect(tester);
        expect(find.text('Port is 1 to 65535'), findsOneWidget, reason: p);
      }
    });

    testWidgets('IPv6 literals and *.ts.net names are accepted', (tester) async {
      for (final host in ['[::1]', 'devbox.tail3a1f.ts.net']) {
        final (c, gw) = await _pumpRouted(tester);
        await _fill(tester, host: host);
        await _connect(tester);
        expect(gw.sessions, hasLength(1), reason: host);
        expect(c.read(sshMachinesProvider).single.host, host == '[::1]' ? '::1' : host);
      }
    });

    testWidgets('a good connect saves the machine and opens Machines', (
      tester,
    ) async {
      final (c, gw) = await _pumpRouted(tester);
      await _fill(tester);
      await _connect(tester);
      expect(find.text('MACHINES'), findsOneWidget);
      final m = c.read(sshMachinesProvider).single;
      expect(m.address, 'dev@devbox.tail3a1f.ts.net:22');
      expect(m.name, 'devbox.tail3a1f.ts.net'); // name defaults to the host
      expect(gw.sessions.single.closed, isTrue);
    });

    testWidgets('first host key: trusting saves, cancelling saves nothing', (
      tester,
    ) async {
      final fp = 'SHA256:4mQe0rT7xLq9ZkP2vB8nYdW1cH5sA3uJ6fGtR0oEiXM';
      final (c, gw) = await _pumpRouted(
        tester,
        behavior: FakeBehavior(states: [HostKeyNew(fp)]),
      );
      await _fill(tester);
      await _connect(tester);
      expect(find.text('Trust this machine?'), findsOneWidget);
      expect(find.textContaining('4mQe0rT7xLq9ZkP2'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(FirstHostKeySheet),
          matching: find.text('Cancel'),
        ),
      );
      await _frames(tester);
      expect(c.read(sshMachinesProvider), isEmpty);
      expect(find.text('Host key not trusted'), findsOneWidget);
      expect(gw.sessions.single.decisions, ['reject']);

      await _connect(tester);
      await tester.tap(find.text('Trust and connect'));
      await _frames(tester);
      expect(gw.sessions.last.decisions, ['accept']);
      expect(c.read(sshMachinesProvider), hasLength(1));
    });

    testWidgets('a failed test gives the specific message and saves nothing', (
      tester,
    ) async {
      final cases = {
        'login refused: add the phone key to ~/.ssh/authorized_keys':
            'Permission denied (publickey)',
        'cannot connect: SocketException': 'Cannot reach devbox.tail3a1f.ts.net:22',
        missingCoreMessage: 'HyperOx core not found',
        'the login prints text; see docs/machines.md': 'The login prints text',
      };
      for (final e in cases.entries) {
        final (c, _) = await _pumpRouted(
          tester,
          behavior: FakeBehavior(end: Failed(e.key)),
        );
        await _fill(tester);
        await _connect(tester);
        expect(find.text(e.value), findsOneWidget, reason: e.key);
        expect(c.read(sshMachinesProvider), isEmpty);
      }
    });

    testWidgets('a duplicate is refused without connecting', (tester) async {
      final (c, gw) = await _pumpRouted(
        tester,
        stored: storedMachines([devbox]),
      );
      await _fill(tester, host: 'devbox.tail3a1f.ts.net', user: 'dev');
      await _connect(tester);
      expect(find.text('Already saved'), findsOneWidget);
      expect(gw.sessions, isEmpty);
      expect(c.read(sshMachinesProvider), hasLength(1));
    });

    testWidgets('Tailscale SSH hides the key and offers no key', (tester) async {
      final (c, gw) = await _pumpRouted(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Copy command with key'), findsNothing);
      expect(find.textContaining('no key is offered'), findsOneWidget);
      await _fill(tester);
      await _connect(tester);
      expect(c.read(sshMachinesProvider).single.tailscale, isTrue);
      expect(gw.sessions.single.machine.tailscale, isTrue);
    });

    testWidgets('Cancel while connecting saves nothing', (tester) async {
      final hold = Completer<void>();
      final (c, gw) = await _pumpRouted(
        tester,
        behavior: FakeBehavior(hold: hold),
      );
      await _fill(tester);
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Connecting…'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      hold.complete();
      await tester.pumpAndSettle();
      expect(c.read(sshMachinesProvider), isEmpty);
      expect(find.text('Connect'), findsOneWidget);
      expect(gw.sessions.single.closed, isTrue);
    });
  });

  group('Core path (Advanced)', () {
    testWidgets('collapsed by default; Advanced opens the field', (tester) async {
      await _pumpRouted(tester);
      expect(find.text('Advanced'), findsOneWidget);
      expect(find.text('Core path (optional)'), findsNothing);
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Core path (optional)'), findsOneWidget);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Core path (optional)'), findsNothing);
    });

    testWidgets('a typed core path is stored with the machine and given to the connection', (
      tester,
    ) async {
      final (c, gw) = await _pumpRouted(tester);
      await _fill(tester);
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, r'  G:\HyperOx\core\h0x-core.exe  ');
      await _connect(tester);
      expect(gw.sessions.last.machine.corePath, r'G:\HyperOx\core\h0x-core.exe');
      expect(c.read(sshMachinesProvider).single.corePath, r'G:\HyperOx\core\h0x-core.exe');
    });

    testWidgets('no core path: nothing is stored', (tester) async {
      final (c, gw) = await _pumpRouted(tester);
      await _fill(tester);
      await _connect(tester);
      expect(gw.sessions.last.machine.corePath, '');
      expect(c.read(sshMachinesProvider).single.corePath, '');
    });

    testWidgets('core not found: the error says so and Advanced opens by itself', (tester) async {
      final (c, _) = await _pumpRouted(
        tester,
        behavior: FakeBehavior(end: const CoreMissing(missingCoreMessage)),
      );
      await _fill(tester);
      await _connect(tester);
      expect(find.text('HyperOx core not found'), findsOneWidget);
      expect(find.text('Core path (optional)'), findsOneWidget);
      expect(c.read(sshMachinesProvider), isEmpty);
    });

    testWidgets('a path set after the error is used on the next try', (tester) async {
      final (c, gw) = await _pumpRouted(
        tester,
        behavior: FakeBehavior(end: const CoreMissing(missingCoreMessage)),
      );
      await _fill(tester);
      await _connect(tester);
      await tester.enterText(find.byType(TextField).last, '/opt/hyperox/h0x-core');
      await _connect(tester);
      expect(gw.sessions.last.machine.corePath, '/opt/hyperox/h0x-core');
      expect(c.read(sshMachinesProvider), isEmpty);
    });

    test('cleanCorePath: trim, then one matching pair of quotes', () {
      expect(cleanCorePath(r'  "C:\Program Files\HyperOx\h0x-core.exe"  '), r'C:\Program Files\HyperOx\h0x-core.exe');
      expect(cleanCorePath("'/opt/hyper ox/h0x-core'"), '/opt/hyper ox/h0x-core');
      expect(cleanCorePath(r' " C:\x\h0x-core.exe " '), r'C:\x\h0x-core.exe');
      expect(cleanCorePath(r'"C:\x\h0x-core.exe'), r'"C:\x\h0x-core.exe', reason: 'unmatched: left alone');
      expect(cleanCorePath('"a\''), '"a\'', reason: 'mixed: left alone');
      expect(cleanCorePath('"'), '"');
      expect(cleanCorePath('""'), '');
      expect(cleanCorePath('   '), '');
      expect(cleanCorePath(r"C:\O'Neil\h0x-core.exe"), r"C:\O'Neil\h0x-core.exe", reason: 'inner quote kept');
    });

    test('one damaged entry in the store is skipped, the others stay', () async {
      SharedPreferences.setMockInitialValues({
        'ssh.machines': jsonEncode([
          {'id': 'a', 'name': 'a', 'host': 'h1', 'user': 'u', 'port': 22, 'corePath': 7},
          {'id': 'b', 'name': 'b', 'host': 'h2', 'user': 'u', 'port': 'not a number'},
          'junk',
          null,
          {'id': 'c', 'name': 'c', 'host': 'h3', 'user': 'u', 'port': 22, 'corePath': r'C:\x\h0x-core.exe'},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      final ms = c.read(sshMachinesProvider);
      // a wrong-typed corePath loads as none; a wrong-typed port drops only that entry
      expect([for (final m in ms) m.id], ['a', 'c']);
      expect([for (final m in ms) m.corePath], ['', r'C:\x\h0x-core.exe']);
    });

    test('a machine saved before this existed still loads, and the path round-trips', () {
      final old = SshMachine.fromJson({'id': 'a', 'name': 'a', 'host': 'h', 'user': 'u', 'port': 22});
      expect(old.corePath, '');
      expect(old.toJson().containsKey('corePath'), isFalse);
      final set = old.copyWith(corePath: '/x/h0x-core');
      expect(SshMachine.fromJson(set.toJson()).corePath, '/x/h0x-core');
      expect(set.copyWith(name: 'b').corePath, '/x/h0x-core');
    });

    testWidgets('the repo sets and clears a machine core path', (tester) async {
      final (c, _) = await _pumpRouted(tester, stored: {'ssh.machines': jsonEncode([devbox.toJson()])});
      final repo = c.read(sshMachinesProvider.notifier);
      await repo.setCorePath(devbox.id, ' /opt/x/h0x-core ');
      expect(c.read(sshMachinesProvider).single.corePath, '/opt/x/h0x-core');
      await repo.setCorePath(devbox.id, '');
      expect(c.read(sshMachinesProvider).single.corePath, '');
    });

    Future<void> typeCorePath(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, text);
    }

    for (final (pasted, want) in [
      ('"C:\\Program Files\\HyperOx\\h0x-core.exe"', r'C:\Program Files\HyperOx\h0x-core.exe'),
      (' "G:\\HyperOx\\core\\h0x-core.exe" ', r'G:\HyperOx\core\h0x-core.exe'),
      ("'/opt/hyper ox/h0x-core'", '/opt/hyper ox/h0x-core'),
    ]) {
      testWidgets('a pasted path in quotes is stored without them: $pasted', (tester) async {
        // Found bug: the field is only trimmed of whitespace, so the quotes
        // become part of the path and the probe never finds the file.
        final (c, gw) = await _pumpRouted(tester);
        await _fill(tester);
        await typeCorePath(tester, pasted);
        await _connect(tester);
        expect(gw.sessions.last.machine.corePath, want);
        expect(c.read(sshMachinesProvider).single.corePath, want);
      });
    }

    testWidgets('tabs and newlines pasted around the path are trimmed', (tester) async {
      final (_, gw) = await _pumpRouted(tester);
      await _fill(tester);
      await typeCorePath(tester, '\t/opt/hyperox/h0x-core\n');
      await _connect(tester);
      expect(gw.sessions.last.machine.corePath, '/opt/hyperox/h0x-core');
    });

    testWidgets('a path of only spaces is no path', (tester) async {
      final (c, gw) = await _pumpRouted(tester);
      await _fill(tester);
      await typeCorePath(tester, '    ');
      await _connect(tester);
      expect(gw.sessions.last.machine.corePath, '');
      expect(c.read(sshMachinesProvider).single.toJson().containsKey('corePath'), isFalse);
    });

    testWidgets('UNC, unicode and odd characters are kept exactly', (tester) async {
      const p = r'\\server\share\Zoë 核心\R&D 100% (x86)\h0x-core.exe';
      final (_, gw) = await _pumpRouted(tester);
      await _fill(tester);
      await typeCorePath(tester, p);
      await _connect(tester);
      expect(gw.sessions.last.machine.corePath, p);
    });

    testWidgets('a failure that is not CoreMissing leaves Advanced closed', (tester) async {
      await _pumpRouted(
        tester,
        behavior: FakeBehavior(end: const Failed('login refused: add the phone key to ~/.ssh/authorized_keys')),
      );
      await _fill(tester);
      await _connect(tester);
      expect(find.text('Permission denied (publickey)'), findsOneWidget);
      expect(find.text('Core path (optional)'), findsNothing);
    });

    testWidgets('closed by hand after CoreMissing, Advanced opens again on the next CoreMissing', (tester) async {
      await _pumpRouted(tester, behavior: FakeBehavior(end: const CoreMissing(missingCoreMessage)));
      await _fill(tester);
      await _connect(tester);
      expect(find.text('Core path (optional)'), findsOneWidget);
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Core path (optional)'), findsNothing);
      await _connect(tester);
      expect(find.text('HyperOx core not found'), findsOneWidget);
      expect(find.text('Core path (optional)'), findsOneWidget);
    });

    testWidgets('a key read error is shown on the key card', (tester) async {
      await pumpGolden(
        tester,
        const AddMachineScreen(),
        overrides: [sshGatewayProvider.overrideWithValue(_NoKeyGateway())],
      );
      expect(find.textContaining("cannot read the phone's SSH key"), findsOneWidget);
    });

    testWidgets('golden: the Advanced field open, light', (tester) async {
      await pumpGolden(
        tester,
        const AddMachineScreen(),
        overrides: [sshGatewayProvider.overrideWithValue(FakeGateway())],
      );
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, r'G:\HyperOx\core\h0x-core.exe');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Core path (optional)'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_machine_core_path_light.png'),
      );
    });

    testWidgets('golden: core not found with the field open, dark, text 2.0', (tester) async {
      await pumpGolden(
        tester,
        const AddMachineScreen(),
        brightness: Brightness.dark,
        textScale: 2.0,
        overrides: [
          sshGatewayProvider.overrideWithValue(
            FakeGateway(fallback: FakeBehavior(end: const CoreMissing(missingCoreMessage))),
          ),
        ],
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'devbox.tail3a1f.ts.net');
      await tester.enterText(fields.at(1), 'dev');
      await tester.enterText(fields.at(2), '22');
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await _frames(tester);
      expect(find.text('HyperOx core not found'), findsOneWidget);
      await tester.ensureVisible(find.text('HyperOx core not found'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_machine_core_missing_dark_2.png'),
      );
    });

    testWidgets('golden: core not found, light', (tester) async {
      await pumpGolden(
        tester,
        const AddMachineScreen(),
        overrides: [
          sshGatewayProvider.overrideWithValue(
            FakeGateway(fallback: FakeBehavior(end: const CoreMissing(missingCoreMessage))),
          ),
        ],
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'devbox.tail3a1f.ts.net');
      await tester.enterText(fields.at(1), 'dev');
      await tester.enterText(fields.at(2), '22');
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await _frames(tester);
      await tester.ensureVisible(find.text('HyperOx core not found'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_machine_core_missing_light.png'),
      );
    });

    testWidgets('semantics: the Advanced toggle and the open field', (tester) async {
      await pumpGolden(
        tester,
        const AddMachineScreen(),
        overrides: [sshGatewayProvider.overrideWithValue(FakeGateway())],
        dpr: 3.0,
      );
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });
  });

  group('AddMachineScreen goldens and semantics', () {
    final overrides = <Override>[
      sshGatewayProvider.overrideWithValue(FakeGateway()),
    ];
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final tag = '${dark ? 'dark' : 'light'}_${scale.round()}';
        testWidgets('golden ssh $tag', (tester) async {
          await pumpGolden(
            tester,
            const AddMachineScreen(),
            brightness: dark ? Brightness.dark : Brightness.light,
            textScale: scale,
            overrides: overrides,
          );
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/add_machine_ssh_$tag.png'),
          );
        });
      }
    }

    testWidgets('golden: values typed in, dark; values are foreground, hints muted', (
      tester,
    ) async {
      await pumpGolden(
        tester,
        const AddMachineScreen(),
        brightness: Brightness.dark,
        overrides: overrides,
      );
      final hx = HxColors(themeById('darkmatter').roles);
      // Empty: every field shows a hint, in muted.
      for (final f in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(f.decoration!.hintStyle!.color, hx.muted);
      }
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'devbox.tail3a1f.ts.net');
      await tester.enterText(fields.at(1), 'dev');
      await tester.pump();
      for (final i in [0, 1, 2]) {
        final style = tester.widget<TextField>(fields.at(i)).style!;
        expect(style.color, hx.foreground, reason: 'value style of field $i');
        expect(style.fontFamily, 'JetBrainsMono');
        expect(style.fontSize, 14);
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_machine_ssh_filled_dark.png'),
      );
    });

    testWidgets('golden validation errors, dark', (tester) async {
      await pumpGolden(
        tester,
        const AddMachineScreen(),
        brightness: Brightness.dark,
        overrides: overrides,
      );
      await tester.enterText(find.byType(TextField).at(2), '0');
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_machine_invalid_dark.png'),
      );
    });

    testWidgets('golden tablet', (tester) async {
      await pumpGolden(
        tester,
        const AddMachineScreen(),
        frame: Frame.tablet,
        brightness: Brightness.dark,
        overrides: overrides,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_machine_tablet_dark.png'),
      );
    });

    testWidgets('golden first host key sheet', (tester) async {
      await pumpGolden(
        tester,
        Scaffold(
          body: FirstHostKeySheet(
            address: 'dev@devbox.tail3a1f.ts.net:22',
            fingerprint: 'SHA256:4mQe0rT7xLq9ZkP2vB8nYdW1cH5sA3uJ6fGtR0oEiXM',
            onTrust: () {},
            onCancel: () {},
          ),
        ),
        brightness: Brightness.dark,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_machine_hostkey_dark.png'),
      );
    });

    testWidgets('semantics: first host key sheet', (tester) async {
      await pumpGolden(
        tester,
        Scaffold(
          body: FirstHostKeySheet(
            address: 'dev@devbox.tail3a1f.ts.net:22',
            fingerprint: 'SHA256:4mQe0rT7xLq9ZkP2vB8nYdW1cH5sA3uJ6fGtR0oEiXM',
            onTrust: () {},
            onCancel: () {},
          ),
        ),
        brightness: Brightness.dark,
        dpr: 3.0,
      );
      await expectAccessible(tester);
    });

    testWidgets('semantics: labelled targets of at least 48 dp', (tester) async {
      await pumpGolden(
        tester,
        const AddMachineScreen(),
        overrides: overrides,
        dpr: 3.0,
      );
      await expectAccessible(tester);
    });

    testWidgets('semantics: dark with text 2.0', (tester) async {
      await pumpGolden(
        tester,
        const AddMachineScreen(),
        brightness: Brightness.dark,
        textScale: 2.0,
        overrides: overrides,
        dpr: 3.0,
      );
      await expectAccessible(tester);
    });
  });
}

class _NoKeyGateway extends FakeGateway {
  @override
  Future<PhoneKeyInfo> phoneKey() async =>
      throw StateError("cannot read the phone's SSH key: boom; try again");
}
