/// The desktop's to-do files (defaults/mods/todo/model.js), ported line for
/// line: `todo/<slug>.md` with `# Name`, `- [ ] task`, indented steps, and
/// every line it does not understand kept where it was.
library;

class TodoStep {
  TodoStep(this.title, this.done, [List<String>? extra]) : extra = extra ?? [];
  String title;
  bool done;
  final List<String> extra;
}

class TodoTask {
  TodoTask(this.title, this.done, {List<TodoStep>? steps, List<String>? extra})
      : steps = steps ?? [],
        extra = extra ?? [];
  String title;
  bool done;
  final List<TodoStep> steps;
  final List<String> extra;
}

class TodoList {
  TodoList({required this.name, List<String>? head, List<TodoTask>? tasks, List<String>? pre})
      : head = head ?? [],
        tasks = tasks ?? [],
        pre = pre ?? [];
  String name;

  /// Lines between the heading and the first task.
  final List<String> head;
  final List<TodoTask> tasks;

  /// Lines above the heading (front matter, comments).
  final List<String> pre;

  int get openCount => tasks.where((t) => !t.done).length;
  int get doneCount => tasks.length - openCount;
  bool get allDone => tasks.isNotEmpty && tasks.every((t) => t.done);
}

class TodoIndexEntry {
  const TodoIndexEntry(this.name, this.slug);
  final String name;
  final String slug;

  @override
  bool operator ==(Object other) =>
      other is TodoIndexEntry && other.name == name && other.slug == slug;

  @override
  int get hashCode => Object.hash(name, slug);
}

final _taskRe = RegExp(r'^[-*] \[( |x|X)\] (.*)$');
final _stepRe = RegExp(r'^(?:  +|\t)[ \t]*[-*] \[( |x|X)\] (.*)$');
final _fenceRe = RegExp(r'^---[ \t]*$');
final _headingRe = RegExp(r'^# (.*)$');
final _indexRe = RegExp(r'^- \[(.+?)\]\(([^()]*)\.md\)\s*$');
final _slugRe = RegExp(r'^[a-z0-9-]{1,60}$');

/// A title is one line: newlines become spaces.
String escapeTitle(String s) => s.replaceAll(RegExp(r'\r\n|\r|\n'), ' ');

String _trimEnd(String s) => s.replaceFirst(RegExp(r' +$'), '');

/// Parses a task-list file. Lines that are not tasks are kept verbatim.
TodoList parseList(String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  if (lines.isNotEmpty && lines.last == '') lines.removeLast();
  final list = TodoList(name: '');
  var named = false;
  final pre = <String>[];
  var close = -1;
  if (lines.isNotEmpty && _fenceRe.hasMatch(lines[0])) {
    for (var k = 1; k < lines.length; k++) {
      if (_fenceRe.hasMatch(lines[k])) {
        close = k;
        break;
      }
    }
  }
  final front = close > 0 ? lines.sublist(0, close + 1) : <String>[];
  for (final line in close > 0 ? lines.sublist(close + 1) : lines) {
    final task = _taskRe.firstMatch(line);
    if (task != null) {
      list.tasks.add(TodoTask(_trimEnd(task[2]!), task[1] != ' '));
      continue;
    }
    final cur = list.tasks.isEmpty ? null : list.tasks.last;
    final step = cur == null ? null : _stepRe.firstMatch(line);
    if (cur != null && step != null) {
      cur.steps.add(TodoStep(_trimEnd(step[2]!), step[1] != ' '));
      continue;
    }
    if (cur == null) {
      final h = named ? null : _headingRe.firstMatch(line);
      if (h != null) {
        named = true;
        list.name = h[1]!.trim();
      } else if (named) {
        list.head.add(line);
      } else {
        pre.add(line);
      }
    } else if (cur.steps.isNotEmpty) {
      cur.steps.last.extra.add(line);
    } else {
      cur.extra.add(line);
    }
  }
  // Without a heading there is nothing to stay above: those lines are the head.
  if (!named) list.head.addAll(pre);
  final above = named ? [...front, ...pre] : front;
  list.pre.addAll(above);
  if (list.name.isEmpty) list.name = 'Untitled';
  return list;
}

String serializeList(TodoList list) {
  final out = <String>[...list.pre, '# ${escapeTitle(list.name)}', ...list.head];
  for (final t in list.tasks) {
    out.add('- [${t.done ? 'x' : ' '}] ${escapeTitle(t.title)}');
    out.addAll(t.extra);
    for (final s in t.steps) {
      out.add('  - [${s.done ? 'x' : ' '}] ${escapeTitle(s.title)}');
      out.addAll(s.extra);
    }
  }
  return '${out.join('\n')}\n';
}

/// `- [Name](slug.md)` lines; invalid slugs and duplicates are dropped.
List<TodoIndexEntry> parseIndex(String text) {
  final lists = <TodoIndexEntry>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    final m = _indexRe.firstMatch(line);
    if (m == null) continue;
    final slug = m[2]!;
    if (!_slugRe.hasMatch(slug) || lists.any((l) => l.slug == slug)) continue;
    lists.add(TodoIndexEntry(m[1]!, slug));
  }
  return lists;
}

String serializeIndex(List<TodoIndexEntry> lists) =>
    lists.map((l) => '- [${escapeTitle(l.name)}](${l.slug}.md)\n').join();

/// A file-safe slug from a list name, unique against [taken]; `lists` is reserved.
String slugify(String name, List<String> taken) {
  var base = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.length > 60) base = base.substring(0, 60);
  base = base.replaceAll(RegExp(r'-+$'), '');
  if (base.isEmpty) base = 'list';
  bool used(String s) => s == 'lists' || taken.contains(s);
  var slug = base;
  for (var n = 2; used(slug); n++) {
    final suffix = '-$n';
    var head = base.length > 60 - suffix.length ? base.substring(0, 60 - suffix.length) : base;
    head = head.replaceAll(RegExp(r'-+$'), '');
    slug = '$head$suffix';
  }
  return slug;
}

/// Tick or untick a task: its steps follow.
void setTaskDone(TodoTask task, bool done) {
  task.done = done;
  for (final s in task.steps) {
    s.done = done;
  }
}

/// Tick or untick one step: the task is done exactly when every step is.
void setStepDone(TodoTask task, int j, bool done) {
  if (j < 0 || j >= task.steps.length) return;
  task.steps[j].done = done;
  task.done = task.steps.every((s) => s.done);
}

/// Moves open task [from] to the place of open task [to] (both indices among
/// the open tasks): done tasks stay where they are (the desktop rule).
void moveOpenTask(TodoList list, int from, int to) {
  final slots = [for (var i = 0; i < list.tasks.length; i++) if (!list.tasks[i].done) i];
  if (from < 0 || from >= slots.length || to < 0 || to >= slots.length || from == to) return;
  final open = [for (final i in slots) list.tasks[i]];
  final moved = open.removeAt(from);
  open.insert(to, moved);
  for (var k = 0; k < slots.length; k++) {
    list.tasks[slots[k]] = open[k];
  }
}

/// Moves step [from] to place [to] inside one task.
void moveStep(TodoTask task, int from, int to) {
  if (from < 0 || from >= task.steps.length || to < 0 || to >= task.steps.length || from == to) {
    return;
  }
  task.steps.insert(to, task.steps.removeAt(from));
}
