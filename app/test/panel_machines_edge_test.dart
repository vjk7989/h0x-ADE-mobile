import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_directory.dart';
import 'package:hyperox/conn/panel/panel_link.dart';
import 'package:hyperox/conn/ssh/ssh_keys.dart';
import 'package:hyperox/data/panel_machines_repo.dart';
import 'package:hyperox/data/ssh_gateway.dart';
import 'package:hyperox/screens/machines_screen.dart';
import 'package:hyperox/state/ssh.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_gateway.dart';
import 'support/golden.dart';
import 'support/machines_fixture.dart';

/// A secret store that fails on demand, per key, and counts what it is asked.
class _Store implements SecretStore {
  final map = <String, String>{};
  final failReads = <String, int>{};
  final failWrites = <String>{};
  final failDeletes = <String>{};
  int writes = 0;
  int deletes = 0;

  @override
  Future<String?> read(String key) async {
    final left = failReads[key] ?? 0;
    if (left > 0) {
      failReads[key] = left - 1;
      throw StateError('keystore');
    }
    return map[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (failWrites.contains(key)) throw StateError('keystore write');
    map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    if (failDeletes.contains(key)) throw StateError('keystore delete');
    map.remove(key);
  }
}

const _tok = 'hyperox.panel.p1.token.v1';
const _key = 'hyperox.panel.p1.key.v1';
const _m = PanelMachine(
  id: 'p1',
  name: 'Desk',
  baseUrl: 'https://laptop-s9t3td0a.tail2393be.ts.net:8377',
  fp: 'Q1tpzLkgbJanh6ADLP-gd6BvjEg5TUTEhUZJUZVfjWc',
);
const _s = PanelSecrets(token: 'tok', deviceKey: 'a2V5');

Future<(ProviderContainer, _Store, SharedPreferences)> _make([
  Map<String, Object> stored = const {},
]) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final store = _Store();
  final c = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      secretStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(c.dispose);
  return (c, store, prefs);
}

PanelLinkError? _err(String s) {
  try {
    parsePanelLink(s);
  } on PanelLinkException catch (e) {
    return e.error;
  }
  return null;
}

