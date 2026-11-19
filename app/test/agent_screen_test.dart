import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/screens/agent_screen.dart';
import 'package:hyperox/state/agent_session.dart';
import 'package:hyperox/theme/theme_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/a11y.dart';
import 'support/fake_connection.dart';
import 'support/golden.dart';

const _output =
    '\$ claude --continue\r\n'
    '\x1b[32m●\x1b[0m Read \x1b[36msrc/pricing.ts\x1b[0m (128 lines)\r\n'
    '\x1b[32m●\x1b[0m Edit \x1b[36msrc/pricing.ts\x1b[0m\r\n'
    '  \x1b[31m42 -  const cta = "Start now";\x1b[0m\r\n'
    '  \x1b[32m42 +  const cta = "Start free trial";\x1b[0m\r\n'
    'Allow this edit?\r\n'
    '❯ 1. Yes   2. Always   3. No\r\n';

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens terminal [t] of [fake] and lets it attach with some output.
Future<void> _open(
  WidgetTester tester,
  FakeConnection fake, {
  String t = 't1',
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Frame frame = Frame.phone,
  double dpr = 1.0,
  bool output = true,
}) async {
  await pumpGolden(
    tester,
    AgentScreen(machineId: 'fake', terminal: t, connection: fake),
    brightness: brightness,
    textScale: textScale,
    frame: frame,
    dpr: dpr,
    settle: false,
  );
  if (output) {
    fake.emitView(t, utf8.encode(_output));
    await _frames(tester);
  }
}

/// Unmounts the screen so its timers stop before the test ends.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// A connection whose state the test drives.
class _Flaky extends FakeConnection {
  final drop = StreamController<ConnState>.broadcast(sync: true);

  @override
  Stream<ConnState> get state => drop.stream;
}

