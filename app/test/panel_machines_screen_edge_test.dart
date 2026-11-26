import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/ssh/ssh_keys.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/ssh.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/golden.dart';

class _Store implements SecretStore {
  final map = <String, String>{
    'hyperox.panel.p1.token.v1': 'tok',
    'hyperox.panel.p1.key.v1': 'key',
  };
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

const _stored = {
  'panel.machines':
      '[{"id":"p1","name":"pc.tail1234.ts.net","baseUrl":"https://pc.tail1234.ts.net:8377","fp":"AB"}]',
};

Future<_Store> _pump(WidgetTester tester) async {
  final store = _Store();
  await pumpShellGolden(
    tester,
    '/machines',
    stored: _stored,
    overrides: [
      secretStoreProvider.overrideWithValue(store),
      connectionsProvider.overrideWithValue(const <MachineConnection>[]),
      panelStateProvider('p1').overrideWith((ref) => Stream.value(const Ready())),
    ],
  );
  return store;
}

Future<void> _openRemove(WidgetTester tester) async {
  await tester.longPress(find.text('pc.tail1234.ts.net').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Remove from this phone'));
  await tester.pumpAndSettle();
  expect(find.text('Remove pc.tail1234.ts.net?'), findsOneWidget);
}

Future<List<Object?>> _savedMachines() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('panel.machines');
  return raw == null || raw.isEmpty ? const [] : jsonDecode(raw) as List<Object?>;
}

void main() {
  group('removing a paired computer', () {
    testWidgets('edge: Remove deletes the machine and both of its secrets', (tester) async {
      final store = await _pump(tester);
      await _openRemove(tester);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(await _savedMachines(), isEmpty);
      expect(store.map, isEmpty);
      expect(find.text('PAIRED BY QR'), findsNothing);
    });

    testWidgets('edge: Cancel keeps the machine and its secrets', (tester) async {
      final store = await _pump(tester);
      await _openRemove(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await _savedMachines(), hasLength(1));
      expect(store.map, hasLength(2));
      expect(find.text('PAIRED BY QR'), findsOneWidget);
    });
  });
}