void main() {
  group('parsePanelLink edge cases', () {
    test('the real desktop qr link parses to host and port only', () {
      final l = parsePanelLink(
        'https://laptop-s9t3td0a.tail2393be.ts.net:8377/'
        '#pair=HC92MZDP&fp=Q1tpzLkgbJanh6ADLP-gd6BvjEg5TUTEhUZJUZVfjWc',
      );
      expect(l.baseUrl, 'https://laptop-s9t3td0a.tail2393be.ts.net:8377');
      expect(l.code, 'HC92MZDP');
      expect(l.fp, 'Q1tpzLkgbJanh6ADLP-gd6BvjEg5TUTEhUZJUZVfjWc');
    });

    test('uppercase scheme and host normalize to lowercase', () {
      final l = parsePanelLink('HTTPS://LAPTOP.Tail2393be.TS.NET:8377/#pair=A&fp=B');
      expect(l.baseUrl, 'https://laptop.tail2393be.ts.net:8377');
      // the secrets keep their case
      expect(l.code, 'A');
      expect(l.fp, 'B');
    });

    test('explicit port 443 and no port give the same base url', () {
      final explicit = parsePanelLink('https://h.example:443/#pair=a&fp=b');
      final implicit = parsePanelLink('https://h.example/#pair=a&fp=b');
      expect(explicit.baseUrl, implicit.baseUrl);
      expect(implicit.baseUrl, 'https://h.example');
    });

    test('trailing slash, path and empty fragment keys are dropped from the base url', () {
      expect(parsePanelLink('https://h.example:8377/#pair=a&fp=b').baseUrl, 'https://h.example:8377');
      expect(parsePanelLink('https://h.example:8377/a/b/#pair=a&fp=b').baseUrl, 'https://h.example:8377');
      expect(parsePanelLink('https://h.example:8377#pair=a&fp=b').baseUrl, 'https://h.example:8377');
    });

    test('ipv6 literal host keeps its brackets in the base url', () {
      final l = parsePanelLink('https://[fd7a:115c:a1e0::1]:8377/#pair=a&fp=b');
      expect(l.baseUrl, 'https://[fd7a:115c:a1e0::1]:8377');
      expect(Uri.parse(l.baseUrl).host, 'fd7a:115c:a1e0::1');
      expect(Uri.parse(l.baseUrl).port, 8377);
    });

    test('tailscale 100.x address is accepted as host', () {
      final l = parsePanelLink('https://100.101.102.103:8377/#pair=a&fp=b');
      expect(l.baseUrl, 'https://100.101.102.103:8377');
    });

    test('fragment order, extra params and percent-encoding', () {
      final swapped = parsePanelLink('https://h.example/#fp=F&pair=P');
      expect((swapped.code, swapped.fp), ('P', 'F'));
      final extra = parsePanelLink('https://h.example/#v=2&pair=P&x=&fp=F&y');
      expect((extra.code, extra.fp), ('P', 'F'));
      final enc = parsePanelLink('https://h.example/#pair=A%2DB&fp=Q1%5Ftp');
      expect((enc.code, enc.fp), ('A-B', 'Q1_tp'));
    });

    test('duplicated pair or fp: the last value wins (documents current behaviour)', () {
      final l = parsePanelLink('https://h.example/#pair=a&fp=b&pair=c&fp=d');
      expect((l.code, l.fp), ('c', 'd'));
    });

    test('empty or missing secrets are refused', () {
      expect(_err('https://h.example/#pair=&fp=b'), PanelLinkError.missingPair);
      expect(_err('https://h.example/#pair=a&fp='), PanelLinkError.missingFp);
      expect(_err('https://h.example/#pair&fp'), PanelLinkError.missingPair);
      expect(_err('https://h.example/#'), PanelLinkError.missingPair);
      expect(_err('https://h.example/#&&&'), PanelLinkError.missingPair);
      expect(_err('https://h.example/#PAIR=a&FP=b'), PanelLinkError.missingPair);
      // '#' missing: the params sit in the path and do not count
      expect(_err('https://h.example/pair=a&fp=b'), PanelLinkError.missingPair);
    });

    test('non-https schemes are refused', () {
      for (final s in [
        'http://h.example/#pair=a&fp=b',
        'ws://h.example/#pair=a&fp=b',
        'wss://h.example/#pair=a&fp=b',
        'ftp://h.example/#pair=a&fp=b',
        'javascript:alert(1)//#pair=a&fp=b',
        'JavaScript:alert(1)#pair=a&fp=b',
        '//h.example/#pair=a&fp=b',
        'h.example:8377/#pair=a&fp=b',
        '   ',
      ]) {
        expect(_err(s), PanelLinkError.httpsRequired, reason: s);
      }
    });

    test('host, userinfo and query refusals', () {
      expect(_err('https:h.example#pair=a&fp=b'), PanelLinkError.hostRequired);
      expect(_err('https://:8377/#pair=a&fp=b'), PanelLinkError.hostRequired);
      expect(_err('https://u@h.example/#pair=a&fp=b'), PanelLinkError.userinfo);
      expect(_err('https://h.example/?#pair=a&fp=b'), PanelLinkError.queryNotAllowed);
      expect(_err('https://h.example/?x=1#pair=a&fp=b'), PanelLinkError.queryNotAllowed);
    });

    test('very long input never throws anything but PanelLinkException', () {
      final longCode = 'A' * 10000;
      final l = parsePanelLink('https://h.example/#pair=$longCode&fp=b');
      expect(l.code, hasLength(10000));
      expect(l.baseUrl, 'https://h.example');
      expect(_err('x' * 10000), PanelLinkError.httpsRequired);
      expect(_err('https://h.example/#${'&' * 10000}'), PanelLinkError.missingPair);
    });

    test('a host with a newline, a space or non-ascii letters is refused', () {
      // A percent-encoded host (b%C3%BCcher.example) cannot be resolved, so the
      // link must be refused rather than stored as a machine.
      for (final s in [
        'https://h.ex\nample:8377/#pair=a&fp=b',
        'https://h ex.example:8377/#pair=a&fp=b',
        'https://bücher.example:8377/#pair=a&fp=b',
      ]) {
        expect(_err(s), isNotNull, reason: s.replaceAll('\n', r'\n'));
      }
    });
  });

  group('PanelMachinesController edge cases', () {
    test('a secret write failure during add stores no metadata', () async {
      final (c, store, prefs) = await _make();
      store.failWrites.add(_key);
      final n = c.read(panelMachinesProvider.notifier);
      await expectLater(n.add(_m, _s), throwsStateError);
      expect(c.read(panelMachinesProvider), isEmpty);
      expect(prefs.getString('panel.machines'), isNull);
      // the pairing can be retried once the store works again
      store.failWrites.clear();
      expect(await n.add(_m, _s), isTrue);
      expect(store.map, {_tok: 'tok', _key: 'a2V5'});
    });

    test('explicit and implicit port 443 links are the same machine', () async {
      final (c, _, _) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      PanelMachine from(String link, String id) {
        final l = parsePanelLink(link);
        return PanelMachine(id: id, name: id, baseUrl: l.baseUrl, fp: l.fp);
      }

      expect(await n.add(from('https://H.example:443/#pair=a&fp=b', 'p1'), _s), isTrue);
      expect(await n.add(from('https://h.example/#pair=c&fp=b', 'p2'), _s), isFalse);
      expect(c.read(panelMachinesProvider), hasLength(1));
    });

    test('concurrent add of the same base url keeps one machine', () async {
      final (c, store, _) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      final results = await Future.wait([
        n.add(_m, _s),
        n.add(
          PanelMachine(id: 'p2', name: 'Twin', baseUrl: _m.baseUrl, fp: _m.fp),
          const PanelSecrets(token: 'tok2', deviceKey: 'k2'),
        ),
      ]);
      expect(results.where((r) => r), hasLength(1));
      expect(c.read(panelMachinesProvider), hasLength(1));
      expect(store.map.keys.where((k) => k.contains('.p2.')), isEmpty);
    });

    test('an id collision never overwrites the first machine secrets', () async {
      final (c, store, _) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      await n.add(
        const PanelMachine(id: 'p1', name: 'Other', baseUrl: 'https://other.example', fp: 'X'),
        const PanelSecrets(token: 'tok2', deviceKey: 'k2'),
      );
      expect(store.map[_tok], 'tok');
      expect(store.map[_key], 'a2V5');
      final ids = c.read(panelMachinesProvider).map((m) => m.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('remove when a secret delete fails: the machine is gone and the error surfaces', () async {
      final (c, store, prefs) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      store.failDeletes.add(_tok);
      await expectLater(n.remove('p1'), throwsStateError);
      expect(c.read(panelMachinesProvider), isEmpty);
      expect(jsonDecode(prefs.getString('panel.machines')!), isEmpty);
    });

    test('remove of an unknown id deletes nothing else', () async {
      final (c, store, _) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      await n.remove('nope');
      expect(c.read(panelMachinesProvider).single.id, 'p1');
      expect(store.map, {_tok: 'tok', _key: 'a2V5'});
    });

    test('rename boundaries: 64 characters save, 65 and blank throw, nothing changes on error', () async {
      final (c, store, prefs) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      final writes = store.writes;
      await n.rename('p1', '  ${'a' * 64}  ');
      expect(c.read(panelMachinesProvider).single.name, 'a' * 64);
      expect(() => n.rename('p1', 'b' * 65), throwsArgumentError);
      expect(() => n.rename('p1', ''), throwsArgumentError);
      expect(() => n.rename('p1', '\n\t '), throwsArgumentError);
      expect(c.read(panelMachinesProvider).single.name, 'a' * 64);
      expect(prefs.getString('panel.machines'), contains('a' * 64));
      expect(store.writes, writes); // rename never touches the secrets
    });

    test('rename survives a fresh container and unknown id is a no-op', () async {
      final (c, store, prefs) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      await n.rename('p1', 'Lab');
      await n.rename('nope', 'Ghost');
      final c2 = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          secretStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(c2.dispose);
      final list = c2.read(panelMachinesProvider);
      expect(list.single.name, 'Lab');
      expect(list.single.baseUrl, _m.baseUrl);
      expect(list.single.fp, _m.fp);
    });

    test('secrets: a failing device key read is retried, then throws, never writes', () async {
      final (c, store, _) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      final writes = store.writes;
      store.failReads[_key] = 1;
      expect((await n.secrets('p1'))!.deviceKey, 'a2V5');
      store.failReads[_key] = 2;
      await expectLater(n.secrets('p1'), throwsStateError);
      expect(store.writes, writes);
      expect(store.deletes, 0);
      expect(store.map, {_tok: 'tok', _key: 'a2V5'});
    });

    test('secrets: a token without a device key is null, not half a secret', () async {
      final (c, store, _) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      store.map.remove(_key);
      expect(await n.secrets('p1'), isNull);
      store.map[_key] = 'a2V5';
      store.map.remove(_tok);
      expect(await n.secrets('p1'), isNull);
    });

    test('prefs: wrong shapes, missing fields and non-https entries are skipped', () async {
      final good = {'id': 'g', 'name': 'Good', 'baseUrl': 'https://g.example:8377', 'fp': 'F', 'label': 'L'};
      final (c, _, _) = await _make({
        'panel.machines': jsonEncode([
          null,
          42,
          'x',
          [1, 2],
          {'id': 'a', 'name': 'n', 'fp': 'f'},
          {'id': 'b', 'name': 'n', 'baseUrl': 'HTTP://b', 'fp': 'f'},
          {'id': 'c', 'name': 'n', 'baseUrl': ' https://c', 'fp': 'f'},
          {'id': 'd', 'name': 'n', 'baseUrl': 'wss://d', 'fp': 'f'},
          {'id': 'e', 'name': 1, 'baseUrl': 'https://e', 'fp': 'f'},
          {'id': 'f', 'name': 'n', 'baseUrl': 'https://f', 'fp': null},
          good,
        ]),
      });
      final list = c.read(panelMachinesProvider);
      expect(list.single.id, 'g');
      expect(list.single.label, 'L');
    });

    test('prefs: empty string, object and null json start empty', () async {
      for (final raw in ['', '{}', 'null', '"x"', '[']) {
        final (c, _, _) = await _make({'panel.machines': raw});
        expect(c.read(panelMachinesProvider), isEmpty, reason: raw);
      }
    });

    test('secrets are never written into prefs, label omitted when empty', () async {
      final (c, _, prefs) = await _make();
      await c.read(panelMachinesProvider.notifier).add(_m, _s);
      final raw = prefs.getString('panel.machines')!;
      expect(raw, isNot(contains('a2V5')));
      expect(raw, isNot(contains('"tok"')));
      expect((jsonDecode(raw) as List<Object?>).single, isNot(contains('label')));
    });
  });

  group('MachineDirectory with panel machines', () {
    test('order is cloud, panel, ssh and the address is the base url', () {
      const second = PanelMachine(id: 'p2', name: 'Lab', baseUrl: 'https://[fd7a:115c:a1e0::1]:8377', fp: 'F');
      final e = MachineDirectory.merge(cloud: const [], ssh: [devbox], panel: const [_m, second]);
      expect(e.map((x) => x.info.id), ['p1', 'p2', 'm1']);
      expect(e[0].address, _m.baseUrl);
      expect(e[1].address, 'https://[fd7a:115c:a1e0::1]:8377');
      expect(e[0].ssh, isNull);
      expect(e[2].panel, isNull);
      expect(e[0].info.online, isFalse);
    });

    test('empty panel list adds nothing', () {
      expect(MachineDirectory.merge(cloud: const [], ssh: const [], panel: const []), isEmpty);
    });
  });

  group('MachinesScreen with panel machines', () {
    Future<void> pump(WidgetTester tester, Map<String, Object> stored) => pumpGolden(
      tester,
      const Scaffold(body: MachinesScreen()),
      stored: stored,
      overrides: <Override>[
        sshGatewayProvider.overrideWithValue(FakeGateway(fallback: FakeBehavior())),
      ],
    );

    testWidgets('a paired panel machine alone is listed, not the empty state', (tester) async {
      await pump(tester, {
        'panel.machines': jsonEncode([_m.toJson()]),
      });
      expect(find.text('Desk'), findsOneWidget);
      expect(find.text('No machines yet'), findsNothing);
      expect(find.textContaining('1 machine'), findsOneWidget);
    });

    testWidgets('panel and ssh machines are listed together', (tester) async {
      await pump(tester, {
        ...storedMachines([devbox]),
        'panel.machines': jsonEncode([_m.toJson()]),
      });
      expect(find.text('Desk'), findsOneWidget);
      expect(find.text('devbox'), findsOneWidget);
      expect(find.textContaining('2 machines'), findsOneWidget);
    });
  });
}
