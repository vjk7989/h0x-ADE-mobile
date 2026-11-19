import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../conn/machine_connection.dart';
import '../data/todo_model.dart';
import '../data/todo_repo.dart';
import '../theme/theme_controller.dart' show sharedPrefsProvider;
import 'connections.dart';

class TodoState {
  const TodoState({
    this.lists = const [],
    this.current,
    this.doc,
    this.loading = true,
    this.error,
    this.offline = false,
  });

  final List<TodoIndexEntry> lists;
  final TodoIndexEntry? current;
  final TodoDoc? doc;
  final bool loading;

  /// Why the machine's files could not be read (not "offline").
  final String? error;

  /// The machine is not reachable: [doc] is the last synced copy.
  final bool offline;

  /// Nothing may be written: offline, nothing loaded, or a list too big or unreadable.
  bool get readOnly => offline || doc == null || doc!.readOnly;

  TodoState copyWith({
    List<TodoIndexEntry>? lists,
    TodoIndexEntry? current,
    TodoDoc? doc,
    bool? loading,
    Object? error = _keep,
    bool? offline,
  }) =>
      TodoState(
        lists: lists ?? this.lists,
        current: current ?? this.current,
        doc: doc ?? this.doc,
        loading: loading ?? this.loading,
        error: identical(error, _keep) ? this.error : error as String?,
        offline: offline ?? this.offline,
      );
}

const _keep = Object();

/// The result of a change: written, refused because the file changed on the
/// computer (the list was reloaded), or failed.
sealed class TodoOutcome {
  const TodoOutcome();
}

class TodoOk extends TodoOutcome {
  const TodoOk();
}

class TodoChanged extends TodoOutcome {
  const TodoChanged();
}

class TodoFailed extends TodoOutcome {
  const TodoFailed(this.message);
  final String message;
}

/// What a delete removed, for the 6 s undo.
class TodoDeleted {
  const TodoDeleted.task(this.index, this.task)
      : stepIndex = null,
        step = null;
  const TodoDeleted.step(this.index, int this.stepIndex, TodoStep this.step) : task = null;
  final int index;
  final TodoTask? task;
  final int? stepIndex;
  final TodoStep? step;
  String get title => task?.title ?? step!.title;
  bool get isStep => step != null;
}

/// One machine's to-do lists: reads, edits (each one a re-read and write),
/// and a copy of what it read, for when the machine is away.
class TodoController {
  TodoController(this.conn, {this.prefs}) : repo = TodoRepo(conn);

  final MachineConnection conn;
  final SharedPreferences? prefs;
  final TodoRepo repo;
  final value = ValueNotifier<TodoState>(const TodoState());
  var _disposed = false;

  String get _id => conn.machine.id;
  String get _cacheIndex => 'todo.cache.$_id.lists';
  String _cacheList(String slug) => 'todo.cache.$_id.$slug';
  String get _lastList => 'todo.list.$_id';

  void _set(TodoState s) {
    if (!_disposed) value.value = s;
  }

  bool _isOffline(Object e) => e is StateError && e.message.startsWith('not connected');

  /// Reads the index and one list ([slug], else the one used last, else the first).
  Future<void> load({String? slug}) async {
    _set(value.value.copyWith(loading: true, error: null));
    try {
      final index = await repo.loadIndex();
      await prefs?.setString(_cacheIndex, index.raw ?? '');
      final want = slug ?? value.value.current?.slug ?? prefs?.getString(_lastList);
      final entries = index.entries;
      final entry = entries.isEmpty
          ? null
          : entries.firstWhere((e) => e.slug == want, orElse: () => entries.first);
      TodoDoc? doc;
      if (entry != null) {
        doc = await repo.loadList(entry);
        if (!doc.readOnly) await prefs?.setString(_cacheList(entry.slug), doc.raw);
        await prefs?.setString(_lastList, entry.slug);
      }
      _set(TodoState(lists: entries, current: entry, doc: doc, loading: false));
    } catch (e) {
      if (_isOffline(e)) {
        _loadCached(slug);
      } else {
        _set(value.value.copyWith(loading: false, error: e.toString(), offline: false));
      }
    }
  }

  void _loadCached(String? slug) {
    final raw = prefs?.getString(_cacheIndex);
    final entries = raw == null ? const <TodoIndexEntry>[] : parseIndex(raw);
    final want = slug ?? value.value.current?.slug ?? prefs?.getString(_lastList);
    final entry = entries.isEmpty
        ? null
        : entries.firstWhere((e) => e.slug == want, orElse: () => entries.first);
    TodoDoc? doc;
    if (entry != null) {
      final text = prefs?.getString(_cacheList(entry.slug));
      if (text != null) {
        doc = TodoDoc(slug: entry.slug, raw: text, list: parseList(text));
      }
    }
    _set(TodoState(
      lists: entries,
      current: entry,
      doc: doc ?? value.value.doc,
      loading: false,
      offline: true,
    ));
  }

  Future<void> select(TodoIndexEntry entry) => load(slug: entry.slug);

