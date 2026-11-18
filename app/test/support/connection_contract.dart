import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';

/// The suite every MachineConnection implementation passes. [make] returns a
/// connection holding the fixture described on FakeConnection (t1 working,
/// t2 blocked/permission, t3 blocked/question; read t1 = "hello t1").
void connectionContract(String name, Future<MachineConnection> Function() make) {
  group('contract: $name', () {
    late MachineConnection c;
    setUp(() async => c = await make());
    tearDown(() => c.close());

    test('sessions group by what they need', () async {
      final by = {for (final s in await c.sessions()) s.terminal: s.group};
      expect(by['t1'], AgentGroup.working);
      expect(by['t2'], AgentGroup.needsYou);
      expect(by['t3'], AgentGroup.needsYou);
    });

    test('read returns the screen text', () async {
      expect(await c.read('t1', lines: 10), contains('hello t1'));
    });

    test('send, keys and interrupt on a known terminal are done', () async {
      expect(await c.send('t1', 'go'), isA<Done>());
      expect(await c.keys('t1', [Key.enter, Key.ctrlC]), isA<Done>());
      expect(await c.interrupt('t1'), isA<Done>());
    });

    test('an unknown terminal is a failed reply, not an exception', () async {
      expect(await c.send('nope', 'x'), isA<ReplyFailed>());
    });

    test('approve and deny work only on a blocked permission', () async {
      expect(await c.approve('t2'), isA<Done>());
      expect(await c.deny('t2'), isA<Done>());
      expect(await c.approve('t3'), isA<ReplyFailed>(), reason: 'a question');
      expect(await c.approve('t1'), isA<ReplyFailed>(), reason: 'working');
    });

    test('kill and run ask first; confirm does it once', () async {
      final r = await c.kill('t1');
      expect(r, isA<NeedsConfirm>());
      final token = (r as NeedsConfirm).token;
      expect(await c.confirm(token), isA<Done>());
      expect(await c.confirm(token), isA<ReplyFailed>(), reason: 'single use');
      expect(await c.run('/srv/a', 'ls'), isA<NeedsConfirm>());
      expect(await c.confirm('bogus'), isA<ReplyFailed>());
    });

    test('state emits ready or has been ready', () async {
      // Implementations are ready when make() returns.
      expect(c.machine.online, isTrue);
    });
  });
}
