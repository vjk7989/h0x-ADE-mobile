import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/machine_directory.dart';
import 'package:hyperox/data/machine_status.dart';
import 'package:hyperox/data/ssh_gateway.dart';
import 'package:hyperox/data/ssh_machines_repo.dart';
import 'package:hyperox/screens/machines_screen.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:hyperox/widgets/machine_sheets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/a11y.dart';
import 'support/fake_gateway.dart';
import 'support/golden.dart';
import 'support/machines_fixture.dart';

Future<ProviderContainer> _container(
  Map<String, Object> stored, [
  FakeGateway? gw,
]) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sshGatewayProvider.overrideWithValue(gw ?? FakeGateway()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

final _changed = FakeBehavior(
  states: const [HostKeyChanged(known: 'SHA256:old', offered: 'SHA256:new')],
  end: const Failed('host key refused'),
);

void main() {
  group('SshMachinesController', () {
    test('add, rename, remove persist; duplicates are refused', () async {
      final c = await _container({});
      final n = c.read(sshMachinesProvider.notifier);
      expect(c.read(sshMachinesProvider), isEmpty);
      expect(await n.add(devbox), isTrue);
      expect(await n.add(raspi), isTrue);
      // same user, host (any case) and port
      expect(
        await n.add(
          const SshMachine(
            id: 'x',
            name: 'again',
            host: 'DEVBOX.tail3a1f.ts.net',
            user: 'dev',
          ),
        ),
        isFalse,
      );
      // same host, another port is a different machine
      expect(
        await n.add(
          const SshMachine(
            id: 'y',
            name: 'alt',
            host: 'devbox.tail3a1f.ts.net',
            user: 'dev',
            port: 2222,
          ),
        ),
        isTrue,
      );
      await n.rename('m1', ' work box ');
      await n.remove('m2');
      final raw = c.read(sharedPrefsProvider).getString('ssh.machines')!;
      final names = [
        for (final m in jsonDecode(raw) as List<Object?>)
          (m! as Map<String, Object?>)['name'],
      ];
      expect(names, ['work box', 'alt']);
    });

    test('a name of 0 or 65 characters is rejected before the write', () async {
      final c = await _container(storedMachines([devbox]));
      final n = c.read(sshMachinesProvider.notifier);
      expect(() => n.rename('m1', '   '), throwsArgumentError);
      expect(() => n.rename('m1', 'x' * 65), throwsArgumentError);
      await n.rename('m1', 'x' * 64);
      expect(c.read(sshMachinesProvider).single.name.length, 64);
    });

    test('a damaged store starts empty instead of crashing', () async {
      final c = await _container({'ssh.machines': '{not json'});
      expect(c.read(sshMachinesProvider), isEmpty);
    });

    test('the validators', () {
      expect(validateHost(''), isNotNull);
      expect(validateHost('a b'), isNotNull);
      expect(validateHost('devbox'), isNull);
      expect(validateHost('devbox.tail3a1f.ts.net'), isNull);
      expect(validateHost('192.168.1.42'), isNull);
      expect(validateHost('::1'), isNull);
      expect(validateHost('[fe80::1]'), isNull);
      expect(validateHost('[::zz]'), isNotNull);
      expect(validatePort('22'), isNull);
      expect(validatePort('0'), isNotNull);
      expect(validatePort('65536'), isNotNull);
      expect(validatePort('65535'), isNull);
      expect(validatePort('ssh'), isNotNull);
      expect(validatePort(''), isNotNull);
      expect(validateUser('dev'), isNull);
      expect(validateUser('de v'), isNotNull);
      expect(validateUser(' '), isNotNull);
      expect(normalizeHost(' [::1] '), '::1');
      expect(
        const SshMachine(id: 'a', name: 'a', host: '::1', user: 'u').address,
        'u@[::1]:22',
      );
    });
  });

  group('MachineDirectory', () {
    const cloudInfo = MachineInfo(
      id: 'c1',
      name: 'studio-pc',
      os: 'windows',
      mode: ConnMode.cloud,
      online: true,
    );

    test('zero machines', () {
      expect(MachineDirectory.merge(cloud: const [], ssh: const []), isEmpty);
    });

    test('cloud only', () {
      final l = MachineDirectory.merge(cloud: [cloudInfo], ssh: const []);
      expect(l.single.mode, ConnMode.cloud);
      expect(l.single.ssh, isNull);
    });

    test('SSH only, with the probe status', () {
      final l = MachineDirectory.merge(
        cloud: const [],
        ssh: [devbox],
        status: const {'m1': MachineStatus(Ready(), os: 'linux')},
      );
      expect(l.single.mode, ConnMode.ssh);
      expect(l.single.info.online, isTrue);
      expect(l.single.info.os, 'linux');
      expect(l.single.address, 'dev@devbox.tail3a1f.ts.net:22');
    });

    test('both: account first, no automatic merge of the same name', () {
      final same = const SshMachine(
        id: 's',
        name: 'studio-pc',
        host: 'studio',
        user: 'me',
      );
      final l = MachineDirectory.merge(cloud: [cloudInfo], ssh: [same, devbox]);
      expect(l.map((e) => e.info.name), ['studio-pc', 'studio-pc', 'devbox']);
      expect(l.map((e) => e.mode), [
        ConnMode.cloud,
        ConnMode.ssh,
        ConnMode.ssh,
      ]);
    });
  });

  group('MachineStatusController', () {
    test('probes every machine; a changed key is reported, not trusted', () async {
      final gw = FakeGateway(
        byHost: {'192.168.1.42': _changed},
        fallback: FakeBehavior(os: 'linux'),
      );
      final c = await _container(storedMachines([devbox, raspi]), gw);
      await c.read(machineStatusProvider.notifier).refresh();
      final s = c.read(machineStatusProvider);
      expect(s['m1']!.online, isTrue);
      expect(s['m1']!.os, 'linux');
      expect(s['m2']!.hostKeyChanged, isTrue);
      expect(gw.sessions.every((x) => x.closed), isTrue);
      expect(
        gw.sessions.expand((x) => x.decisions),
        isNot(contains('replace')),
      );
    });

    test('an unreachable machine is offline', () async {
      final gw = FakeGateway(
        fallback: FakeBehavior(end: const Failed('cannot connect: timed out')),
      );
      final c = await _container(storedMachines([devbox]), gw);
      await c.read(machineStatusProvider.notifier).refresh();
      expect(c.read(machineStatusProvider)['m1']!.online, isFalse);
    });
  });

  group('labels', () {
    test('a row is read: name, OS, mode, state', () {
      final e = MachineDirectory.merge(
        cloud: const [],
        ssh: [devbox],
        status: const {'m1': MachineStatus(Ready(), os: 'linux')},
      ).single;
      expect(rowLabel(e), 'devbox, Linux, SSH, online');
      final blocked = MachineDirectory.merge(
        cloud: const [],
        ssh: [raspi],
        status: const {
          'm2': MachineStatus(HostKeyChanged(known: 'a', offered: 'b')),
        },
      ).single;
      expect(rowLabel(blocked), 'raspi, Unknown OS, SSH, host key changed, blocked');
    });

    test('spoken code and fingerprint', () {
      expect(spokenCode('482913'), '4 8 2, 9 1 3');
      expect(
        spokenFingerprint('SHA256:4mQe0rT7xLq9'),
        'fingerprint SHA256 4mQe',
      );
      expect(chunkFingerprint('A' * 40).split('\n').map((l) => l.length), [
        16,
        16,
        8,
      ]);
    });
  });

  group('MachinesScreen', () {
    Future<FakeGateway> pump(
      WidgetTester tester, {
      required List<SshMachine> machines,
      Map<String, FakeBehavior> byHost = const {},
      Brightness brightness = Brightness.light,
      double scale = 1.0,
      Frame frame = Frame.phone,
      double dpr = 1.0,
    }) async {
      final gw = FakeGateway(byHost: byHost, fallback: FakeBehavior());
      await pumpGolden(
        tester,
        // The app puts this screen in the navigation's Scaffold.
        const Scaffold(body: MachinesScreen()),
        brightness: brightness,
        textScale: scale,
        frame: frame,
        dpr: dpr,
        stored: storedMachines(machines),
        overrides: <Override>[sshGatewayProvider.overrideWithValue(gw)],
      );
      return gw;
    }

    testWidgets('empty: the SSH card only in the SSH-only build', (tester) async {
      await pump(tester, machines: const []);
      expect(find.text('No machines yet'), findsOneWidget);
      expect(find.text('SSH'), findsOneWidget);
      expect(find.text('Same account'), findsNothing);
      expect(find.text('Add machine'), findsNothing); // no FAB when empty
    });

    testWidgets('one online, one offline, one blocked row', (tester) async {
      await pump(
        tester,
        machines: [devbox, raspi, gcp],
        byHost: {
          '192.168.1.42': _changed,
          '34.93.12.8': FakeBehavior(end: const Failed('cannot connect: x')),
        },
      );
      final h = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel('devbox, Linux, SSH, online'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'raspi, .*, SSH, host key changed, blocked'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'h0x-gcp, .*, SSH, offline')),
        findsOneWidget,
      );
      expect(find.text('3 machines · 1 online'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Review host key change for raspi'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Add machine'), findsOneWidget);
      h.dispose();
    });

    testWidgets('rename: 0 and 65 characters show an error, 1 saves', (
      tester,
    ) async {
      await pump(tester, machines: [devbox]);
      await tester.longPress(find.text('devbox'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Name must be 1 to 64 characters'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'x' * 65);
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Name must be 1 to 64 characters'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'work');
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('work'), findsOneWidget);
    });

    testWidgets('remove asks first and removes only after the confirm', (
      tester,
    ) async {
      await pump(tester, machines: [devbox]);
      await tester.longPress(find.text('devbox'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from this phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('devbox'), findsOneWidget);
      await tester.longPress(find.text('devbox'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from this phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.text('devbox'), findsNothing);
      expect(find.text('No machines yet'), findsOneWidget);
    });

    testWidgets('review: Do not connect keeps the old key', (tester) async {
      final gw = await pump(
        tester,
        machines: [raspi],
        byHost: {'192.168.1.42': _changed},
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Host key changed'), findsWidgets);
      expect(find.text('SHA256:old'), findsOneWidget);
      expect(find.text('SHA256:new'), findsOneWidget);
      await tester.tap(find.text("Don't connect"));
      await tester.pumpAndSettle();
      // sessions[0] is the first probe, [1] the review connection.
      expect(gw.sessions[1].decisions, ['reject']);
    });

    testWidgets('review: Trust new key needs a second confirmation', (
      tester,
    ) async {
      final gw = await pump(
        tester,
        machines: [raspi],
        byHost: {'192.168.1.42': _changed},
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trust new key…'));
      await tester.pumpAndSettle();
      expect(find.text('Trust the new key?'), findsOneWidget);
      expect(gw.sessions[1].decisions, isEmpty); // nothing replaced yet
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(gw.sessions[1].decisions, ['reject']);
    });

    for (final dark in [false, true]) {
      final b = dark ? Brightness.dark : Brightness.light;
      final tag = dark ? 'dark' : 'light';
      for (final scale in [1.0, 2.0]) {
        testWidgets('golden mixed list $tag text $scale', (tester) async {
          await pump(
            tester,
            machines: [devbox, raspi, gcp],
            byHost: {
              '192.168.1.42': _changed,
              '34.93.12.8': FakeBehavior(end: const Failed('cannot connect: x')),
            },
            brightness: b,
            scale: scale,
          );
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/machines_list_${tag}_${scale.round()}.png'),
          );
        });
      }
      testWidgets('golden empty $tag', (tester) async {
        await pump(tester, machines: const [], brightness: b);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/machines_empty_$tag.png'),
        );
      });
    }

    testWidgets('golden tablet', (tester) async {
      await pump(
        tester,
        machines: [devbox, raspi],
        byHost: {'192.168.1.42': _changed},
        brightness: Brightness.dark,
        frame: Frame.tablet,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/machines_tablet_dark.png'),
      );
    });

    testWidgets('semantics: list, light then dark at text 2.0', (tester) async {
      await pump(
        tester,
        machines: [devbox, raspi],
        byHost: {'192.168.1.42': _changed},
        dpr: 3.0,
      );
      await expectAccessible(tester);
      await pump(
        tester,
        machines: [devbox, raspi],
        byHost: {'192.168.1.42': _changed},
        brightness: Brightness.dark,
        scale: 2.0,
        dpr: 3.0,
      );
      await expectAccessible(tester);
    });

    testWidgets('semantics: empty state', (tester) async {
      await pump(tester, machines: const [], dpr: 3.0);
      await expectAccessible(tester);
    });
  });

  group('sheets', () {
    testWidgets('host key changed sheet and approval sheet: goldens + a11y', (
      tester,
    ) async {
      var dont = 0;
      await pumpGolden(
        tester,
        Scaffold(
          body: HostKeyChangedSheet(
            machineName: 'raspi',
            address: 'pi@192.168.1.42:22',
            known: 'SHA256:9fWqX2vHk8mL1nRzT4cYb7JdA3eUo5sPiGt0QxVwM2z',
            offered: 'SHA256:Qm7xT1cBn5Za8RvLd2KfWy9HuJ3ePo6sGt0XiAcN4rE',
            onDontConnect: () => dont++,
            onTrustNew: () {},
          ),
        ),
        brightness: Brightness.dark,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/machines_hostkey_dark.png'),
      );
      await tester.tap(find.text("Don't connect"));
      expect(dont, 1);

      await pumpGolden(
        tester,
        Scaffold(
          body: ApprovalSheet(
            machineName: 'studio-pc',
            code: '482913',
            onCancel: () {},
          ),
        ),
      );
      final h = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel('Approval code 4 8 2, 9 1 3'),
        findsOneWidget,
      );
      h.dispose();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/machines_approval_light.png'),
      );
    });

    testWidgets('semantics: both sheets', (tester) async {
      await pumpGolden(
        tester,
        Scaffold(
          body: HostKeyChangedSheet(
            machineName: 'raspi',
            address: 'pi@192.168.1.42:22',
            known: 'SHA256:9fWqX2vHk8mL1nRzT4cYb7JdA3eUo5sPiGt0QxVwM2z',
            offered: 'SHA256:Qm7xT1cBn5Za8RvLd2KfWy9HuJ3ePo6sGt0XiAcN4rE',
            onDontConnect: () {},
            onTrustNew: () {},
          ),
        ),
        brightness: Brightness.dark,
        dpr: 3.0,
      );
      await expectAccessible(tester);
      await pumpGolden(
        tester,
        Scaffold(
          body: ApprovalSheet(
            machineName: 'studio-pc',
            code: '482913',
            onCancel: () {},
          ),
        ),
        dpr: 3.0,
      );
      await expectAccessible(tester);
    });
  });
}
