import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/panel/e2e.dart';
import 'package:hyperox/conn/panel/panel_connection.dart';
import 'package:hyperox/conn/panel/panel_link.dart';
import 'package:hyperox/conn/ssh/ssh_keys.dart';
import 'package:hyperox/data/panel_machines_repo.dart';
import 'package:hyperox/screens/scan_screen.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/ssh.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:hyperox/theme/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/golden_expect.dart';

class _Store implements SecretStore {
  final map = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('disk full');
    map[key] = value;
  }
  @override
  Future<void> delete(String key) async => map.remove(key);
}

const _link = 'https://pc.tail1234.ts.net:8377/#pair=CODE&fp=K60P1hDZnq5EPpMqJhQryh5fqZW0UYRSgn547x8xf_A';

/// A camera stand-in: a dark box, and a handle to feed codes into the screen.
class _Cam {
  void Function(String)? feed;
  VoidCallback? denied;
  int built = 0;

  Widget build(BuildContext context, void Function(String) onCode, VoidCallback onDenied) {
    feed = onCode;
    denied = onDenied;
    built++;
    return Container(color: const Color(0xFF111111));
  }
}

PanelPairing _pairing() => const PanelPairing(
  secrets: PanelSecrets(token: 'tok', deviceKey: 'a2V5'),
  device: 'HyperOx phone',
);

Future<(ProviderContainer, _Store)> _pump(
  WidgetTester tester,
  _Cam cam, {
  PanelPairer? pair,
  Map<String, Object> stored = const {},
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final store = _Store();
  final c = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      secretStoreProvider.overrideWithValue(store),
      connectionsProvider.overrideWithValue(const <MachineConnection>[]),
    ],
  );
  addTearDown(c.dispose);
  final router = GoRouter(
    initialLocation: '/machines/scan',
    routes: [
      GoRoute(path: '/machines', builder: (_, _) => const Text('MACHINES')),
      GoRoute(
        path: '/machines/scan',
        builder: (_, _) => ScanScreen(camera: cam.build, pair: pair ?? (l, {required label}) async => _pairing()),
      ),
    ],
  );
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: themeData(
          themeById(brightness == Brightness.light ? kDefaultLightTheme : kDefaultDarkTheme),
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (c, store);
}

Future<void> _scan(WidgetTester tester, _Cam cam, String raw) async {
  cam.feed!(raw);
  await tester.pumpAndSettle();
}

