import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/panel/panel_connection.dart';
import 'package:hyperox/state/connections.dart';
import 'package:material_ui/material_ui.dart';

import 'support/golden.dart';
import 'support/golden_expect.dart';

const _stored = {
  'panel.machines':
      '[{"id":"p1","name":"pc.tail1234.ts.net","baseUrl":"https://pc.tail1234.ts.net:8377","fp":"AB"}]',
};

Future<void> _pump(
  WidgetTester tester,
  Stream<ConnState> state, {
  Brightness brightness = Brightness.light,
}) => pumpShellGolden(
  tester,
  '/machines',
  brightness: brightness,
  stored: _stored,
  overrides: [
    connectionsProvider.overrideWithValue(const <MachineConnection>[]),
    panelStateProvider('p1').overrideWith((ref) => state),
  ],
);

void main() {
  group('a paired computer in Machines', () {
    testWidgets('is listed under PAIRED BY QR and shows online when ready', (tester) async {
      await _pump(tester, Stream.value(const Ready()));
      expect(find.text('PAIRED BY QR'), findsOneWidget);
      expect(find.text('pc.tail1234.ts.net'), findsOneWidget);
      expect(find.text('online'), findsOneWidget);
      expect(find.text('[qr]'), findsOneWidget);
      expect(find.text('Scan again'), findsNothing);
    });

    testWidgets('an expired or revoked session says Scan again', (tester) async {
      await _pump(tester, Stream.value(const ScanAgain()));
      expect(find.text('scan again'), findsOneWidget);
      expect(find.text('No longer paired'), findsOneWidget);
      expect(find.text('Scan again'), findsOneWidget);
    });

    testWidgets('a connection that is retrying shows offline, not scan again', (tester) async {
      await _pump(tester, Stream.value(const Failed('connection lost', retryIn: Duration(seconds: 1))));
      expect(find.text('offline'), findsOneWidget);
      expect(find.text('Scan again'), findsNothing);
    });

    testWidgets('before the first state it shows connecting', (tester) async {
      await _pump(tester, const Stream.empty());
      expect(find.text('connecting'), findsOneWidget);
    });

    for (final b in [Brightness.light, Brightness.dark]) {
      final name = b == Brightness.light ? 'light' : 'dark';
      testWidgets('golden: paired and online, $name', (tester) async {
        await _pump(tester, Stream.value(const Ready()), brightness: b);
        await expectGolden(find.byType(MaterialApp), 'machines_panel_online_$name');
      });
      testWidgets('golden: scan again, $name', (tester) async {
        await _pump(tester, Stream.value(const ScanAgain()), brightness: b);
        await expectGolden(find.byType(MaterialApp), 'machines_panel_scan_again_$name');
      });
    }
  });
}
