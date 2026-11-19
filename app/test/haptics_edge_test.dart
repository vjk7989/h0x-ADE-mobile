import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/screens/agent_screen.dart';
import 'package:hyperox/screens/todo_screen.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/inbox.dart';
import 'package:material_ui/material_ui.dart' hide Key;

import 'support/fake_connection.dart';
import 'support/golden.dart';
import 'support/golden_expect.dart';

/// Every haptic the app asks for, by type, in order.
List<String> _mock(WidgetTester t) {
  final calls = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
    if (c.method == 'HapticFeedback.vibrate') calls.add('${c.arguments}');
    return null;
  });
  addTearDown(
    () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

Future<void> _agent(WidgetTester t, FakeConnection fake, String id) async {
  await pumpGolden(
    t,
    AgentScreen(machineId: 'fake', terminal: id, connection: fake),
    settle: false,
    frames: 1,
  );
}

Future<void> _close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

const _home = '/home/me/.config/h0x-ade';
const _release = '$_home/todo/release.md';

FakeConnection _todoMachine() {
  final c = FakeConnection(id: 'studio', name: 'studio-pc');
  c.files['$_home/todo/lists.md'] = '- [Release 0.2](release.md)\n';
  c.files[_release] = '# Release 0.2\n'
      '- [ ] Update the app icon\n'
      '- [ ] Test on a small phone\n'
      '- [x] Fix the login timeout\n';
  return c;
}

List<Override> _todoOverrides(FakeConnection c) => [
  connectionsProvider.overrideWithValue(<MachineConnection>[c]),
  inboxPollProvider.overrideWithValue(null),
];

void main() {
  group('agent', () {
    testWidgets('Approve: one medium impact and nothing else', (t) async {
      final calls = _mock(t);
      final fake = FakeConnection();
      await _agent(t, fake, 't2');
      fake.emitView('t2', utf8.encode('Allow?\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      await t.pump(const Duration(milliseconds: 300));
      expect(calls, isEmpty, reason: 'output alone makes no haptic');
      await t.tap(find.text('Approve').first);
      await t.pump();
      expect(calls, ['HapticFeedbackType.mediumImpact']);
      await _close(t);
    });

    testWidgets('Deny: one light impact and nothing else', (t) async {
      final calls = _mock(t);
      final fake = FakeConnection();
      await _agent(t, fake, 't2');
      fake.emitView('t2', utf8.encode('Allow?\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Deny').first);
      await t.pump();
      expect(calls, ['HapticFeedbackType.lightImpact']);
      await _close(t);
    });

    testWidgets('Interrupt: nothing on open, nothing on Cancel, heavy on confirm', (t) async {
      final calls = _mock(t);
      final fake = FakeConnection();
      await _agent(t, fake, 't1');
      fake.emitView('t1', utf8.encode('working\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      await t.tap(find.byTooltip('Interrupt claude'));
      await t.pump(const Duration(milliseconds: 400));
      expect(calls, isEmpty, reason: 'opening the dialog');
      await t.tap(find.text('Cancel'));
      await t.pump(const Duration(milliseconds: 400));
      expect(calls, isEmpty, reason: 'Cancel is no haptic at all');
      await t.tap(find.byTooltip('Interrupt claude'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.widgetWithText(TextButton, 'Interrupt'));
      await t.pump(const Duration(milliseconds: 400));
      expect(calls, ['HapticFeedbackType.heavyImpact']);
      await _close(t);
    });

    testWidgets('dismissing the Interrupt dialog by the scrim is no haptic', (t) async {
      final calls = _mock(t);
      final fake = FakeConnection();
      await _agent(t, fake, 't1');
      fake.emitView('t1', utf8.encode('working\r\n'));
      await t.pump(const Duration(milliseconds: 1700));
      await t.tap(find.byTooltip('Interrupt claude'));
      await t.pump(const Duration(milliseconds: 400));
      await t.tapAt(const Offset(5, 5));
      await t.pump(const Duration(milliseconds: 400));
      expect(calls, isEmpty);
      await _close(t);
    });
  });

  group('to-do', () {
    Future<void> show(WidgetTester t, FakeConnection c) async {
      await pumpGolden(
        t,
        TodoScreen(onNavigate: (_) {}, undoFor: const Duration(seconds: 6)),
        overrides: _todoOverrides(c),
      );
      await t.pumpAndSettle();
    }

    testWithSemantics('a tick is one light impact', (t) async {
      final calls = _mock(t);
      final c = _todoMachine();
      await show(t, c);
      await t.tap(find.bySemanticsLabel('Mark done: Update the app icon'));
      await t.pumpAndSettle();
      expect(calls, ['HapticFeedbackType.lightImpact']);
      expect(c.files[_release], contains('- [x] Update the app icon'));
    });

    testWithSemantics('an untick is no haptic', (t) async {
      final calls = _mock(t);
      final c = _todoMachine();
      await show(t, c);
      await t.tap(find.text('Completed'));
      await t.pumpAndSettle();
      await t.tap(find.bySemanticsLabel('Mark not done: Fix the login timeout'));
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      expect(c.files[_release], contains('- [ ] Fix the login timeout'));
    });
  });
}
