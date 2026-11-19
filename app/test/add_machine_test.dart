import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperox/conn/machine_connection.dart';
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
        ex("h0x-core is not on this machine's PATH for SSH logins").title,
        'h0x-core is not installed for SSH logins',
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
        "h0x-core is not on this machine's PATH for SSH logins":
            'h0x-core is not installed for SSH logins',
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