  Future<TodoOutcome> _mutate(Future<TodoDoc> Function(TodoDoc base) run) async {
    final base = value.value.doc;
    if (base == null || value.value.readOnly) return const TodoFailed('This list is read-only.');
    try {
      final next = await run(base);
      await prefs?.setString(_cacheList(next.slug), next.raw);
      _set(value.value.copyWith(doc: next, error: null));
      return const TodoOk();
    } on TodoConflict {
      await load(slug: base.slug);
      return const TodoChanged();
    } catch (e) {
      if (_isOffline(e)) {
        _set(value.value.copyWith(offline: true));
        return const TodoFailed('The computer is offline. Nothing was changed.');
      }
      return TodoFailed(e.toString());
    }
  }

  Future<TodoOutcome> edit(void Function(TodoList l) change) =>
      _mutate((base) => repo.update(base, change));

  Future<TodoOutcome> setTask(int i, bool done) => edit((l) {
        if (i < l.tasks.length) setTaskDone(l.tasks[i], done);
      });

  Future<TodoOutcome> setStep(int i, int j, bool done) => edit((l) {
        if (i < l.tasks.length) setStepDone(l.tasks[i], j, done);
      });

  Future<TodoOutcome> addTask(String title) {
    final t = escapeTitle(title).trim();
    if (t.isEmpty) return Future.value(const TodoOk());
    return edit((l) => l.tasks.add(TodoTask(t, false)));
  }

  Future<TodoOutcome> addStep(int i, String title) {
    final t = escapeTitle(title).trim();
    if (t.isEmpty) return Future.value(const TodoOk());
    return edit((l) {
      if (i < l.tasks.length) {
        l.tasks[i].steps.add(TodoStep(t, false));
        l.tasks[i].done = false;
      }
    });
  }

  /// Renames a task, or step [j] of it. An empty title changes nothing.
  Future<TodoOutcome> rename(int i, int? j, String title) {
    final t = escapeTitle(title).trim();
    if (t.isEmpty) return Future.value(const TodoOk());
    return edit((l) {
      if (i >= l.tasks.length) return;
      if (j == null) {
        l.tasks[i].title = t;
      } else if (j < l.tasks[i].steps.length) {
        l.tasks[i].steps[j].title = t;
      }
    });
  }

  /// Removes a task (or step [j]); returns what to restore on undo, or null.
  Future<(TodoOutcome, TodoDeleted?)> delete(int i, [int? j]) async {
    final list = value.value.doc?.list;
    if (list == null || i >= list.tasks.length) return (const TodoFailed('Not found.'), null);
    final TodoDeleted gone;
    if (j == null) {
      gone = TodoDeleted.task(i, list.tasks[i]);
    } else if (j < list.tasks[i].steps.length) {
      gone = TodoDeleted.step(i, j, list.tasks[i].steps[j]);
    } else {
      return (const TodoFailed('Not found.'), null);
    }
    final r = await edit((l) {
      if (i >= l.tasks.length) return;
      if (j == null) {
        l.tasks.removeAt(i);
      } else if (j < l.tasks[i].steps.length) {
        l.tasks[i].steps.removeAt(j);
        l.tasks[i].done = l.tasks[i].steps.isNotEmpty && l.tasks[i].steps.every((s) => s.done);
      }
    });
    return (r, r is TodoOk ? gone : null);
  }

  Future<TodoOutcome> undo(TodoDeleted d) => edit((l) {
        if (d.isStep) {
          if (d.index >= l.tasks.length) return;
          final steps = l.tasks[d.index].steps;
          steps.insert(d.stepIndex! > steps.length ? steps.length : d.stepIndex!, d.step!);
        } else {
          l.tasks.insert(d.index > l.tasks.length ? l.tasks.length : d.index, d.task!);
        }
      });

  /// Drag: open task [from] to the place of open task [to].
  Future<TodoOutcome> reorder(int from, int to) => edit((l) => moveOpenTask(l, from, to));

  Future<TodoOutcome> moveStepTo(int i, int from, int to) => edit((l) {
        if (i < l.tasks.length) moveStep(l.tasks[i], from, to);
      });

  Future<TodoOutcome> createList(String name) async {
    try {
      final e = await repo.createList(name);
      await load(slug: e.slug);
      return const TodoOk();
    } on TodoConflict {
      await load();
      return const TodoChanged();
    } catch (e) {
      return TodoFailed(e.toString());
    }
  }

  Future<TodoOutcome> renameList(String name) async {
    final cur = value.value.current;
    if (cur == null) return const TodoFailed('No list.');
    try {
      await repo.renameList(cur, name);
      await load(slug: cur.slug);
      return const TodoOk();
    } on TodoConflict {
      await load();
      return const TodoChanged();
    } catch (e) {
      return TodoFailed(e.toString());
    }
  }

  /// Takes the list out of `lists.md` (its file stays).
  Future<TodoOutcome> removeList() async {
    final cur = value.value.current;
    if (cur == null) return const TodoFailed('No list.');
    try {
      await repo.removeList(cur);
      await load(slug: '');
      return const TodoOk();
    } on TodoConflict {
      await load();
      return const TodoChanged();
    } catch (e) {
      return TodoFailed(e.toString());
    }
  }

  void dispose() {
    _disposed = true;
    value.dispose();
  }
}

final todoControllerProvider = Provider.family<TodoController, String>((ref, machineId) {
  final conn = ref.watch(connectionsProvider).firstWhere((c) => c.machine.id == machineId);
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPrefsProvider);
  } catch (_) {
    prefs = null;
  }
  final c = TodoController(conn, prefs: prefs);
  ref.onDispose(c.dispose);
  return c;
});
