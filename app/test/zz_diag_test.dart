import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/screens/agent_screen.dart';
import 'package:xterm/xterm.dart';

import 'support/fake_connection.dart';
import 'support/golden.dart';

void main() {
  testWidgets('diag agent terminal size', (tester) async {
    final fake = FakeConnection();
    await pumpGolden(
      tester,
      AgentScreen(machineId: 'fake', terminal: 't2', connection: fake),
      settle: false,
    );
    fake.emitView('t2', utf8.encode('hello world\r\nsecond line\r\n'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final view = find.byType(TerminalView);
    final w = tester.widget<TerminalView>(view);
    expect(
      '',
      isNotEmpty,
      reason:
          'AGENT size=${tester.getSize(view)} topLeft=${tester.getTopLeft(view)} '
          'view=${w.terminal.viewWidth}x${w.terminal.viewHeight} '
          'lines=${w.terminal.buffer.lines.length}',
    );
  });
}
