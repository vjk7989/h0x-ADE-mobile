import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/screens/inbox_screen.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/inbox.dart';
import 'package:hyperox/widgets/app_shell.dart';
import 'package:hyperox/widgets/hx_bits.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/a11y.dart';
import 'support/fake_connection.dart';
import 'support/golden.dart';
import 'support/golden_expect.dart';

Session s(String t, String agent, String folder, String status,
        {String? kind, String msg = '', bool live = true}) =>
    Session(
      terminal: t,
      name: t,
      agent: agent,
      folder: folder,
      status: status,
      live: live,
      blockedKind: kind,
      message: msg,
    );

FakeConnection studio() => FakeConnection(id: 'studio', name: 'studio-pc', sessions: {
      'a': s('a', 'claude', '/home/me/acme-web', 'blocked',
          kind: 'permission', msg: 'Allow edit to README.md?'),
      'b': s('b', 'opencode', '/home/me/api-server', 'working', msg: 'Running tests (34/120)…'),
      'c': s('c', 'codex', '/home/me/acme-web', 'done', msg: 'Done: 3 files changed'),
    });

FakeConnection devbox() => FakeConnection(id: 'devbox', name: 'devbox', sessions: {
      'd': s('d', 'codex', '/home/me/infra', 'blocked',
          kind: 'question', msg: 'Which region: eu-west-1 or us-east-1?'),
      'e': s('e', 'claude', '/home/me/mobile-app', 'working', msg: 'Editing lib/router.dart'),
      'f': s('f', 'gemini', '/home/me/docs', 'idle', msg: 'Waiting for input'),
    });

Future<InboxController> started(List<FakeConnection> conns,
    {SharedPreferences? prefs}) async {
  final c = InboxController(conns, prefs: prefs, pollEvery: null)..start();
  addTearDown(c.dispose);
  await pump();
  return c;
}

Future<void> pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

List<Override> overrides(List<FakeConnection> conns) => [
      connectionsProvider.overrideWithValue(conns),
      inboxPollProvider.overrideWithValue(null),
    ];

