import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/data/todo_model.dart';
import 'package:hyperox/data/todo_repo.dart';

import 'support/fake_connection.dart';

const home = '/home/me/.config/h0x-ade';

void main() {
  group('todo model (the desktop format)', () {
    test('parses name, tasks, steps and ticks', () {
      final l = parseList('# Release 0.2\n'
          '- [ ] Write notes\n'
          '  - [x] Draft\n'
          '  - [ ] Proof\n'
          '- [X] Ship\n');
      expect(l.name, 'Release 0.2');
      expect(l.tasks.map((t) => t.title), ['Write notes', 'Ship']);
      expect(l.tasks[0].steps.map((s) => s.done), [true, false]);
      expect(l.tasks[1].done, isTrue);
      expect(l.openCount, 1);
      expect(l.doneCount, 1);
    });

    test('round trips and keeps lines it does not understand', () {
      const text = '---\nowner: me\n---\n# Home\nsome note\n'
          '- [ ] water plants\nlink: https://x\n'
          '  - [ ] step\n    detail\n'
          '- [x] done\n';
      expect(serializeList(parseList(text)), text);
    });

    test('a file with no heading is Untitled and keeps its lines', () {
      final l = parseList('hello\n- [ ] a\n');
      expect(l.name, 'Untitled');
      expect(l.head, ['hello']);
      expect(serializeList(l), '# Untitled\nhello\n- [ ] a\n');
    });

    test('empty text is an empty Untitled list', () {
      final l = parseList('');
      expect(l.name, 'Untitled');
      expect(l.tasks, isEmpty);
    });

    test('CRLF is read, written back as LF; trailing spaces trimmed', () {
      final l = parseList('# A\r\n- [ ] one  \r\n');
      expect(l.tasks.single.title, 'one');
      expect(serializeList(l), '# A\n- [ ] one\n');
    });

    test('newlines in a title become spaces', () {
      final l = TodoList(name: 'A\nB', tasks: [TodoTask('x\ny', false)]);
      expect(serializeList(l), '# A B\n- [ ] x y\n');
    });

    test('ticking a task ticks its steps; the last step ticks the task', () {
      final l = parseList('# A\n- [ ] t\n  - [ ] a\n  - [ ] b\n');
      final t = l.tasks.single;
      setTaskDone(t, true);
      expect(t.steps.every((s) => s.done), isTrue);
      setStepDone(t, 0, false);
      expect(t.done, isFalse);
      setStepDone(t, 0, true);
      expect(t.done, isTrue);
      setStepDone(t, 9, true); // out of range: ignored
    });

    test('index: parses, drops bad slugs and duplicates, serializes', () {
      final e = parseIndex('- [Release 0.2](release-0-2.md)\n'
          '- [Bad](../x.md)\n'
          '- [Dup](release-0-2.md)\n'
          'junk\n'
          '- [Home](home.md)\n');
      expect(e, const [TodoIndexEntry('Release 0.2', 'release-0-2'), TodoIndexEntry('Home', 'home')]);
      expect(serializeIndex(e), '- [Release 0.2](release-0-2.md)\n- [Home](home.md)\n');
      expect(parseIndex(''), isEmpty);
    });

    test('slugify: lowercase, dashes, unique, lists is reserved', () {
      expect(slugify('Release 0.2!', []), 'release-0-2');
      expect(slugify('Home', ['home']), 'home-2');
      expect(slugify('Home', ['home', 'home-2']), 'home-3');
      expect(slugify('Lists', []), 'lists-2');
      expect(slugify('???', []), 'list');
      expect(slugify('a' * 80, []).length, 60);
    });

    test('moving an open task keeps done tasks where they are', () {
      final l = parseList('# A\n- [ ] a\n- [x] d\n- [ ] b\n- [ ] c\n');
      moveOpenTask(l, 2, 0); // c before a
      expect(l.tasks.map((t) => t.title), ['c', 'd', 'a', 'b']);
      moveOpenTask(l, 0, 0);
      moveOpenTask(l, 5, 0);
      expect(l.tasks.map((t) => t.title), ['c', 'd', 'a', 'b']);
    });

    test('moving a step stays inside its task', () {
      final t = parseList('# A\n- [ ] t\n  - [ ] 1\n  - [ ] 2\n  - [ ] 3\n').tasks.single;
      moveStep(t, 0, 2);
      expect(t.steps.map((s) => s.title), ['2', '3', '1']);
      moveStep(t, 0, 9);
      expect(t.steps.map((s) => s.title), ['2', '3', '1']);
    });
  });

  group('TodoRepo', () {
    late FakeConnection conn;
    late TodoRepo repo;
    setUp(() {
      conn = FakeConnection();
      repo = TodoRepo(conn);
      conn.files['$home/todo/lists.md'] = '- [Release](release.md)\n- [Home](home.md)\n';
      conn.files['$home/todo/release.md'] = '# Release\n- [ ] one\n- [ ] two\n';
    });

    test('reads the index and a list', () async {
      final index = await repo.loadIndex();
      expect(index.entries.map((e) => e.slug), ['release', 'home']);
      final doc = await repo.loadList(index.entries.first);
      expect(doc.list.tasks.map((t) => t.title), ['one', 'two']);
      expect(doc.readOnly, isFalse);
    });

    test('a list named in lists.md with no file yet is empty and writable', () async {
      final index = await repo.loadIndex();
      final doc = await repo.loadList(index.entries[1]);
      expect(doc.list.tasks, isEmpty);
      expect(doc.list.name, 'Home');
      final next = await repo.update(doc, (l) => l.tasks.add(TodoTask('milk', false)));
      expect(conn.files['$home/todo/home.md'], '# Home\n- [ ] milk\n');
      expect(next.list.tasks.single.title, 'milk');
    });

    test('no lists.md at all is no lists', () async {
      conn.files.remove('$home/todo/lists.md');
      final index = await repo.loadIndex();
      expect(index.entries, isEmpty);
      expect(index.raw, isNull);
    });

    test('an edit is written once, atomically as one file write', () async {
      final doc = await repo.loadList((await repo.loadIndex()).entries.first);
      final w = conn.writes;
      final next = await repo.update(doc, (l) => setTaskDone(l.tasks[0], true));
      expect(conn.writes, w + 1);
      expect(conn.files['$home/todo/release.md'], '# Release\n- [x] one\n- [ ] two\n');
      expect(next.raw, conn.files['$home/todo/release.md']);
    });

    test('a change on the computer since the read is a conflict and nothing is written', () async {
      final doc = await repo.loadList((await repo.loadIndex()).entries.first);
      conn.files['$home/todo/release.md'] = '# Release\n- [ ] one\n- [ ] two\n- [ ] added on desktop\n';
      final w = conn.writes;
      await expectLater(repo.update(doc, (l) => l.tasks.clear()), throwsA(isA<TodoConflict>()));
      expect(conn.writes, w);
      expect(conn.files['$home/todo/release.md'], contains('added on desktop'));
      // reload, then the same edit works
      final fresh = await repo.loadList((await repo.loadIndex()).entries.first);
      await repo.update(fresh, (l) => setTaskDone(l.tasks[2], true));
      expect(conn.files['$home/todo/release.md'], contains('- [x] added on desktop'));
    });

    test('a file changed between the re-read and nothing else: a no-op edit writes nothing', () async {
      final doc = await repo.loadList((await repo.loadIndex()).entries.first);
      final w = conn.writes;
      await repo.update(doc, (l) {});
      expect(conn.writes, w);
    });

    test('over 1 MB is read-only and never written', () async {
      conn.files['$home/todo/release.md'] = '# R\n${'- [ ] x\n' * 140000}';
      final doc = await repo.loadList((await repo.loadIndex()).entries.first);
      expect(doc.readOnly, isTrue);
      expect(doc.problem, contains('1 MB'));
      await expectLater(repo.update(doc, (l) {}), throwsStateError);
    });

    test('an unreadable file is read-only with a reason', () async {
      conn.onRead = (p) {
        if (p.endsWith('release.md')) throw StateError('not text');
      };
      final doc = await repo.loadList((await repo.loadIndex()).entries.first);
      expect(doc.readOnly, isTrue);
    });

    test('lines the desktop keeps survive a phone edit', () async {
      conn.files['$home/todo/release.md'] = '# Release\nnote\n- [ ] one\nextra\n  - [ ] s\n';
      final doc = await repo.loadList((await repo.loadIndex()).entries.first);
      await repo.update(doc, (l) => setTaskDone(l.tasks[0], true));
      expect(conn.files['$home/todo/release.md'], '# Release\nnote\n- [x] one\nextra\n  - [x] s\n');
    });

    test('create: a new file and a line at the end of lists.md, unique slug', () async {
      final e = await repo.createList('Release');
      expect(e.slug, 'release-2');
      expect(conn.files['$home/todo/release-2.md'], '# Release\n');
      expect(conn.files['$home/todo/lists.md'],
          '- [Release](release.md)\n- [Home](home.md)\n- [Release](release-2.md)\n');
    });

    test('rename changes the heading and the index; delete only unlists', () async {
      final index = await repo.loadIndex();
      await repo.renameList(index.entries.first, 'Release 0.3');
      expect(conn.files['$home/todo/release.md'], startsWith('# Release 0.3\n'));
      expect(conn.files['$home/todo/lists.md'], startsWith('- [Release 0.3](release.md)\n'));
      await repo.removeList(index.entries.first);
      expect(conn.files['$home/todo/lists.md'], '- [Home](home.md)\n');
      expect(conn.files, contains('$home/todo/release.md'), reason: 'the file stays');
    });

    test('lists.md changed on the computer during a rename is a conflict', () async {
      final index = await repo.loadIndex();
      var reads = 0;
      conn.onRead = (p) {
        if (p.endsWith('lists.md') && ++reads == 2) {
          conn.files[p] = '${conn.files[p]}- [Other](other.md)\n';
        }
      };
      await expectLater(repo.renameList(index.entries.first, 'X'), throwsA(isA<TodoConflict>()));
      expect(conn.files['$home/todo/lists.md'], contains('other.md'));
    });
  });
}