void main() {
  group('explainScan', () {
    PanelLinkException err(String raw) {
      try {
        parsePanelLink(raw);
      } on PanelLinkException catch (e) {
        return e;
      }
      throw StateError('parsed: $raw');
    }

    test('an http link says to turn on HTTPS in Tailscale', () {
      const raw = 'http://pc.ts.net:8377/#pair=A&fp=B';
      expect(explainScan(raw, err(raw)).title, 'Turn on HTTPS in Tailscale');
      expect(explainScan(' HTTP://x/#pair=A&fp=B', err(' HTTP://x/#pair=A&fp=B')).title, 'Turn on HTTPS in Tailscale');
    });

    test('empty, garbage and other schemes are not a pairing QR', () {
      for (final raw in ['', '   ', 'hello', 'ftp://x/#pair=A&fp=B', 'WIFI:S:x;;']) {
        expect(explainScan(raw, err(raw)).title, 'Not a HyperOx pairing QR', reason: raw);
      }
    });

    test('a missing code or key is named', () {
      expect(explainScan('', err('https://x.ts.net/#fp=B')).title, contains('pairing code'));
      expect(explainScan('', err('https://x.ts.net/#pair=A')).title, contains('computer key'));
    });
  });

  group('scan screen', () {
    testWidgets('an https link with any host, ts.net or IPv6, asks to confirm', (tester) async {
      for (final raw in [
        _link,
        'https://[fd7a:115c::1]:8377/#pair=A&fp=B',
        'https://192.168.1.5/#pair=A&fp=B',
        'https://DESKTOP-1.local:8377/#pair=A&fp=B',
      ]) {
        final cam = _Cam();
        await _pump(tester, cam);
        await _scan(tester, cam, raw);
        expect(find.text('Pair with this computer?'), findsOneWidget, reason: raw);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('an http link shows Turn on HTTPS in Tailscale and nothing is asked', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      await _scan(tester, cam, 'http://pc.ts.net:8377/#pair=A&fp=B');
      expect(find.text('Turn on HTTPS in Tailscale'), findsOneWidget);
      expect(find.text('Pair with this computer?'), findsNothing);
    });

    testWidgets('an empty and a garbage QR show an error and keep scanning', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      await _scan(tester, cam, '');
      expect(find.text('Not a HyperOx pairing QR'), findsOneWidget);
      await _scan(tester, cam, 'garbage');
      expect(find.text('Not a HyperOx pairing QR'), findsOneWidget);
      await _scan(tester, cam, _link);
      expect(find.text('Pair with this computer?'), findsOneWidget);
    });

    testWidgets('a link without a fingerprint is refused', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      await _scan(tester, cam, 'https://pc.ts.net/#pair=A');
      expect(find.text('This QR has no computer key'), findsOneWidget);
    });

    testWidgets('cancel on the confirm pairs nothing and the same QR can be scanned again', (tester) async {
      final cam = _Cam();
      var pairs = 0;
      final (c, store) = await _pump(tester, cam, pair: (l, {required label}) async {
        pairs++;
        return _pairing();
      });
      await _scan(tester, cam, _link);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(pairs, 0);
      expect(c.read(panelMachinesProvider), isEmpty);
      expect(store.map, isEmpty);
      await _scan(tester, cam, _link);
      expect(find.text('Pair with this computer?'), findsOneWidget);
    });

    testWidgets('confirm pairs once, saves the computer and its secrets, and leaves', (tester) async {
      final cam = _Cam();
      final links = <PanelLink>[];
      final labels = <String>[];
      final (c, _) = await _pump(tester, cam, pair: (l, {required label}) async {
        links.add(l);
        labels.add(label);
        return _pairing();
      });
      await _scan(tester, cam, _link);
      cam.feed!(_link); // the camera sees it again while the sheet is open
      await tester.tap(find.text('Pair this phone'));
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the computer'), findsNothing);
      expect(labels, ['HyperOx phone']);
      expect(links, hasLength(1));
      expect(links.single.baseUrl, 'https://pc.tail1234.ts.net:8377');
      final saved = c.read(panelMachinesProvider).single;
      expect((saved.name, saved.baseUrl), ('pc.tail1234.ts.net', 'https://pc.tail1234.ts.net:8377'));
      expect((await c.read(panelMachinesProvider.notifier).secrets(saved.id))!.token, 'tok');
      expect(find.text('MACHINES'), findsOneWidget);
    });

    testWidgets('scanning a computer that is already paired replaces the old pairing', (tester) async {
      final cam = _Cam();
      const old = PanelMachine(
        id: 'old',
        name: 'pc',
        baseUrl: 'https://pc.tail1234.ts.net:8377',
        fp: 'OLDFP',
      );
      final (c, store) = await _pump(tester, cam, stored: {
        'panel.machines': '[{"id":"old","name":"pc","baseUrl":"https://pc.tail1234.ts.net:8377","fp":"OLDFP"}]',
      });
      store.map['hyperox.panel.old.token.v1'] = 'oldtok';
      store.map['hyperox.panel.old.key.v1'] = 'oldkey';
      expect(c.read(panelMachinesProvider).single.id, old.id);
      await _scan(tester, cam, _link);
      await tester.tap(find.text('Pair this phone'));
      await tester.pumpAndSettle();
      final all = c.read(panelMachinesProvider);
      expect(all, hasLength(1));
      expect(all.single.id, isNot('old'));
      expect(all.single.fp, 'K60P1hDZnq5EPpMqJhQryh5fqZW0UYRSgn547x8xf_A');
      expect(store.map.keys.where((k) => k.contains('.old.')), isEmpty);
    });

    testWidgets('a refused code says so and nothing is saved', (tester) async {
      final cam = _Cam();
      final (c, store) = await _pump(tester, cam, pair: (l, {required label}) async {
        throw const PanelPairException('wrong or used pairing code');
      });
      await _scan(tester, cam, _link);
      await tester.tap(find.text('Pair this phone'));
      await tester.pumpAndSettle();
      expect(find.text('The computer refused to pair'), findsOneWidget);
      expect(find.textContaining('wrong or used pairing code'), findsOneWidget);
      expect(c.read(panelMachinesProvider), isEmpty);
      expect(store.map, isEmpty);
      await _scan(tester, cam, _link);
      expect(find.text('Pair with this computer?'), findsOneWidget, reason: 'scan again after a failure');
    });

    testWidgets('a wrong computer key is a hard stop with its own message', (tester) async {
      final cam = _Cam();
      final (c, _) = await _pump(tester, cam, pair: (l, {required label}) async {
        throw const PanelFingerprintMismatch();
      });
      await _scan(tester, cam, _link);
      await tester.tap(find.text('Pair this phone'));
      await tester.pumpAndSettle();
      expect(find.text('The computer key does not match'), findsOneWidget);
      expect(c.read(panelMachinesProvider), isEmpty);
    });

    testWidgets('an unreachable computer says so', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam, pair: (l, {required label}) async => throw TimeoutException('x'));
      await _scan(tester, cam, _link);
      await tester.tap(find.text('Pair this phone'));
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the computer'), findsOneWidget);
    });

    testWidgets('permission denied shows a message; Try again opens the camera again', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      expect(cam.built, 1);
      cam.denied!();
      await tester.pumpAndSettle();
      expect(find.text('Camera access is off'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Camera access is off'), findsNothing);
      expect(cam.built, 2);
    });
  });

  group('confirm sheet warnings', () {
    testWidgets('a Tailscale host shows its port and no warning', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      await _scan(tester, cam, _link);
      expect(find.text('pc.tail1234.ts.net'), findsOneWidget);
      expect(find.text('Port 8377'), findsOneWidget);
      expect(find.textContaining('Not a Tailscale address'), findsNothing);
      expect(find.textContaining('security key changed'), findsNothing);
    });

    testWidgets('a host that is not *.ts.net warns', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      await _scan(tester, cam, 'https://my-laptop.attacker.example/#pair=A&fp=B');
      expect(
        find.text('Not a Tailscale address — pair only on a network you trust'),
        findsOneWidget,
      );
      expect(find.textContaining('Port'), findsNothing, reason: 'no explicit port');
    });

    testWidgets('a lookalike such as ts.net.evil.example still warns', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      await _scan(tester, cam, 'https://pc.ts.net.evil.example/#pair=A&fp=B');
      expect(find.textContaining('Not a Tailscale address'), findsOneWidget);
    });

    testWidgets('the same computer with another key says the key changed', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam, stored: {
        'panel.machines':
            '[{"id":"old","name":"pc","baseUrl":"https://pc.tail1234.ts.net:8377","fp":"OLDFP"}]',
      });
      await _scan(tester, cam, _link);
      expect(find.text("This computer's security key changed"), findsOneWidget);
    });

    testWidgets('the same computer with the same key does not', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam, stored: {
        'panel.machines':
            '[{"id":"old","name":"pc","baseUrl":"https://pc.tail1234.ts.net:8377","fp":"K60P1hDZnq5EPpMqJhQryh5fqZW0UYRSgn547x8xf_A"}]',
      });
      await _scan(tester, cam, _link);
      expect(find.textContaining('security key changed'), findsNothing);
    });

    testWidgets('a failed save keeps the old pairing and says so', (tester) async {
      final cam = _Cam();
      final (c, store) = await _pump(tester, cam, stored: {
        'panel.machines':
            '[{"id":"old","name":"pc","baseUrl":"https://pc.tail1234.ts.net:8377","fp":"OLDFP"}]',
      });
      store.map['hyperox.panel.old.token.v1'] = 'oldtok';
      store.map['hyperox.panel.old.key.v1'] = 'oldkey';
      store.failWrites = true;
      await _scan(tester, cam, _link);
      await tester.tap(find.text('Pair this phone'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save the pairing'), findsOneWidget);
      expect(find.text('Could not reach the computer'), findsNothing);
      expect(c.read(panelMachinesProvider).single.id, 'old');
      expect(store.map['hyperox.panel.old.token.v1'], 'oldtok');
    });
  });

  group('goldens', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      final name = b == Brightness.light ? 'light' : 'dark';

      testWidgets('scan screen, $name', (tester) async {
        final cam = _Cam();
        await _pump(tester, cam, brightness: b);
        await expectGolden(find.byType(MaterialApp), 'scan_screen_$name');
      });

      testWidgets('scan screen with the https error, $name', (tester) async {
        final cam = _Cam();
        await _pump(tester, cam, brightness: b);
        await _scan(tester, cam, 'http://pc.ts.net:8377/#pair=A&fp=B');
        await expectGolden(find.byType(MaterialApp), 'scan_screen_http_$name');
      });

      testWidgets('permission denied, $name', (tester) async {
        final cam = _Cam();
        await _pump(tester, cam, brightness: b);
        cam.denied!();
        await tester.pumpAndSettle();
        await expectGolden(find.byType(MaterialApp), 'scan_screen_denied_$name');
      });

      testWidgets('first pair confirm, $name', (tester) async {
        final cam = _Cam();
        await _pump(tester, cam, brightness: b);
        await _scan(tester, cam, _link);
        await expectGolden(find.byType(MaterialApp), 'scan_screen_confirm_$name');
      });

      testWidgets('pairing, $name', (tester) async {
        final cam = _Cam();
        final never = Completer<PanelPairing>();
        await _pump(tester, cam, brightness: b, pair: (l, {required label}) => never.future);
        await _scan(tester, cam, _link);
        await tester.tap(find.text('Pair this phone'));
        // the spinner never settles: frames by hand
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Pairing…'), findsOneWidget);
        await expectGolden(find.byType(MaterialApp), 'scan_screen_pairing_$name');
      });
    }
  });
}