void main() {
  group('InboxController', () {
    test('loads every ready machine and groups by need', () async {
      final c = await started([studio(), devbox()]);
      final st = c.value.value;
      expect(st.needsYou, 2);
      expect(st.group(AgentGroup.needsYou, '').map((i) => i.session.agent), ['claude', 'codex']);
      expect(st.group(AgentGroup.working, '').length, 2);
      expect(st.group(AgentGroup.done, '').single.session.agent, 'codex');
      expect(st.group(AgentGroup.idle, '').single.session.agent, 'gemini');
      expect(st.loading, isFalse);
    });

    test('a machine that is not ready is loading, then offline when it fails', () async {
      final a = studio()..setState(const Connecting());
      final c = await started([a]);
      expect(c.value.value.loading, isTrue);
      a.setState(const Failed('timed out'));
      await pump();
      expect(c.value.value.allOffline, isTrue);
      expect(c.value.value.machines.single.sessions, isEmpty);
    });

    test('the last known sessions stay when a machine drops', () async {
      final a = studio();
      final c = await started([a]);
      a.setState(const Failed('connection lost'));
      await pump();
      final st = c.value.value;
      expect(st.machines.single.offline, isTrue);
      expect(st.items('').every((i) => i.offline), isTrue);
      expect(st.items('').length, 3);
    });

    test('a machine that comes back is read again', () async {
      final a = studio();
      final c = await started([a]);
      a.setState(const Failed('lost'));
      a.live = {...a.live}..remove('b');
      a.setState(const Ready());
      await pump();
      expect(c.value.value.items('').length, 2);
    });

    test('a failing sessions call is an error on that machine only', () async {
      final bad = _Throwing();
      final c = await started([studio(), bad]);
      expect(c.value.value.machines[1].error, isNotNull);
      expect(c.value.value.machines[0].sessions.length, 3);
      expect(c.value.value.items('').length, 3);
    });

    test('a notice makes the machine re-read', () async {
      final a = studio();
      final c = await started([a]);
      a.live = {
        ...a.live,
        'z': s('z', 'claude', '/x', 'blocked', kind: 'permission', msg: 'new'),
      };
      a.emitNotice(const Notice(
          terminal: 'z', agent: 'claude', folder: '/x', kind: 'needs_you', excerpt: ''));
      await pump();
      expect(c.value.value.needsYou, 2);
    });

    test('search matches agent, folder, machine and message, case-insensitively', () async {
      final c = await started([studio(), devbox()]);
      final st = c.value.value;
      expect(st.items('CLAUDE').length, 2);
      expect(st.items('infra').single.session.agent, 'codex');
      expect(st.items('devbox').length, 3);
      expect(st.items('readme').single.session.terminal, 'a');
      expect(st.items('nothing like this'), isEmpty);
      expect(st.items('   ').length, 6);
    });

    test('unread: needs-you and done until opened; a new status is unread again', () async {
      final a = studio();
      final c = await started([a]);
      var items = c.value.value.items('');
      expect(items.where((i) => i.unread).map((i) => i.session.terminal), ['a', 'c']);
      c.markRead(items.firstWhere((i) => i.session.terminal == 'a'));
      expect(c.value.value.items('').where((i) => i.unread).length, 1);
      a.live = {
        ...a.live,
        'a': s('a', 'claude', '/home/me/acme-web', 'done', msg: 'finished'),
      };
      await c.refresh();
      items = c.value.value.items('');
      expect(items.firstWhere((i) => i.session.terminal == 'a').unread, isTrue);
      c.markAllRead();
      expect(c.value.value.items('').any((i) => i.unread), isFalse);
    });

    test('pinned rows sort first in their group and persist', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final a = FakeConnection(id: 'm', name: 'm', sessions: {
        'x': s('x', 'aaa', '/a', 'working'),
        'y': s('y', 'zzz', '/z', 'working'),
      });
      final c = await started([a], prefs: prefs);
      expect(c.value.value.group(AgentGroup.working, '').first.session.terminal, 'x');
      await c.togglePin('m/y');
      expect(c.value.value.group(AgentGroup.working, '').first.session.terminal, 'y');
      expect(prefs.getStringList('inbox.pinned'), ['m/y']);
      final again = InboxController([a], prefs: prefs, pollEvery: null);
      addTearDown(again.dispose);
      expect(again.value.value.pinned, {'m/y'});
      await c.togglePin('m/y');
      expect(c.value.value.pinned, isEmpty);
    });

    test('no machines: nothing, not loading', () async {
      final c = await started([]);
      expect(c.value.value.machines, isEmpty);
      expect(c.value.value.loading, isFalse);
      expect(c.value.value.needsYou, 0);
    });
  });

  group('helpers', () {
    test('shortFolder', () {
      expect(shortFolder('/home/me/acme-web'), '~/acme-web');
      expect(shortFolder('/Users/me'), '~');
      expect(shortFolder(r'C:\Users\x\proj'), '~/proj');
      expect(shortFolder('/srv/app'), '/srv/app');
    });

    test('initials', () {
      expect(initials('claude'), 'cl');
      expect(initials('x'), 'x');
      expect(initials(''), '··');
    });
  });

  group('InboxScreen', () {
    Future<void> show(WidgetTester t, List<FakeConnection> conns,
        {Brightness b = Brightness.light, double scale = 1, Frame f = Frame.phone,
        void Function(InboxItem)? onOpen}) async {
      await pumpGolden(
        t,
        InboxScreen(onOpen: onOpen, onNavigate: (_) {}),
        frame: f,
        brightness: b,
        textScale: scale,
        overrides: overrides(conns),
      );
      await t.pumpAndSettle();
    }

    testWidgets('groups, rows, tags and the needs-you badge', (t) async {
      final sem = t.ensureSemantics();
      addTearDown(sem.dispose);
      await show(t, [studio(), devbox()]);
      expect(find.text('NEEDS YOU'), findsOneWidget);
      expect(find.text('WORKING'), findsOneWidget);
      expect(find.text('2 need you · 2 machines'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^claude in ~/acme-web on studio-pc, needs you: Allow edit to README.md\?')),
          findsOneWidget);
      expect(find.bySemanticsLabel('Inbox, 2 needs you'), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget, reason: 'only the permission has it');
      expect(find.text('Deny'), findsOneWidget);
    });

    testWidgets('Approve and Deny answer the agent', (t) async {
      final a = studio();
      await show(t, [a]);
      await t.tap(find.text('Approve'));
      await t.pumpAndSettle();
      expect(a.log, contains('keys a enter'));
      await t.tap(find.text('Deny'));
      await t.pumpAndSettle();
      expect(a.log, contains('keys a esc'));
    });

    testWidgets('a question row has no Approve', (t) async {
      await show(t, [devbox()]);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('[question]'), findsOneWidget);
    });

    testWidgets('tapping a row opens it and marks it read', (t) async {
      InboxItem? opened;
      await show(t, [studio()], onOpen: (i) => opened = i);
      await t.tap(find.textContaining('Running tests'));
      expect(opened?.session.terminal, 'b');
    });

    testWidgets('search narrows the groups; clear restores them', (t) async {
      await show(t, [studio(), devbox()]);
      await t.enterText(find.byType(TextField), 'infra');
      await t.pumpAndSettle();
      expect(find.textContaining('Which region'), findsOneWidget);
      expect(find.textContaining('Running tests'), findsNothing);
      await t.tap(find.byTooltip('Clear search'));
      await t.pumpAndSettle();
      expect(find.textContaining('Running tests'), findsOneWidget);
    });

    testWidgets('no match says so', (t) async {
      await show(t, [studio()]);
      await t.enterText(find.byType(TextField), 'zzz');
      await t.pumpAndSettle();
      expect(find.text('No agent matches "zzz".'), findsOneWidget);
    });

    testWidgets('no machines: empty state with Add machine', (t) async {
      var went = false;
      await pumpGolden(t, InboxScreen(onNavigate: (d) => went = d == NavDest.machines),
          overrides: overrides([]));
      expect(find.text('No agents yet'), findsOneWidget);
      await t.tap(find.text('Add machine'));
      expect(went, isTrue);
    });

    testWidgets('all offline: banner, last known rows marked offline', (t) async {
      final sem = t.ensureSemantics();
      addTearDown(sem.dispose);
      final a = studio();
      await show(t, [a]);
      a.setState(const Failed('lost'));
      await t.pumpAndSettle();
      expect(find.text('All machines are offline'), findsOneWidget);
      expect(find.text('all machines offline'), findsOneWidget);
      expect(find.text('Approve'), findsNothing, reason: 'cannot answer an offline machine');
      expect(find.bySemanticsLabel(RegExp(r'on studio-pc, offline: Allow edit')), findsOneWidget);
    });

    testWidgets('one machine failed: a banner with Retry, the others stay', (t) async {
      final bad = devbox()..setState(const Failed('ssh: connect to host devbox port 22: timed out'));
      await show(t, [studio(), bad]);
      expect(find.text("devbox didn't answer"), findsOneWidget);
      expect(find.text('Retry devbox'), findsOneWidget);
      expect(find.textContaining('Running tests'), findsOneWidget);
    });

    testWidgets('SSH-only build: no approval banner', (t) async {
      final a = studio()..setState(const NeedsApproval('482913'));
      await show(t, [a]);
      expect(find.textContaining('Approve on'), findsNothing);
    });

    testWidgets('loading shows skeleton rows', (t) async {
      final sem = t.ensureSemantics();
      addTearDown(sem.dispose);
      final a = studio()..setState(const Connecting());
      await pumpGolden(t, InboxScreen(onNavigate: (_) {}), overrides: overrides([a]));
      expect(find.bySemanticsLabel('Loading agents'), findsWidgets);
      expect(find.text('syncing…'), findsOneWidget);
    });

    testWidgets('golden: phone light and dark, accessible', (t) async {
      await show(t, [studio(), devbox()]);
      await expectGolden(find.byType(MaterialApp), 'inbox_phone_light');
      await expectAccessible(t);
      await show(t, [studio(), devbox()], b: Brightness.dark);
      await expectGolden(find.byType(MaterialApp), 'inbox_phone_dark');
      await expectAccessible(t);
    });

    testWidgets('golden: text 200 percent stacks Approve and Deny, accessible', (t) async {
      await show(t, [studio()], scale: 2);
      expect(find.text('Approve'), findsOneWidget);
      await expectGolden(find.byType(MaterialApp), 'inbox_phone_light_200');
      await expectAccessible(t);
    });

    testWidgets('golden: tablet shows the rail and a list beside a pane', (t) async {
      await show(t, [studio(), devbox()], f: Frame.tablet);
      expect(find.text('Select an agent'), findsOneWidget);
      await expectGolden(find.byType(MaterialApp), 'inbox_tablet_light');
      await expectAccessible(t);
    });
  });
}

class _Throwing extends FakeConnection {
  _Throwing() : super(id: 'bad', name: 'bad');

  @override
  Future<List<Session>> sessions() async => throw StateError('boom');
}
