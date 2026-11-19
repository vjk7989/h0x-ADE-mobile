import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/screens/todo_screen.dart';
import 'package:hyperox/state/connections.dart';
import 'package:hyperox/state/inbox.dart';
import 'package:hyperox/theme/theme_controller.dart' show sharedPrefsProvider;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/a11y.dart';
import 'support/fake_connection.dart';
import 'support/golden.dart';
import 'support/golden_expect.dart';

const home = '/home/me/.config/h0x-ade';
const release = '$home/todo/release.md';
const lists = '$home/todo/lists.md';

const releaseText = '# Release 0.2\n'
    '- [ ] Write release notes\n'
    '  - [x] Draft the changelog\n'
    '  - [ ] Add screenshots\n'
    '  - [ ] Proofread\n'
    '- [ ] Update the app icon\n'
    '- [ ] Test on a small phone\n'
    '  - [ ] Pixel\n'
    '  - [ ] Galaxy\n'
    '- [ ] Book a design review\n'
    '- [ ] Reply to beta testers\n'
    '- [x] Fix the login timeout\n'
    '- [x] Bump version to 0.2.0\n';

FakeConnection machine({String id = 'studio', String name = 'studio-pc'}) {
  final c = FakeConnection(id: id, name: name);
  c.files[lists] = '- [Release 0.2](release.md)\n- [Home](home.md)\n- [Reading](reading.md)\n';
  c.files[release] = releaseText;
  c.files['$home/todo/home.md'] = '# Home\n- [x] Water the plants\n- [x] Call the plumber\n';
  c.files['$home/todo/reading.md'] = '# Reading\n';
  return c;
}

class _Away extends FakeConnection {
  _Away() : super(id: 'studio', name: 'studio-pc');

  @override
  Future<String> appHome() async => throw StateError('not connected: timed out');
}

class _Slow extends FakeConnection {
  _Slow() : super(id: 'studio', name: 'studio-pc');
  final release = Completer<void>();

  @override
  Future<String> appHome() async {
    await release.future;
    return super.appHome();
  }
}

List<Override> overrides(List<FakeConnection> conns) => [
      connectionsProvider.overrideWithValue(conns),
      inboxPollProvider.overrideWithValue(null),
    ];

Future<void> show(WidgetTester t, List<FakeConnection> conns,
    {Brightness b = Brightness.light, double scale = 1, Frame f = Frame.phone}) async {
  await pumpGolden(
    t,
    TodoScreen(onNavigate: (_) {}, undoFor: const Duration(seconds: 6)),
    frame: f,
    brightness: b,
    textScale: scale,
    overrides: overrides(conns),
  );
  await t.pumpAndSettle();
}

final dialogField =
    find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));

