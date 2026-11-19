import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/screens/spaces_screen.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/inbox.dart';
import 'package:hyperox/state/spaces.dart';
import 'package:material_ui/material_ui.dart';

import 'support/a11y.dart';
import 'support/fake_connection.dart';
import 'support/golden.dart';
import 'support/golden_expect.dart';

Session pane(String name, String agent, String status, {String? kind, bool live = true}) => Session(
      terminal: 't-$name',
      name: name,
      agent: agent,
      folder: '/home/me',
      status: status,
      live: live,
      blockedKind: kind,
    );

const acme = Space(name: 'acme-web', folder: '/home/me/acme-web', tabs: [
  SpaceTab(name: 'agent', panes: ['claude', 'shell']),
  SpaceTab(name: 'tests', panes: ['tests']),
]);
const api = Space(name: 'api-server', folder: '/home/me/api-server', tabs: [
  SpaceTab(name: 'dev', panes: ['codex', 'old']),
]);
const scratch = Space(name: 'scratch', folder: '/home/me/scratch');

FakeConnection studio({SpacesView? view}) {
  final c = FakeConnection(id: 'studio', name: 'studio-pc', sessions: {
    't-claude': pane('claude', 'claude', 'blocked', kind: 'permission'),
    't-shell': pane('shell', 'pwsh', 'idle'),
    't-tests': pane('tests', 'npm', 'working'),
    't-codex': pane('codex', 'codex', 'working'),
    't-old': pane('old', 'tail', 'idle', live: false),
  });
  c.spacesView = view ??
      const SpacesView(
        spaces: [acme, api, scratch],
        agents: [
          AgentSlot(slot: 1, name: 'Claude Code', command: 'claude'),
          AgentSlot(slot: 2, name: 'Codex', command: 'codex'),
        ],
      );
  return c;
}

List<Override> overrides(List<FakeConnection> conns) => [
      connectionsProvider.overrideWithValue(<MachineConnection>[...conns]),
      inboxPollProvider.overrideWithValue(null),
    ];

