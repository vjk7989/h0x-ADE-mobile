import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';

import 'support/connection_contract.dart';
import 'support/fake_connection.dart';

void main() {
  connectionContract('FakeConnection', () async => FakeConnection());

  group('models', () {
    test('Session.fromJson parses the sessions shape and ignores extras', () {
      final s = Session.fromJson({
        'address': 't7',
        'name': 'n',
        'agent': 'claude',
        'folder': 'C:\\Users\\x\\proj',
        'status': 'blocked',
        'live': true,
        'future_field': 1,
      });
      expect(s.terminal, 't7');
      expect(s.folder, 'C:\\Users\\x\\proj');
      expect(s.group, AgentGroup.needsYou);
    });

    test('Session.fromJson rejects a missing required field', () {
      expect(() => Session.fromJson({'name': 'x', 'status': 'idle', 'live': true}),
          throwsFormatException);
      expect(() => Session.fromJson({'address': 't1', 'status': 'idle'}),
          throwsFormatException);
    });

    test('a finished terminal is idle whatever its last word', () {
      const s = Session(
          terminal: 't', name: '', agent: '', folder: '', status: 'working', live: false);
      expect(s.group, AgentGroup.idle);
    });

    test('SpacesView parses the new object and the old array form', () {
      final v = SpacesView.fromJson({
        'spaces': [
          {
            'name': 'a',
            'folder': '/f',
            'tabs': [
              {'name': 't', 'panes': ['p1', 'p2']}
            ]
          }
        ],
        'agents': [
          {'slot': 1, 'name': 'c', 'command': 'claude'}
        ],
        'extra': true,
      });
      expect(v.spaces.single.tabs.single.panes, ['p1', 'p2']);
      expect(v.agents.single.slot, 1);
      final old = SpacesView.fromJson([
        {'name': 'a', 'folder': '/f'}
      ]);
      expect(old.spaces.single.tabs, isEmpty);
      expect(old.agents, isEmpty);
    });

    test('SpacesView rejects missing required fields and bad shapes', () {
      expect(() => SpacesView.fromJson({'spaces': [{'name': 'a'}]}), throwsFormatException);
      expect(() => SpacesView.fromJson('x'), throwsFormatException);
      expect(
          () => SpacesView.fromJson({
                'spaces': [],
                'agents': [{'name': 'a', 'command': 'c'}]
              }),
          throwsFormatException);
    });

    test('unsupported spaces says so', () {
      expect(const SpacesView.unsupported().supported, isFalse);
    });
  });
}