void main() {
  testWidgets('shows the list, its progress, steps count and Completed fold', (t) async {
    await show(t, [machine()]);
    expect(find.text('Release 0.2'), findsOneWidget);
    expect(find.text('studio-pc · 5 open'), findsOneWidget);
    expect(find.text('2 of 7 done'), findsOneWidget);
    expect(find.text('Write release notes'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Fix the login timeout'), findsNothing, reason: 'folded');
  });

  testWidgets('Completed unfolds and a done task unticks', (t) async {
    final c = machine();
    await show(t, [c]);
    await t.tap(find.text('Completed'));
    await t.pumpAndSettle();
    expect(find.text('Fix the login timeout'), findsOneWidget);
  });

  testWidgets('tapping the circle ticks the task in the desktop file', (t) async {
    final sem = t.ensureSemantics();
    addTearDown(sem.dispose);
    final c = machine();
    await show(t, [c]);
    await t.tap(find.bySemanticsLabel('Mark done: Update the app icon'));
    await t.pumpAndSettle();
    expect(c.files[release], contains('- [x] Update the app icon'));
    expect(find.text('3 of 7 done'), findsOneWidget);
  });

  testWidgets('expanding shows steps; ticking a step is written', (t) async {
    final sem = t.ensureSemantics();
    addTearDown(sem.dispose);
    final c = machine();
    await show(t, [c]);
    await t.tap(find.bySemanticsLabel('Show steps of Write release notes'));
    await t.pumpAndSettle();
    expect(find.text('Add screenshots'), findsOneWidget);
    expect(find.text('Add step'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Mark step done: Add screenshots'));
    await t.pumpAndSettle();
    expect(c.files[release], contains('  - [x] Add screenshots'));
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('Add step writes a new step under the task', (t) async {
    final sem = t.ensureSemantics();
    addTearDown(sem.dispose);
    final c = machine();
    await show(t, [c]);
    await t.tap(find.bySemanticsLabel('Show steps of Update the app icon'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add step'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Export 512 px');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(c.files[release], contains('- [ ] Update the app icon\n  - [ ] Export 512 px\n'));
  });

  testWidgets('the add bar adds a task and clears', (t) async {
    final c = machine();
    await show(t, [c]);
    await t.tap(find.byType(TextField).first);
    await t.enterText(find.byType(TextField).first, 'Ship it');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(c.files[release], contains('- [ ] Ship it'));
    expect(find.text('Ship it'), findsOneWidget);
    expect(find.text('studio-pc · 6 open'), findsOneWidget);
  });

  testWidgets('double tap edits the title in place and saves', (t) async {
    final c = machine();
    await show(t, [c]);
    await t.tap(find.text('Update the app icon'));
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.text('Update the app icon'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Update the icon and splash');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(c.files[release], contains('- [ ] Update the icon and splash\n'));
  });

  testWidgets('swipe left deletes with an undo that restores it', (t) async {
    final c = machine();
    await show(t, [c]);
    await t.drag(find.text('Update the app icon'), const Offset(-400, 0));
    await t.pumpAndSettle();
    expect(c.files[release], isNot(contains('Update the app icon')));
    expect(find.text('Task deleted · Update the app icon'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(c.files[release], releaseText);
    expect(find.text('Update the app icon'), findsOneWidget);
  });

  testWidgets('the undo snackbar lasts six seconds', (t) async {
    final c = machine();
    await show(t, [c]);
    await t.drag(find.text('Update the app icon'), const Offset(-400, 0));
    await t.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    expect(find.text('Undo'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('long press and drag moves an open task; done tasks stay put', (t) async {
    final c = machine();
    await show(t, [c]);
    final from = t.getCenter(find.text('Book a design review'));
    final g = await t.startGesture(from);
    await t.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(0, -140));
    await t.pump(const Duration(milliseconds: 100));
    await g.moveBy(const Offset(0, -60));
    await t.pump(const Duration(milliseconds: 100));
    await g.up();
    await t.pumpAndSettle();
    final text = c.files[release]!;
    expect(text.indexOf('Book a design review'), lessThan(text.indexOf('Test on a small phone')));
    expect(text.indexOf('Fix the login timeout'), greaterThan(text.indexOf('Reply to beta testers')));
  });

  testWidgets('a change on the computer first: told, reloaded, nothing overwritten', (t) async {
    final sem = t.ensureSemantics();
    addTearDown(sem.dispose);
    final c = machine();
    await show(t, [c]);
    c.files[release] = '$releaseText- [ ] Added on the desktop\n';
    await t.tap(find.bySemanticsLabel('Mark done: Update the app icon'));
    await t.pumpAndSettle();
    expect(find.textContaining('changed on the computer'), findsOneWidget);
    expect(c.files[release], contains('- [ ] Update the app icon'));
    expect(find.text('Added on the desktop'), findsOneWidget);
  });

  testWidgets('the list switcher shows lists in lists.md order and opens another', (t) async {
    final c = machine();
    await show(t, [c]);
    await t.tap(find.text('Release 0.2'));
    await t.pumpAndSettle();
    expect(find.text('order from todo/lists.md on studio-pc'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('studio-pc · 0 open'), findsOneWidget);
    expect(find.text('All done for today'), findsOneWidget);
  });

  testWidgets('New list creates it; Remove list only unlists it', (t) async {
    final c = machine();
    await show(t, [c]);
    await t.tap(find.text('Release 0.2'));
    await t.pumpAndSettle();
    await t.tap(find.text('New list'));
    await t.pumpAndSettle();
    await t.enterText(dialogField, 'Errands');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
    expect(c.files[lists], contains('- [Errands](errands.md)'));
    expect(find.text('No tasks yet. Add one above.'), findsOneWidget);
    await t.tap(find.text('Errands').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Remove list…'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(c.files[lists], isNot(contains('errands')));
    expect(c.files, contains('$home/todo/errands.md'));
  });

  testWidgets('an empty list says so', (t) async {
    final c = machine();
    c.files[lists] = '- [Reading](reading.md)\n';
    await show(t, [c]);
    expect(find.text('No tasks yet. Add one above.'), findsOneWidget);
  });

  testWidgets('offline: last synced copy, read-only, banner says why', (t) async {
    SharedPreferences.setMockInitialValues({
      'todo.cache.studio.lists': '- [Release 0.2](release.md)\n',
      'todo.cache.studio.release': releaseText,
    });
    final prefs = await SharedPreferences.getInstance();
    await pumpGolden(
      t,
      TodoScreen(onNavigate: (_) {}),
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), ...overrides([_Away()])],
    );
    await t.pumpAndSettle();
    expect(find.text('studio-pc is offline'), findsOneWidget);
    expect(find.text('Write release notes'), findsOneWidget);
    expect(find.byType(Dismissible), findsNothing, reason: 'no swipe to delete while read-only');
    await expectGolden(find.byType(MaterialApp), 'todo_phone_light_offline');
    await expectAccessible(t);
  });

  testWidgets('a list over 1 MB is shown read-only with a reason', (t) async {
    final c = machine();
    c.files[release] = '# Big\n${'- [ ] x\n' * 140000}';
    await show(t, [c]);
    expect(find.text("This list can't be read"), findsOneWidget);
    expect(find.byType(Dismissible), findsNothing);
  });

  testWidgets('which computer: the picker appears with two machines and switches', (t) async {
    final sem = t.ensureSemantics();
    addTearDown(sem.dispose);
    final other = machine(id: 'devbox', name: 'devbox');
    other.files['$home/todo/lists.md'] = '- [Garden](garden.md)\n';
    other.files['$home/todo/garden.md'] = '# Garden\n- [ ] Prune\n';
    await show(t, [machine(), other]);
    await t.tap(find.bySemanticsLabel('Computer: studio-pc'));
    await t.pumpAndSettle();
    expect(find.text('Which computer'), findsOneWidget);
    await t.tap(find.text('devbox'));
    await t.pumpAndSettle();
    expect(find.text('Garden'), findsOneWidget);
    expect(find.text('Prune'), findsOneWidget);
  });

  testWidgets('one machine: no computer picker', (t) async {
    final sem = t.ensureSemantics();
    addTearDown(sem.dispose);
    await show(t, [machine()]);
    expect(find.bySemanticsLabel('Computer: studio-pc'), findsNothing);
  });

  testWidgets('no machines: empty state', (t) async {
    await show(t, []);
    expect(find.text('No machines yet'), findsOneWidget);
  });

  testWidgets('no lists.md on the computer: offers New list', (t) async {
    final c = FakeConnection(id: 'x', name: 'x');
    await show(t, [c]);
    expect(find.text('No lists on x'), findsOneWidget);
    await t.tap(find.text('New list'));
    await t.pumpAndSettle();
    await t.enterText(dialogField, 'First');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
    expect(c.files[lists], '- [First](first.md)\n');
  });

  testWidgets('loading shows skeleton cards', (t) async {
    final sem = t.ensureSemantics();
    addTearDown(sem.dispose);
    final c = _Slow();
    await pumpGolden(t, TodoScreen(onNavigate: (_) {}), overrides: overrides([c]));
    await t.pump();
    expect(find.bySemanticsLabel('Loading tasks'), findsWidgets);
    c.release.complete();
    await t.pumpAndSettle();
  });

  testWidgets('golden: phone light and dark, accessible', (t) async {
    await show(t, [machine()]);
    await expectGolden(find.byType(MaterialApp), 'todo_phone_light');
    await expectAccessible(t);
    await show(t, [machine()], b: Brightness.dark);
    await expectGolden(find.byType(MaterialApp), 'todo_phone_dark');
    await expectAccessible(t);
  });

  testWidgets('golden: steps open and Completed open', (t) async {
    final sem = t.ensureSemantics();
    addTearDown(sem.dispose);
    await show(t, [machine()]);
    await t.tap(find.bySemanticsLabel('Show steps of Write release notes'));
    await t.tap(find.text('Completed'));
    await t.pumpAndSettle();
    await expectGolden(find.byType(MaterialApp), 'todo_phone_light_open');
  });

  testWidgets('golden: text 200 percent, accessible', (t) async {
    await show(t, [machine()], scale: 2);
    await expectGolden(find.byType(MaterialApp), 'todo_phone_light_200');
    await expectAccessible(t);
  });

  testWidgets('golden: tablet lists and tasks, accessible', (t) async {
    await show(t, [machine()], f: Frame.tablet);
    expect(find.text('LISTS'), findsOneWidget);
    await expectGolden(find.byType(MaterialApp), 'todo_tablet_light');
    await expectAccessible(t);
  });
}
