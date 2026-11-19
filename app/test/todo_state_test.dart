import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/data/todo_model.dart';
import 'package:hyperox/state/todo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_connection.dart';

const home = '/home/me/.config/h0x-ade';
const release = '$home/todo/release.md';
const lists = '$home/todo/lists.md';

const releaseText = '# Release 0.2\n'
    '- [ ] Write notes\n'
    '  - [x] Draft\n'
    '  - [ ] Proof\n'
    '- [ ] Icon\n'
    '- [ ] Test\n'
    '- [x] Fix login\n';

FakeConnection machine() {
  final c = FakeConnection(id: 'studio', name: 'studio-pc');
  c.files[lists] = '- [Release 0.2](release.md)\n- [Home](home.md)\n';
  c.files[release] = releaseText;
  c.files['$home/todo/home.md'] = '# Home\n- [ ] Milk\n';
  return c;
}

class _Away extends FakeConnection {
  _Away() : super(id: 'studio', name: 'studio-pc');

  @override
  Future<String> appHome() async => throw StateError('not connected: timed out');
}

Future<TodoController> loaded(FakeConnection c, {SharedPreferences? prefs}) async {
  final p = prefs ?? await _prefs();
  final t = TodoController(c, prefs: p);
  addTearDown(t.dispose);
  await t.load();
  return t;
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

List<String> titles(TodoController t) => [for (final x in t.value.value.doc!.list.tasks) x.title];

void main() {
  test('load: first list, its tasks, and the last list is remembered', () async {
    final c = machine();
    final prefs = await _prefs();
    final t = await loaded(c, prefs: prefs);
    final s = t.value.value;
    expect(s.loading, isFalse);
    expect(s.current?.slug, 'release');
    expect(s.lists.map((e) => e.name), ['Release 0.2', 'Home']);
    expect(s.doc!.list.openCount, 3);
    await t.select(s.lists[1]);
    expect(t.value.value.doc!.list.name, 'Home');
    final again = await loaded(c, prefs: prefs);
    expect(again.value.value.current?.slug, 'home');
  });

  test('no lists.md: no lists, not an error', () async {
    final c = FakeConnection(id: 'x', name: 'x');
    final t = await loaded(c);
    expect(t.value.value.lists, isEmpty);
    expect(t.value.value.doc, isNull);
    expect(t.value.value.error, isNull);
    expect(t.value.value.readOnly, isTrue);
  });

  test('ticks, steps, adds and renames are written to the desktop file', () async {
    final c = machine();
    final t = await loaded(c);
    expect(await t.setTask(1, true), isA<TodoOk>());
    expect(c.files[release], contains('- [x] Icon'));
    await t.setStep(0, 1, true);
    expect(c.files[release], contains('  - [x] Proof'));
    expect(t.value.value.doc!.list.tasks[0].done, isTrue, reason: 'last step ticks the task');
    await t.addTask('  New one \n');
    expect(c.files[release], endsWith('- [ ] New one\n'));
    await t.addStep(2, 'a step');
    expect(c.files[release], contains('- [ ] Test\n  - [ ] a step\n'));
    await t.rename(2, null, 'Test on a phone');
    expect(c.files[release], contains('- [ ] Test on a phone\n'));
    await t.rename(0, 0, 'Draft notes');
    expect(c.files[release], contains('  - [x] Draft notes'));
  });

  test('empty titles change nothing and write nothing', () async {
    final c = machine();
    final t = await loaded(c);
    final w = c.writes;
    await t.addTask('   ');
    await t.addStep(0, '');
    await t.rename(0, null, ' ');
    expect(c.writes, w);
  });

  test('delete returns what to put back; undo restores task and step in place', () async {
    final c = machine();
    final t = await loaded(c);
    final (r, gone) = await t.delete(1);
    expect(r, isA<TodoOk>());
    expect(titles(t), isNot(contains('Icon')));
    await t.undo(gone!);
    expect(titles(t), ['Write notes', 'Icon', 'Test', 'Fix login']);
    final (r2, step) = await t.delete(0, 0);
    expect(r2, isA<TodoOk>());
    expect(t.value.value.doc!.list.tasks[0].steps.length, 1);
    await t.undo(step!);
    expect(t.value.value.doc!.list.tasks[0].steps.map((s) => s.title), ['Draft', 'Proof']);
    expect(c.files[release], releaseText);
  });

  test('deleting something that is not there fails without writing', () async {
    final c = machine();
    final t = await loaded(c);
    final w = c.writes;
    final (r, gone) = await t.delete(99);
    expect(r, isA<TodoFailed>());
    expect(gone, isNull);
    expect(c.writes, w);
  });

  test('reorder moves open tasks only, among themselves', () async {
    final c = machine();
    final t = await loaded(c);
    await t.reorder(2, 0); // Test before Write notes
    expect(titles(t), ['Test', 'Write notes', 'Icon', 'Fix login']);
    await t.moveStepTo(1, 0, 1);
    expect(t.value.value.doc!.list.tasks[1].steps.map((s) => s.title), ['Proof', 'Draft']);
  });

  test('a change on the computer first: nothing written, list reloaded, TodoChanged', () async {
    final c = machine();
    final t = await loaded(c);
    c.files[release] = '$releaseText- [ ] Added on the desktop\n';
    final w = c.writes;
    expect(await t.setTask(1, true), isA<TodoChanged>());
    expect(c.writes, w);
    expect(titles(t), contains('Added on the desktop'));
    expect(await t.setTask(1, true), isA<TodoOk>(), reason: 'the retry works');
  });

  test('a write that fails is a failure with its message, state unchanged', () async {
    final c = machine();
    final t = await loaded(c);
    c.writeError = Exception('disk full');
    final r = await t.setTask(1, true);
    expect(r, isA<TodoFailed>().having((f) => f.message, 'message', contains('disk full')));
    expect(t.value.value.doc!.list.tasks[1].done, isFalse);
  });

  test('offline: the last synced copy is shown read-only; edits are refused', () async {
    final prefs = await _prefs();
    await loaded(machine(), prefs: prefs);
    final away = TodoController(_Away(), prefs: prefs);
    addTearDown(away.dispose);
    await away.load();
    final s = away.value.value;
    expect(s.offline, isTrue);
    expect(s.readOnly, isTrue);
    expect(s.doc!.list.name, 'Release 0.2');
    expect(await away.setTask(1, true), isA<TodoFailed>());
  });

  test('offline with nothing cached: no lists, offline', () async {
    final away = TodoController(_Away(), prefs: await _prefs());
    addTearDown(away.dispose);
    await away.load();
    expect(away.value.value.offline, isTrue);
    expect(away.value.value.doc, isNull);
  });

  test('edits made while online are in the offline copy too', () async {
    final prefs = await _prefs();
    final t = await loaded(machine(), prefs: prefs);
    await t.setTask(1, true);
    final away = TodoController(_Away(), prefs: prefs);
    addTearDown(away.dispose);
    await away.load();
    expect(away.value.value.doc!.list.tasks[1].done, isTrue);
  });

  test('a list over 1 MB is read-only', () async {
    final c = machine();
    c.files[release] = '# Big\n${'- [ ] x\n' * 140000}';
    final t = await loaded(c);
    expect(t.value.value.doc!.readOnly, isTrue);
    expect(await t.setTask(0, true), isA<TodoFailed>());
  });

  test('create, rename and remove a list', () async {
    final c = machine();
    final t = await loaded(c);
    expect(await t.createList('Reading'), isA<TodoOk>());
    expect(t.value.value.current?.slug, 'reading');
    expect(c.files[lists], contains('- [Reading](reading.md)'));
    expect(await t.renameList('Books'), isA<TodoOk>());
    expect(t.value.value.current?.name, 'Books');
    expect(c.files['$home/todo/reading.md'], startsWith('# Books'));
    expect(await t.removeList(), isA<TodoOk>());
    expect(t.value.value.lists.map((e) => e.slug), ['release', 'home']);
    expect(c.files, contains('$home/todo/reading.md'), reason: 'the file stays');
  });
}