void main() {
  Future<void> show(WidgetTester t, List<FakeConnection> conns,
      {Brightness b = Brightness.light,
      double scale = 1,
      Frame f = Frame.phone,
      void Function(MachineInfo, String)? onOpen}) async {
    await pumpGolden(
      t,
      SpacesScreen(onOpenPane: onOpen, onNavigate: (_) {}),
      frame: f,
      brightness: b,
      textScale: scale,
      overrides: overrides(conns),
    );
    await t.pumpAndSettle();
  }

  testWidgets('shows spaces, tabs and panes with their state', (t) async {
    await show(t, [studio()]);
    expect(find.text('acme-web'), findsOneWidget);
    expect(find.text('~/acme-web · 2 tabs'), findsOneWidget);
    expect(find.text('studio-pc · 3 spaces'), findsOneWidget);
    expect(find.text('agent'), findsOneWidget);
    expect(find.text('claude'), findsWidgets);
    expect(find.text('[needs you]'), findsOneWidget);
    expect(find.text('[exited]'), findsOneWidget, reason: 'a pane whose terminal finished');
    expect(find.text('No tabs: start an agent to open one'), findsOneWidget);
  });

  testWidgets('a pane opens its terminal, an exited one too (read-only scrollback)', (t) async {
    String? opened;
    await show(t, [studio()], onOpen: (m, term) => opened = '${m.id}/$term');
    await t.tap(find.text('shell'));
    expect(opened, 'studio/t-shell');
    opened = null;
    await t.ensureVisible(find.text('old'));
    await t.tap(find.text('old'));
    expect(opened, 'studio/t-old');
  });

  testWidgets('Start agent: slots, confirm dialog, then it runs once', (t) async {
    final c = studio();
    await show(t, [c]);
    await t.tap(find.text('Start agent').first);
    await t.pumpAndSettle();
    expect(find.text('Start an agent'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    await t.tap(find.text('Claude Code'));
    await t.pumpAndSettle();
    expect(find.text('Start Claude Code?'), findsOneWidget);
    expect(find.textContaining('Runs claude in ~/acme-web on studio-pc'), findsOneWidget);
    await t.tap(find.text('Start'));
    await t.pumpAndSettle();
    expect(c.log.where((e) => e.startsWith('run ')), ['run /home/me/acme-web claude']);
    expect(find.text('Started Claude Code'), findsOneWidget);
  });

  testWidgets('Cancel in the confirm dialog runs nothing', (t) async {
    final c = studio();
    await show(t, [c]);
    await t.tap(find.text('Start agent').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Codex'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.log.where((e) => e.startsWith('run ')), isEmpty);
  });

  testWidgets('no slots: the sheet says where to set them', (t) async {
    final c = studio(view: const SpacesView(spaces: [acme]));
    await show(t, [c]);
    await t.tap(find.text('Start agent').first);
    await t.pumpAndSettle();
    expect(find.textContaining('no agent slots'), findsOneWidget);
  });

  testWidgets('no spaces: say so and still offer Start agent', (t) async {
    await show(t, [studio(view: const SpacesView())]);
    expect(find.text('No spaces on studio-pc'), findsOneWidget);
    expect(find.text('no spaces'), findsOneWidget);
    expect(find.text('Start agent'), findsOneWidget);
  });

  testWidgets('a core without spaces: update banner', (t) async {
    await show(t, [studio(view: const SpacesView.unsupported())]);
    expect(find.text('Update HyperOx on this computer'), findsOneWidget);
    expect(find.text('Open Inbox'), findsOneWidget);
    expect(find.text('Start agent'), findsNothing);
  });

  testWidgets('offline: a banner, nothing to start', (t) async {
    final c = studio()..spacesError = StateError('not connected: timed out');
    await show(t, [c]);
    expect(find.text('studio-pc is offline'), findsOneWidget);
    expect(find.text('last known'), findsOneWidget);
  });

  testWidgets('a read error is shown, not swallowed', (t) async {
    final c = studio()..spacesError = Exception('disk on fire');
    await show(t, [c]);
    expect(find.text("Spaces didn't load"), findsOneWidget);
    expect(find.textContaining('disk on fire'), findsOneWidget);
  });

  testWithSemantics('loading shows skeleton cards', (t) async {
    final c = _Slow();
    await pumpGolden(t, SpacesScreen(onNavigate: (_) {}), overrides: overrides([c]));
    await t.pump();
    expect(find.bySemanticsLabel('Loading spaces'), findsWidgets);
    expect(find.text('loading…'), findsOneWidget);
    c.release.complete();
    await t.pumpAndSettle();
  });

  testWidgets('with two machines the chip switches machine', (t) async {
    final other = FakeConnection(id: 'devbox', name: 'devbox', sessions: {});
    other.spacesView = const SpacesView(spaces: [Space(name: 'infra', folder: '/home/me/infra')]);
    await show(t, [studio(), other]);
    expect(find.text('acme-web'), findsOneWidget);
    await t.tap(find.text('studio-pc').first);
    await t.pumpAndSettle();
    await t.tap(find.text('devbox'));
    await t.pumpAndSettle();
    expect(find.text('infra'), findsOneWidget);
    expect(find.text('acme-web'), findsNothing);
  });

  testWidgets('no machines: empty state', (t) async {
    await show(t, []);
    expect(find.text('No machines yet'), findsOneWidget);
  });

  test('SpacesController: sessions found by terminal name and address', () async {
    final c = SpacesController(studio());
    await c.load();
    final d = c.value.value;
    expect(d.loading, isFalse);
    expect(d.sessionOf('claude')?.terminal, 't-claude');
    expect(d.sessionOf('t-claude')?.name, 'claude');
    expect(d.sessionOf('nope'), isNull);
    c.dispose();
  });

  test('SpacesController keeps the last view when the machine drops', () async {
    final conn = studio();
    final c = SpacesController(conn);
    await c.load();
    conn.spacesError = StateError('not connected: gone');
    await c.load();
    expect(c.value.value.offline, isTrue);
    expect(c.value.value.view?.spaces.length, 3);
    c.dispose();
  });

  testWidgets('golden: phone light and dark, accessible', (t) async {
    await show(t, [studio()]);
    await expectGolden(find.byType(MaterialApp), 'spaces_phone_light');
    await expectAccessible(t);
    await show(t, [studio()], b: Brightness.dark);
    await expectGolden(find.byType(MaterialApp), 'spaces_phone_dark');
    await expectAccessible(t);
  });

  testWidgets('golden: text 200 percent stacks the panes, accessible', (t) async {
    await show(t, [studio()], scale: 2);
    await expectGolden(find.byType(MaterialApp), 'spaces_phone_light_200');
    await expectAccessible(t);
  });

  testWidgets('golden: tablet map with live previews, accessible', (t) async {
    await show(t, [studio()], f: Frame.tablet, b: Brightness.dark);
    expect(find.text('hello t-claude'), findsOneWidget, reason: 'live preview of the pane');
    await expectGolden(find.byType(MaterialApp), 'spaces_tablet_dark');
    await expectAccessible(t);
  });
}

class _Slow extends FakeConnection {
  _Slow() : super(id: 'slow', name: 'slow');
  final release = Completer<void>();

  @override
  Future<SpacesView> spaces() async {
    await release.future;
    return const SpacesView();
  }
}
