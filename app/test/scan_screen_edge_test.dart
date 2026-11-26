import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/panel/panel_connection.dart';
import 'package:hyperox/conn/ssh/ssh_keys.dart';
import 'package:hyperox/data/panel_machines_repo.dart';
import 'package:hyperox/screens/scan_screen.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/ssh.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:hyperox/theme/themes.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements SecretStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

const _fp = 'K60P1hDZnq5EPpMqJhQryh5fqZW0UYRSgn547x8xf_A';
const _link = 'https://pc.tail1234.ts.net:8377/#pair=CODE&fp=$_fp';

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
        theme: themeData(themeById(kDefaultLightTheme)),
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

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text('Pair this phone'));
  await tester.pumpAndSettle();
}

void main() {
  group('scan screen edges', () {
    testWidgets('edge: whitespace, a non-ascii host, a query, an over-long text and a bad port are refused', (tester) async {
      final cam = _Cam();
      final (c, store) = await _pump(tester, cam);
      for (final raw in [
        ' \t\n ',
        'https://bücher.example:8377/#pair=a&fp=b',
        'https://pc.ts.net/?pair=a&fp=b',
        'https://pc.ts.net/?x=1#pair=a&fp=b',
        'x' * 100000,
        'https://pc.ts.net:65536/#pair=a&fp=b',
        'https://pc.ts.net:0/#pair=a&fp=b',
        'mailto:a@b.c',
      ]) {
        await _scan(tester, cam, raw);
        expect(find.text('Not a HyperOx pairing QR'), findsOneWidget, reason: raw.length > 60 ? 'long' : raw);
        expect(find.text('Pair with this computer?'), findsNothing);
      }
      expect(c.read(panelMachinesProvider), isEmpty);
      expect(store.map, isEmpty);
    });

    testWidgets('edge: an http link with no code or key still gets the HTTPS hint', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      await _scan(tester, cam, 'http://pc.tail1234.ts.net:8377/');
      expect(find.text('Turn on HTTPS in Tailscale'), findsOneWidget);
    });

    testWidgets('edge: a missing code is named, then a missing key on the next scan', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      await _scan(tester, cam, 'https://pc.ts.net/#fp=$_fp');
      expect(find.text('This QR has no pairing code'), findsOneWidget);
      await _scan(tester, cam, 'https://pc.ts.net/#pair=a&fp=');
      expect(find.text('This QR has no computer key'), findsOneWidget);
      expect(find.text('This QR has no pairing code'), findsNothing);
      expect(find.text('Pair with this computer?'), findsNothing);
    });

    testWidgets('edge: a punycode host, a port of 65535 and a very long code ask to confirm', (tester) async {
      for (final raw in [
        'https://xn--bcher-kva.example:8377/#pair=a&fp=b',
        'https://pc.ts.net:65535/#pair=a&fp=b',
        'https://pc.ts.net/#pair=${'A' * 4000}&fp=b',
      ]) {
        final cam = _Cam();
        await _pump(tester, cam);
        await _scan(tester, cam, raw);
        expect(find.text('Pair with this computer?'), findsOneWidget, reason: raw.substring(0, 40));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('edge: the confirm shows the computer, never the one-time pairing code', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      await _scan(tester, cam, 'https://pc.tail1234.ts.net:8377/#pair=SECRETPAIRCODE42&fp=$_fp');
      expect(find.text('Pair with this computer?'), findsOneWidget);
      expect(find.text('pc.tail1234.ts.net'), findsOneWidget);
      expect(find.textContaining('SECRETPAIRCODE42'), findsNothing);
    });

    testWidgets('edge: an IPv6 QR is saved with a bracketed base url', (tester) async {
      final cam = _Cam();
      final (c, _) = await _pump(tester, cam);
      await _scan(tester, cam, 'https://[fd7a:115c:a1e0::1]:8377/#pair=CODE&fp=$_fp');
      await _confirm(tester);
      final saved = c.read(panelMachinesProvider).single;
      expect(saved.baseUrl, 'https://[fd7a:115c:a1e0::1]:8377');
      expect(Uri.parse(saved.baseUrl).host, 'fd7a:115c:a1e0::1');
    });

    testWidgets('edge: an upper-case host with :443 replaces the pairing saved without a port', (tester) async {
      final cam = _Cam();
      final (c, store) = await _pump(tester, cam, stored: {
        'panel.machines': '[{"id":"old","name":"pc","baseUrl":"https://pc.tail1234.ts.net","fp":"OLDFP"}]',
      });
      store.map['hyperox.panel.old.token.v1'] = 'oldtok';
      store.map['hyperox.panel.old.key.v1'] = 'oldkey';
      await _scan(tester, cam, 'HTTPS://PC.TAIL1234.TS.NET:443/#pair=CODE&fp=$_fp');
      await _confirm(tester);
      final all = c.read(panelMachinesProvider);
      expect(all, hasLength(1));
      expect((all.single.baseUrl, all.single.fp), ('https://pc.tail1234.ts.net', _fp));
      expect(store.map.keys.where((k) => k.contains('.old.')), isEmpty);
    });

    testWidgets('edge: a failed re-scan of a paired computer keeps the old pairing', (tester) async {
      for (final error in <Object>[
        const PanelPairException('wrong or used pairing code'),
        TimeoutException('x'),
      ]) {
        final cam = _Cam();
        final (c, store) = await _pump(
          tester,
          cam,
          pair: (l, {required label}) async => throw error,
          stored: {
            'panel.machines':
                '[{"id":"old","name":"pc","baseUrl":"https://pc.tail1234.ts.net:8377","fp":"OLDFP"}]',
          },
        );
        store.map['hyperox.panel.old.token.v1'] = 'oldtok';
        store.map['hyperox.panel.old.key.v1'] = 'oldkey';
        await _scan(tester, cam, _link);
        await _confirm(tester);
        expect(c.read(panelMachinesProvider).single.id, 'old', reason: '$error');
        expect(store.map['hyperox.panel.old.token.v1'], 'oldtok');
        expect(store.map['hyperox.panel.old.key.v1'], 'oldkey');
      }
    });

    testWidgets('edge: while pairing, further codes are ignored and nothing is asked twice', (tester) async {
      final cam = _Cam();
      final gate = Completer<PanelPairing>();
      var pairs = 0;
      final (c, _) = await _pump(tester, cam, pair: (l, {required label}) {
        pairs++;
        return gate.future;
      });
      await _scan(tester, cam, _link);
      await tester.tap(find.text('Pair this phone'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Pairing…'), findsOneWidget);
      cam.feed!('https://other.tail1234.ts.net/#pair=B&fp=$_fp');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Pair with this computer?'), findsNothing);
      gate.complete(_pairing());
      await tester.pumpAndSettle();
      expect(pairs, 1);
      expect(c.read(panelMachinesProvider).single.baseUrl, 'https://pc.tail1234.ts.net:8377');
    });

    testWidgets('edge: permission denied twice shows one message; after Try again a scan asks to confirm', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam);
      final denied = cam.denied!;
      denied();
      denied();
      await tester.pumpAndSettle();
      expect(find.text('Camera access is off'), findsOneWidget);
      expect(cam.built, 1, reason: 'no camera while the permission is off');
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(cam.built, 2);
      await _scan(tester, cam, _link);
      expect(find.text('Pair with this computer?'), findsOneWidget);
    });

    testWidgets('edge: the error banner never shows the pairing code', (tester) async {
      final cam = _Cam();
      await _pump(tester, cam, pair: (l, {required label}) async => throw StateError('socket failed'));
      await _scan(tester, cam, 'https://pc.tail1234.ts.net:8377/#pair=SECRETPAIRCODE42&fp=$_fp');
      await _confirm(tester);
      expect(find.text('Could not reach the computer'), findsOneWidget);
      expect(find.textContaining('SECRETPAIRCODE42'), findsNothing);
    });
  });
}
