import '../conn/machine_connection.dart';
import 'todo_model.dart';

/// A file over this is shown read-only and left untouched.
const todoMaxBytes = 1 << 20;

/// The list changed on the computer since it was read: nothing was written.
class TodoConflict implements Exception {
  TodoConflict(this.slug);
  final String slug;
  @override
  String toString() => '$slug changed on the computer';
}

class TodoDoc {
  TodoDoc({required this.slug, required this.raw, required this.list, this.problem});
  final String slug;

  /// The file text as read; a write only happens if the file still is this.
  final String raw;
  final TodoList list;

  /// Why the list is read-only (over 1 MB, not text), or null.
  final String? problem;

  bool get readOnly => problem != null;
}

class TodoIndex {
  const TodoIndex(this.entries, this.raw);
  final List<TodoIndexEntry> entries;

  /// `lists.md` as read; null when the file does not exist.
  final String? raw;
}

/// The desktop's to-do files on one machine, over [MachineConnection]'s file
/// calls. Every write re-reads the file first and refuses (TodoConflict) if
/// someone else changed it, so a phone never overwrites the desktop's edit.
class TodoRepo {
  TodoRepo(this.conn);
  final MachineConnection conn;

  Future<String> _dir() async => '${await conn.appHome()}/todo';

  Future<TodoIndex> loadIndex() async {
    final raw = await conn.readFile('${await _dir()}/lists.md');
    return TodoIndex(raw == null ? const [] : parseIndex(raw), raw);
  }

  Future<TodoDoc> loadList(TodoIndexEntry entry) async {
    final path = '${await _dir()}/${entry.slug}.md';
    final String? raw;
    try {
      raw = await conn.readFile(path);
    } catch (e) {
      return TodoDoc(
        slug: entry.slug,
        raw: '',
        list: TodoList(name: entry.name),
        problem: 'It is not text HyperOx can read.',
      );
    }
    if (raw == null) {
      return TodoDoc(slug: entry.slug, raw: '', list: TodoList(name: entry.name));
    }
    if (raw.length > todoMaxBytes) {
      return TodoDoc(
        slug: entry.slug,
        raw: raw,
        list: parseList(''),
        problem: 'Over 1 MB.',
      );
    }
    return TodoDoc(slug: entry.slug, raw: raw, list: parseList(raw));
  }

  /// Applies [edit] to the list as it is on the computer right now, if that is
  /// still what [base] was read from. Returns the new document.
  Future<TodoDoc> update(TodoDoc base, void Function(TodoList list) edit) async {
    if (base.readOnly) throw StateError('${base.slug} is read-only: ${base.problem}');
    final path = '${await _dir()}/${base.slug}.md';
    final now = await conn.readFile(path) ?? '';
    if (now != base.raw) throw TodoConflict(base.slug);
    final list = now.isEmpty ? TodoList(name: base.list.name) : parseList(now);
    edit(list);
    final text = serializeList(list);
    if (text != now) await conn.writeFile(path, text);
    return TodoDoc(slug: base.slug, raw: text, list: parseList(text));
  }

  /// A new list: its file, then its line at the end of `lists.md`.
  Future<TodoIndexEntry> createList(String name) async {
    final dir = await _dir();
    final index = await loadIndex();
    final slug = slugify(name, [for (final e in index.entries) e.slug]);
    final entry = TodoIndexEntry(escapeTitle(name.trim()), slug);
    await conn.writeFile('$dir/$slug.md', serializeList(TodoList(name: entry.name)));
    await _writeIndex(dir, index, [...index.entries, entry]);
    return entry;
  }

  Future<void> renameList(TodoIndexEntry entry, String name) async {
    final dir = await _dir();
    final index = await loadIndex();
    final i = index.entries.indexWhere((e) => e.slug == entry.slug);
    if (i < 0) throw TodoConflict(entry.slug);
    final clean = escapeTitle(name.trim());
    final path = '$dir/${entry.slug}.md';
    final raw = await conn.readFile(path);
    if (raw != null) {
      final list = parseList(raw)..name = clean;
      await conn.writeFile(path, serializeList(list));
    }
    final next = [...index.entries]..[i] = TodoIndexEntry(clean, entry.slug);
    await _writeIndex(dir, index, next);
  }

  /// Takes the list out of `lists.md`. Its file stays (the desktop never
  /// deletes a list file on its own).
  Future<void> removeList(TodoIndexEntry entry) async {
    final dir = await _dir();
    final index = await loadIndex();
    await _writeIndex(dir, index, [
      for (final e in index.entries)
        if (e.slug != entry.slug) e,
    ]);
  }

  Future<void> _writeIndex(String dir, TodoIndex before, List<TodoIndexEntry> next) async {
    final now = await conn.readFile('$dir/lists.md');
    if (now != before.raw) throw TodoConflict('lists');
    await conn.writeFile('$dir/lists.md', serializeIndex(next));
  }
}