void main() {
  group('AgentController', () {
    test('output reaches the terminal, one write per frame', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fake = FakeConnection();
      final a = AgentController(fake, 't1');
      await a.start();
      expect(a.phase, AgentPhase.attaching);
      fake.emitView('t1', utf8.encode('hel'));
      fake.emitView('t1', utf8.encode('lo\r\n'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(a.phase, AgentPhase.ready);
      expect(a.size, const TermSize(80, 24));
      a.dispose();
    });

    test('a multi-byte character split across chunks is whole', () async {
      final fake = FakeConnection();
      final a = AgentController(fake, 't1');
      await a.start();
      final bytes = utf8.encode('€');
      fake.emitView('t1', bytes.sublist(0, 1));
      fake.emitView('t1', bytes.sublist(1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      a.dispose();
    });

    test('a terminal that does not exist leaves it reconnecting', () async {
      final fake = FakeConnection();
      final a = AgentController(fake, 'nope');
      await a.start();
      expect(a.phase, AgentPhase.reconnecting);
      expect(a.error, contains('no such terminal'));
      a.dispose();
    });

    test('an exited process finishes the terminal', () async {
      final fake = FakeConnection();
      fake.live = {
        't1': const Session(
          terminal: 't1',
          name: 'build',
          agent: 'claude',
          folder: '/srv/a',
          status: 'done',
          live: false,
        ),
      };
      final a = AgentController(fake, 't1');
      await a.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(a.phase, AgentPhase.finished);
      a.dispose();
    });

    test('messageTooLong counts bytes, not characters', () {
      expect(messageTooLong('a' * kMaxMessageBytes), isFalse);
      expect(messageTooLong('a' * (kMaxMessageBytes + 1)), isTrue);
      expect(messageTooLong('€' * (kMaxMessageBytes ~/ 3 + 1)), isTrue);
      expect(messageTooLong(''), isFalse);
    });
  });

  group('AgentScreen', () {
    testWidgets('attaching shows the skeleton and disables input', (
      tester,
    ) async {
      final fake = FakeConnection();
      await _open(tester, fake, output: false);
      final h = tester.ensureSemantics();
      await tester.pump();
      expect(find.text('Attaching to claude'), findsOneWidget);
      expect(find.text('replaying the last 5000 lines'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Send, unavailable: attaching')),
        findsOneWidget,
      );
      h.dispose();
      await _close(tester);
    });

    testWidgets('a working agent: header tag, no prompt card', (tester) async {
      final fake = FakeConnection();
      await _open(tester, fake);
      expect(find.text('claude'), findsWidgets);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Deny'), findsNothing);
      await _close(tester);
    });

    testWidgets('a permission prompt shows Deny and Approve; Approve sends', (
      tester,
    ) async {
      final fake = FakeConnection();
      await _open(tester, fake, t: 't2');
      expect(find.text('Approve'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await _frames(tester, 2);
      expect(fake.log, contains('keys t2 enter'));
      await tester.tap(find.text('Deny'));
      await _frames(tester, 2);
      expect(fake.log, contains('keys t2 esc'));
      await _close(tester);
    });

    testWidgets('a question never shows Approve', (tester) async {
      final fake = FakeConnection();
      await _open(tester, fake, t: 't3');
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Deny'), findsNothing);
      expect(find.textContaining('Reply in the box below'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('compose: Send is off when empty, sends a line when typed', (
      tester,
    ) async {
      final fake = FakeConnection();
      await _open(tester, fake);
      final h = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel('Send, unavailable: type a message first'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'also update the README');
      await tester.pump();
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Send'));
      await _frames(tester, 2);
      expect(fake.log, contains('send t1 also update the README'));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      h.dispose();
      await _close(tester);
    });

    testWidgets('compose: over 60 KiB shows the error and refuses', (
      tester,
    ) async {
      final fake = FakeConnection();
      await _open(tester, fake);
      await tester.enterText(find.byType(TextField), 'x' * (60 * 1024 + 1));
      await tester.pump();
      expect(find.textContaining('over 60 KiB'), findsWidgets);
      final h = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel('Send, unavailable: message is over 60 KiB'),
        findsOneWidget,
      );
      h.dispose();
      expect(fake.log.where((l) => l.startsWith('send')), isEmpty);
      await _close(tester);
    });

    testWidgets('Paste puts the clipboard into the box', (tester) async {
      final fake = FakeConnection();
      await _open(tester, fake);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, Object?>{'text': 'pasted text'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byTooltip('Paste'));
      await _frames(tester, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'pasted text',
      );
      await _close(tester);
    });

    testWidgets('Interrupt asks first; Cancel sends nothing', (tester) async {
      final fake = FakeConnection();
      await _open(tester, fake);
      await tester.tap(find.byTooltip('Interrupt claude'));
      await _frames(tester, 3);
      expect(find.text('Interrupt claude?'), findsOneWidget);
      expect(find.textContaining('Sends Ctrl+C to claude in /srv/a'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _frames(tester, 3);
      expect(fake.log, isNot(contains('interrupt t1')));
      await tester.tap(find.byTooltip('Interrupt claude'));
      await _frames(tester, 3);
      await tester.tap(find.widgetWithText(TextButton, 'Interrupt'));
      await _frames(tester, 3);
      expect(fake.log, contains('interrupt t1'));
      await _close(tester);
    });

    testWidgets('keys: Esc, then one-shot Ctrl applies to the next key only', (
      tester,
    ) async {
      final fake = FakeConnection();
      await _open(tester, fake);
      await tester.tap(find.text('Esc'));
      await _frames(tester, 2);
      await tester.tap(find.text('Ctrl'));
      await _frames(tester, 2);
      await tester.tap(find.text('Tab'));
      await _frames(tester, 2);
      await tester.tap(find.text('Tab'));
      await _frames(tester, 2);
      expect(
        fake.log.where((l) => l.startsWith('keys t1')).toList(),
        ['keys t1 esc', 'keys t1 ctrl+tab', 'keys t1 tab'],
      );
      await _close(tester);
    });

    testWidgets('keys: a locked Ctrl stays until tapped off', (tester) async {
      final fake = FakeConnection();
      await _open(tester, fake);
      final h = tester.ensureSemantics();
      await tester.tap(find.text('Ctrl'));
      await _frames(tester, 2);
      expect(
        find.bySemanticsLabel('Key Ctrl, on for next key'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ctrl'));
      await _frames(tester, 2);
      expect(find.bySemanticsLabel('Key Ctrl, locked'), findsOneWidget);
      await tester.tap(find.text('Tab'));
      await tester.tap(find.text('Tab'));
      await _frames(tester, 2);
      expect(
        fake.log.where((l) => l.startsWith('keys t1')).toList(),
        ['keys t1 ctrl+tab', 'keys t1 ctrl+tab'],
      );
      await tester.tap(find.text('Ctrl'));
      await _frames(tester, 2);
      expect(find.bySemanticsLabel('Key Ctrl, off'), findsOneWidget);
      h.dispose();
      await _close(tester);
    });

    testWidgets('Enter is pinned and sends enter', (tester) async {
      final fake = FakeConnection();
      await _open(tester, fake);
      final h = tester.ensureSemantics();
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Key Enter'));
      await _frames(tester, 2);
      expect(fake.log, contains('keys t1 enter'));
      h.dispose();
      await _close(tester);
    });

    testWidgets('a finished process shows the result card and no inputs', (
      tester,
    ) async {
      final fake = FakeConnection();
      fake.live = {
        't1': const Session(
          terminal: 't1',
          name: 'build',
          agent: 'claude',
          folder: '/srv/a',
          status: 'done',
          live: false,
        ),
      };
      await _open(tester, fake);
      await _frames(tester, 4);
      expect(find.text('claude finished'), findsOneWidget);
      expect(find.text('Close terminal'), findsOneWidget);
      expect(find.text('Back to inbox'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await _close(tester);
    });

    testWidgets('a dropped connection dims the output and comes back', (
      tester,
    ) async {
      final fake = _Flaky();
      await _open(tester, fake);
      fake.drop.add(const Failed('connection lost'));
      await _frames(tester, 2);
      expect(find.text('Reconnecting to fake'), findsOneWidget);
      final h = tester.ensureSemantics();
      await tester.pump();
      expect(
        find.bySemanticsLabel(RegExp(r'Send, unavailable: reconnecting')),
        findsOneWidget,
      );
      h.dispose();
      fake.drop.add(const Ready());
      await _frames(tester, 4);
      fake.emitView('t1', utf8.encode('back\r\n'));
      await _frames(tester, 3);
      expect(find.text('Reconnecting to fake'), findsNothing);
      await _close(tester);
    });

    testWidgets('without a started connection the screen says so', (
      tester,
    ) async {
      await pumpGolden(
        tester,
        const AgentScreen(machineId: 'gone', terminal: 't1'),
      );
      expect(find.text('This machine is not connected'), findsOneWidget);
    });

    testWidgets('zoom is remembered per machine', (tester) async {
      SharedPreferences.setMockInitialValues({zoomKey('fake'): 16.0});
      final prefs = await SharedPreferences.getInstance();
      final fake = FakeConnection();
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: AgentScreen(
              machineId: 'fake',
              terminal: 't1',
              connection: fake,
            ),
          ),
        ),
      );
      await _frames(tester, 2);
      expect(prefs.getDouble(zoomKey('fake')), 16.0);
      await _close(tester);
    });
  });

  group('AgentScreen goldens and semantics', () {
    final cases = <String, Future<void> Function(WidgetTester, FakeConnection)>{
      'permission_light': (t, f) => _open(t, f, t: 't2'),
      'permission_dark': (t, f) =>
          _open(t, f, t: 't2', brightness: Brightness.dark),
      'question_dark': (t, f) =>
          _open(t, f, t: 't3', brightness: Brightness.dark),
      'working_dark': (t, f) => _open(t, f, brightness: Brightness.dark),
      'attaching_light': (t, f) => _open(t, f, output: false),
      'text200_light': (t, f) => _open(t, f, t: 't2', textScale: 2.0),
      'tablet_dark': (t, f) => _open(
        t,
        f,
        t: 't2',
        brightness: Brightness.dark,
        frame: Frame.tablet,
      ),
    };
    for (final e in cases.entries) {
      testWidgets('golden ${e.key}', (tester) async {
        final fake = FakeConnection();
        await e.value(tester, fake);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/agent_${e.key}.png'),
        );
        await _close(tester);
      });
    }

    testWidgets('semantics: permission prompt, light', (tester) async {
      final fake = FakeConnection();
      await _open(tester, fake, t: 't2', dpr: 3.0);
      await expectAccessible(tester);
      await _close(tester);
    });

    testWidgets('semantics: question, dark, text 2.0', (tester) async {
      final fake = FakeConnection();
      await _open(
        tester,
        fake,
        t: 't3',
        brightness: Brightness.dark,
        textScale: 2.0,
        dpr: 3.0,
      );
      await expectAccessible(tester);
      await _close(tester);
    });
  });
}
