import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_directory.dart';
import 'package:hyperox/conn/panel/panel_link.dart';
import 'package:hyperox/conn/ssh/ssh_keys.dart';
import 'package:hyperox/data/panel_machines_repo.dart';
import 'package:hyperox/state/ssh.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements SecretStore {
  final map = <String, String>{};
  int failReads = 0;

  @override
  Future<String?> read(String key) async {
    if (failReads > 0) {
      failReads--;
      throw StateError('keystore');
    }
    return map[key];
  }

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

const _m = PanelMachine(id: 'p1', name: 'Desk', baseUrl: 'https://a.example:8443', fp: 'AB12');
const _s = PanelSecrets(token: 'tok', deviceKey: 'a2V5');

Future<(ProviderContainer, _Store)> _make([Map<String, Object> stored = const {}]) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final store = _Store();
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    secretStoreProvider.overrideWithValue(store),
  ]);
  addTearDown(c.dispose);
  return (c, store);
}

void main() {
  group('PanelMachinesController', () {
    test('add persists metadata and secrets separately', () async {
      final (c, store) = await _make();
      expect(await c.read(panelMachinesProvider.notifier).add(_m, _s), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('panel.machines'), isNot(contains('tok')));
      expect(store.map.values, containsAll(['tok', 'a2V5']));
      // a fresh container over the same prefs lists it
      final c2 = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        secretStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c2.dispose);
      expect(c2.read(panelMachinesProvider).single.baseUrl, _m.baseUrl);
    });

    test('same base url is refused', () async {
      final (c, _) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      expect(await n.add(_m.copyWith(name: 'Other'), _s), isFalse);
      expect(c.read(panelMachinesProvider), hasLength(1));
    });

    test('rename trims and rejects empty', () async {
      final (c, _) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      await n.rename('p1', '  Lab  ');
      expect(c.read(panelMachinesProvider).single.name, 'Lab');
      expect(() => n.rename('p1', '  '), throwsArgumentError);
    });

    test('remove deletes the secrets too', () async {
      final (c, store) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      await n.remove('p1');
      expect(c.read(panelMachinesProvider), isEmpty);
      expect(store.map, isEmpty);
    });

    test('secrets: one transient error is retried, two throw and nothing is overwritten', () async {
      final (c, store) = await _make();
      final n = c.read(panelMachinesProvider.notifier);
      await n.add(_m, _s);
      store.failReads = 1;
      expect((await n.secrets('p1'))!.token, 'tok');
      store.failReads = 2;
      await expectLater(n.secrets('p1'), throwsStateError);
      expect(store.map.values, containsAll(['tok', 'a2V5']));
      expect(await n.secrets('nope'), isNull);
    });

    test('damaged store and http entries start empty / are skipped', () async {
      final (c, _) = await _make({'panel.machines': '{not json'});
      expect(c.read(panelMachinesProvider), isEmpty);
      final (c2, _) = await _make({
        'panel.machines':
            '[{"id":"x","name":"n","baseUrl":"http://a","fp":"f"},{"id":"y","name":"n","baseUrl":"https://b","fp":"f"}]',
      });
      expect(c2.read(panelMachinesProvider).single.id, 'y');
    });

    test('directory lists panel machines', () {
      final e = MachineDirectory.merge(cloud: const [], ssh: const [], panel: const [_m]);
      expect(e.single.panel, _m);
      expect(e.single.info.name, 'Desk');
    });
  });

  group('parsePanelLink', () {
    PanelLinkError err(String s) {
      try {
        parsePanelLink(s);
      } on PanelLinkException catch (e) {
        return e.error;
      }
      fail('accepted $s');
    }

    test('valid link, trimmed, port optional', () {
      final l = parsePanelLink('  https://h.example:8443/x#pair=C0DE&fp=AB%3A12 \n');
      expect(l.baseUrl, 'https://h.example:8443');
      expect(l.code, 'C0DE');
      expect(l.fp, 'AB:12');
      expect(parsePanelLink('https://h.example#pair=a&fp=b').baseUrl, 'https://h.example');
    });

    test('refusals', () {
      expect(err('http://h.example#pair=a&fp=b'), PanelLinkError.httpsRequired);
      expect(err('h.example#pair=a&fp=b'), PanelLinkError.httpsRequired);
      expect(err('https://u:p@h.example#pair=a&fp=b'), PanelLinkError.userinfo);
      expect(err('https:///#pair=a&fp=b'), PanelLinkError.hostRequired);
      expect(err('https://h.example/?pair=a#pair=a&fp=b'), PanelLinkError.queryNotAllowed);
      expect(err('https://h.example#fp=b'), PanelLinkError.missingPair);
      expect(err('https://h.example#pair=a'), PanelLinkError.missingFp);
      expect(err('https://h.example'), PanelLinkError.missingPair);
      expect(err(''), PanelLinkError.httpsRequired);
    });
  });
}
