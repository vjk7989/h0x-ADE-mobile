import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../widgets/hx_icon_compat.dart';
import '../conn/machine_connection.dart';
import '../data/todo_model.dart';
import '../state/connections.dart';
import '../state/todo.dart';
import '../theme/motion.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../widgets/app_shell.dart';
import '../widgets/hx.dart';
import '../widgets/hx_bits.dart';
import '../widgets/hx_icons.dart';
import '../widgets/hx_refresh.dart';
import '../widgets/status_motion.dart';

export '../widgets/hx.dart' show accentOnInverse;

/// The desktop's to-do lists from a chosen computer (design: To-do). The
/// files are the desktop's own Markdown; every change re-reads and writes.
class TodoScreen extends ConsumerStatefulWidget {
  const TodoScreen({super.key, this.onNavigate, this.undoFor = const Duration(seconds: 6)});

  final void Function(NavDest dest)? onNavigate;

  /// How long the undo snackbar stays (the desktop's `UNDO_MS`).
  final Duration undoFor;

  @override
  ConsumerState<TodoScreen> createState() => _TodoScreenState();
}

TextStyle _hand(double size, {Color? color, bool strike = false, Color? strikeColor}) => TextStyle(
      fontFamily: 'PatrickHand',
      fontSize: size,
      height: 1.25,
      color: color,
      decoration: strike ? TextDecoration.lineThrough : null,
      decorationColor: strikeColor,
      decorationThickness: 1.2,
    );

/// Marks the card being dragged, so it draws lifted (shadow, grip).
class _Lifted extends InheritedWidget {
  const _Lifted({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Lifted>() != null;

  @override
  bool updateShouldNotify(_Lifted old) => false;
}

/// Tells an inline edit to give up (the system Back button while editing).
final _cancelEdit = ValueNotifier<int>(0);

class _TodoScreenState extends ConsumerState<TodoScreen> {
  String? _machineId;
  String? _loadedFor;
  final _expanded = <int>{};
  var _completedOpen = false;

  /// The list just became all done (not: it was already): confetti plays.
  bool? _wasAllDone;
  var _celebrating = false;
  var _adding = false;
  final _addController = TextEditingController();
  final _addFocus = FocusNode();

  // Reorder: a drag in progress, where the pointer is, and the cards' keys
  // (to find the hole the neighbours opened, where the accent line goes).
  var _dragging = false;
  var _dragY = 0.0;
  double? _line;
  final _stackKey = GlobalKey();
  final _itemKeys = <int, GlobalKey>{};

  // Inline edit: any field of this screen has the keyboard.
  var _editing = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
  }

  void _focusChanged() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    final editing = ctx != null &&
        ctx.findAncestorWidgetOfExactType<EditableText>() != null &&
        ctx.findAncestorStateOfType<_TodoScreenState>() == this;
    if (editing != _editing && mounted) setState(() => _editing = editing);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  MachineConnection? _conn(List<MachineConnection> all) {
    if (all.isEmpty) return null;
    for (final c in all) {
      if (c.machine.id == _machineId) return c;
    }
    return all.first;
  }

  void _go(NavDest d) => (widget.onNavigate ?? (x) => context.go(x.path))(d);

  void _say(String text, {String? actionLabel, VoidCallback? onAction, Duration? duration}) {
    showHxSnack(
      context,
      text,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  /// Runs a change; tells the person when the computer changed first.
  Future<void> _run(TodoController c, Future<TodoOutcome> Function() change) async {
    final r = await change();
    if (!mounted) return;
    switch (r) {
      case TodoOk():
        break;
      case TodoChanged():
        _say('This list changed on the computer. It was reloaded: try again.');
      case TodoFailed(:final message):
        _say(message);
    }
  }

  Future<void> _delete(TodoController c, int i, [int? j]) async {
    final (r, gone) = await c.delete(i, j);
    if (!mounted) return;
    if (gone == null) {
      if (r is TodoChanged) {
        _say('This list changed on the computer. It was reloaded: try again.');
      } else if (r is TodoFailed) {
        _say(r.message);
      }
      return;
    }
    _say(
      '${gone.isStep ? 'Step' : 'Task'} deleted · ${gone.title}',
      duration: widget.undoFor,
      actionLabel: 'Undo',
      onAction: () => _run(c, () => c.undo(gone)),
    );
  }

  Future<String?> _ask(String title, String hint, {String initial = '', String action = 'Save'}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _lists(TodoController c, TodoState s) async {
    final act = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ListsSheet(state: s, machine: c.conn.machine.name, readOnly: s.offline),
    );
    if (act == null || !mounted) return;
    if (act is TodoIndexEntry) {
      _expanded.clear();
      await c.select(act);
    } else if (act == 'new') {
      final name = await _ask('New list', 'List name', action: 'Create');
      if (name != null && name.trim().isNotEmpty && mounted) {
        _expanded.clear();
        await _run(c, () => c.createList(name));
      }
    } else if (act == 'rename') {
      final name = await _ask('Rename list', 'List name', initial: s.current?.name ?? '');
      if (name != null && name.trim().isNotEmpty && mounted) {
        await _run(c, () => c.renameList(name));
      }
    } else if (act == 'remove') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Remove ${s.current?.name}?'),
          content: const Text(
              'It leaves the list of lists on the computer. Its file is not deleted.'),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        _expanded.clear();
        await _run(c, c.removeList);
      }
    }
  }

  Future<void> _pickMachine(List<MachineConnection> all, MachineConnection current) async {
    final picked = await showModalBottomSheet<MachineConnection>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Which computer', style: HxType.titleSm),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Each computer keeps its own lists.',
                  style: HxType.caption.copyWith(color: ctx.hx.colors.muted)),
            ),
            for (final m in all)
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.computer_outlined),
                title: Text(m.machine.name),
                subtitle: Text(m.machine.online ? 'online' : 'offline · last synced copy'),
                trailing: m.machine.id == current.machine.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _machineId = picked.machine.id;
        _expanded.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(connectionsProvider);
    final conn = _conn(all);
    if (conn == null) {
      return ScreenBody(
        body: Column(
          children: [
            const ScreenHeader(title: 'To-do'),
            Expanded(
              child: _Empty(
                icon: Icons.checklist,
                title: 'No machines yet',
                text: 'Your to-do lists live on your computers. Add one to see them.',
                action: 'Add machine',
                onAction: () => _go(NavDest.machines),
              ),
            ),
          ],
        ),
      );
    }
    final controller = ref.watch(todoControllerProvider(conn.machine.id));
    if (_loadedFor != conn.machine.id) {
      _loadedFor = conn.machine.id;
      Future<void>.microtask(controller.load);
    }
    return ScreenBody(
      body: ValueListenableBuilder<TodoState>(
        valueListenable: controller.value,
        builder: (context, s, _) {
          final wide = MediaQuery.sizeOf(context).width >= kRailBreakpoint;
          final main = _main(context, all, conn, controller, s, wide);
          if (!wide) return main;
          return Row(
            children: [
              SizedBox(width: 300, child: _side(context, all, conn, controller, s)),
              VerticalDivider(width: 1, color: context.hx.colors.hairline),
              Expanded(child: main),
            ],
          );
        },
      ),
    );
  }

  Widget _side(BuildContext context, List<MachineConnection> all, MachineConnection conn,
      TodoController c, TodoState s) {
    final colors = context.hx.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(title: 'To-do'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ComputerChip(
            machine: conn.machine,
            offline: s.offline,
            onTap: all.length > 1 ? () => _pickMachine(all, conn) : null,
          ),
        ),
        const SectionLabel('Lists'),
        Expanded(
          child: ListView(
            children: [
              for (final e in s.lists)
                _SideRow(
                  name: e.name,
                  open: e.slug == s.current?.slug ? s.doc?.list.openCount : null,
                  selected: e.slug == s.current?.slug,
                  onTap: () {
                    _expanded.clear();
                    c.select(e);
                  },
                ),
              Semantics(
                button: true,
                label: 'New list',
                excludeSemantics: true,
                onTap: s.offline ? null : () => _newList(c),
                child: InkWell(
                  onTap: s.offline ? null : () => _newList(c),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(children: [
                        Icon(Icons.add, size: 20, color: s.offline ? colors.dim : colors.accent),
                        const SizedBox(width: 12),
                        Text('New list',
                            style: HxType.body.copyWith(color: s.offline ? colors.dim : colors.accent)),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _newList(TodoController c) async {
    final name = await _ask('New list', 'List name', action: 'Create');
    if (name != null && name.trim().isNotEmpty && mounted) {
      _expanded.clear();
      await _run(c, () => c.createList(name));
    }
  }

  Widget _main(BuildContext context, List<MachineConnection> all, MachineConnection conn,
      TodoController c, TodoState s, bool wide) {
    final colors = context.hx.colors;
    final doc = s.doc;
    final list = doc?.list;
    final open = list?.openCount ?? 0;
    final total = list?.tasks.length ?? 0;
    final done = total - open;
    final allDone = list?.allDone ?? false;
    if (_wasAllDone == false && allDone) _celebrating = true;
    if (!allDone) _celebrating = false;
    if (list != null) _wasAllDone = allDone;
    final subtitle = s.loading && doc == null
        ? '${conn.machine.name} · loading…'
        : '${conn.machine.name} · $open open';

    final title = Expanded(
      child: Semantics(
        button: true,
        label: 'Lists, ${s.current?.name ?? 'none'}',
        excludeSemantics: true,
        onTap: () => _lists(c, s),
        child: InkWell(
          onTap: () => _lists(c, s),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(s.current?.name ?? 'To-do', style: HxType.title),
                  ),
                  Icon(Icons.keyboard_arrow_down, color: colors.muted),
                ]),
                Text(subtitle, style: HxType.mono.copyWith(color: colors.muted)),
              ],
            ),
          ),
        ),
      ),
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          title,
          if (!wide && all.length > 1)
            HxIconButton(
              icon: Icons.computer_outlined,
              label: 'Computer: ${conn.machine.name}',
              onPressed: () => _pickMachine(all, conn),
            ),
        ],
      ),
    );

    final banners = <Widget>[
      if (s.offline)
        _Banner(
          title: '${conn.machine.name} is offline',
          text: 'Read-only copy from the last sync. Ticks and edits wait until it is back.',
          kind: HxBannerKind.offline,
        ),
      if (doc != null && doc.readOnly)
        _Banner(
          title: "This list can't be read",
          text: '${doc.problem} It is left untouched on ${conn.machine.name} and shown read-only.',
          kind: HxBannerKind.error,
        ),
      if (s.error != null)
        _Banner(title: "Couldn't read the lists", text: s.error!, kind: HxBannerKind.error),
    ];

    Widget body;
    if (s.loading && doc == null) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [for (var i = 0; i < 5; i++) const _SkeletonTask()],
      );
    } else if (s.lists.isEmpty) {
      body = ListView(children: [
        ...banners,
        _Empty(
          icon: Icons.checklist,
          title: s.error != null ? 'Nothing to show' : 'No lists on ${conn.machine.name}',
          text: s.error != null
              ? 'Try again when the computer answers.'
              : 'Make your first list here, or in HyperOx on the computer.',
          action: s.offline || s.error != null ? 'Retry' : 'New list',
          onAction: s.offline || s.error != null ? c.load : () => _newList(c),
        ),
      ]);
    } else if (list == null) {
      body = ListView(children: banners);
    } else {
      body = _tasks(context, c, s, list, banners, open, done, total);
    }
    if (!(s.loading && doc == null)) body = HxRefresh(onRefresh: c.load, child: body);

    return PopScope(
      // Back while editing cancels the edit; it does not leave the screen.
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelEdit.value++;
      },
      child: Column(
        children: [
          header,
          Expanded(child: body),
          if (_editing) const _EditBar(),
        ],
      ),
    );
  }

  /// While a card is dragged, measure the hole after every frame: it moves
  /// as the neighbours animate away.
  void _trackLine() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dragging) return;
      final y = _lineTop();
      if (y != _line) setState(() => _line = y);
      WidgetsBinding.instance.scheduleFrame();
      _trackLine();
    });
  }

  /// The y of the accent line: the middle of the hole the neighbours opened
  /// for the dragged card (or just outside the first or last card).
  double? _lineTop() {
    final stack = _stackKey.currentContext?.findRenderObject();
    if (!_dragging || stack is! RenderBox || !stack.hasSize) return null;
    final rects = <Rect>[];
    for (final key in _itemKeys.values) {
      final ctx = key.currentContext;
      final ro = ctx?.findRenderObject();
      // The lifted copy in the overlay is not a card of the list.
      if (ctx == null || _Lifted.of(ctx)) continue;
      if (ro is RenderBox && ro.attached && ro.hasSize) {
        rects.add(stack.globalToLocal(ro.localToGlobal(Offset.zero)) & ro.size);
      }
    }
    if (rects.isEmpty) return null;
    rects.sort((a, b) => a.top.compareTo(b.top));
    var best = 0.0;
    double? at;
    for (var i = 0; i < rects.length - 1; i++) {
      final gap = rects[i + 1].top - rects[i].bottom;
      if (gap > best) {
        best = gap;
        at = rects[i].bottom + gap / 2;
      }
    }
    if (at != null && best > 30) return at - 1.25;
    final y = stack.globalToLocal(Offset(0, _dragY)).dy;
    return y < rects.first.center.dy ? rects.first.top - 3 : rects.last.bottom + 3;
  }

  Widget _tasks(BuildContext context, TodoController c, TodoState s, TodoList list,
      List<Widget> banners, int open, int done, int total) {
    final colors = context.hx.colors;
    final readOnly = s.readOnly;
    final openIdx = [for (var i = 0; i < list.tasks.length; i++) if (!list.tasks[i].done) i];
    final doneIdx = [for (var i = 0; i < list.tasks.length; i++) if (list.tasks[i].done) i];

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...banners,
        if (total > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 5,
                    backgroundColor: colors.well,
                    color: colors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('$done of $total done', style: HxType.mono.copyWith(color: colors.muted)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _AddBar(
            hint: 'Add a task',
            enabled: !readOnly,
            controller: _addController,
            focus: _addFocus,
            adding: _adding,
            onTapStart: () => setState(() => _adding = true),
            onSubmit: (t) {
              _addController.clear();
              _addFocus.requestFocus();
              return _run(c, () => c.addTask(t));
            },
          ),
        ),
        if (total == 0)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              Icon(Icons.edit_note, size: 40, color: colors.muted),
              const SizedBox(height: 8),
              Text('No tasks yet. Add one above.',
                  style: HxType.body.copyWith(color: colors.muted), textAlign: TextAlign.center),
            ]),
          ),
        if (list.allDone)
          Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.check_circle_outline, size: 36, color: colors.accent),
                  const SizedBox(height: 8),
                  Text('All done for today', style: HxType.bodyLg),
                ]),
              ),
              if (_celebrating)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: -160,
                  height: 420,
                  child: IgnorePointer(child: HxConfetti()),
                ),
            ],
          ),
      ],
    );

    final foot = doneIdx.isEmpty
        ? const SizedBox(height: 16)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                label: 'Completed, ${doneIdx.length}',
                hint: _completedOpen ? 'Collapse' : 'Expand',
                excludeSemantics: true,
                onTap: () => setState(() => _completedOpen = !_completedOpen),
                child: InkWell(
                  onTap: () => setState(() => _completedOpen = !_completedOpen),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(children: [
                        Icon(_completedOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                            color: colors.muted),
                        const SizedBox(width: 8),
                        Text('Completed', style: HxType.bodySm.copyWith(color: colors.muted)),
                        const SizedBox(width: 8),
                        _Pill('${doneIdx.length}'),
                      ]),
                    ),
                  ),
                ),
              ),
              if (_completedOpen)
                for (final i in doneIdx)
                  Appear(
                    key: ValueKey('done-row-$i'),
                    animate: true,
                    child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: _TaskCard(
                      key: ValueKey('done-$i'),
                      task: list.tasks[i],
                      index: i,
                      expanded: false,
                      readOnly: readOnly,
                      reorderIndex: null,
                      onToggle: () => _run(c, () => c.setTask(i, false)),
                      onExpand: () {},
                      onStep: (j) => _run(c, () => c.setStep(i, j, !list.tasks[i].steps[j].done)),
                      onRename: (j, t) => _run(c, () => c.rename(i, j, t)),
                      onAddStep: (t) => _run(c, () => c.addStep(i, t)),
                      onDelete: (j) => _delete(c, i, j),
                      onMoveStep: (a, b) => _run(c, () => c.moveStepTo(i, a, b)),
                      onMove: null,
                    ),
                  ),
                  ),
              const SizedBox(height: 16),
            ],
          );

    final accent = colors.accent;
    final reorderable = ReorderableListView(
      buildDefaultDragHandles: false,
      header: head,
      footer: foot,
      // The lifted card: shadow (black 25 %, blur 8, y +8), scale 1.02 and a
      // grip in place of the chevron. Its slot collapses; the neighbours
      // move to make room.
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = Curves.easeOut.transform(animation.value);
          return Transform.scale(
            scale: 1 + 0.02 * t,
            child: Material(
              type: MaterialType.transparency,
              child: _Lifted(child: child),
            ),
          );
        },
      ),
      onReorderStart: (_) {
        setState(() => _dragging = true);
        _trackLine();
      },
      onReorderEnd: (_) => setState(() => _dragging = false),
      onReorder: (a, b) {
        if (readOnly) return;
        if (b > a) b -= 1;
        _run(c, () => c.reorder(a, b));
      },
      children: [
        for (var k = 0; k < openIdx.length; k++)
          Padding(
            key: ValueKey('open-${openIdx[k]}-${list.tasks[openIdx[k]].title}'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: ReorderableDelayedDragStartListener(
              index: k,
              enabled: !readOnly,
              child: _TaskCard(
                key: _itemKeys.putIfAbsent(openIdx[k], GlobalKey.new),
                task: list.tasks[openIdx[k]],
                index: openIdx[k],
                expanded: _expanded.contains(openIdx[k]),
                readOnly: readOnly,
                reorderIndex: k,
                onToggle: () => _run(c, () => c.setTask(openIdx[k], true)),
                onExpand: () => setState(() {
                  final i = openIdx[k];
                  if (!_expanded.remove(i)) _expanded.add(i);
                }),
                onStep: (j) => _run(
                    c, () => c.setStep(openIdx[k], j, !list.tasks[openIdx[k]].steps[j].done)),
                onRename: (j, t) => _run(c, () => c.rename(openIdx[k], j, t)),
                onAddStep: (t) => _run(c, () => c.addStep(openIdx[k], t)),
                onDelete: (j) => _delete(c, openIdx[k], j),
                onMoveStep: (a, b) => _run(c, () => c.moveStepTo(openIdx[k], a, b)),
                onMove: (delta) {
                  final to = k + delta;
                  if (to >= 0 && to < openIdx.length) _run(c, () => c.reorder(k, to));
                },
              ),
            ),
          ),
      ],
    );
    final line = _dragging ? _line : null;
    return Listener(
      onPointerMove: (e) {
        if (_dragging) setState(() => _dragY = e.position.dy);
      },
      child: Stack(
        key: _stackKey,
        children: [
          reorderable,
          if (line != null)
            Positioned(
              top: line,
              left: 16,
              right: 16,
              height: 2.5,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(1.25),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The bar above the keyboard while a title is being edited.
class _EditBar extends StatelessWidget {
  const _EditBar();

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        color: c.chrome,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Done saves · Back cancels',
              style: HxType.mono.copyWith(color: c.muted, fontSize: 12),
            ),
          ),
          Semantics(
            button: true,
            label: 'Done',
            excludeSemantics: true,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: InkWell(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: Container(
                constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
                alignment: Alignment.center,
                child: Text(
                  'Done',
                  style: HxType.weight(HxType.bodyLg, 600).copyWith(color: c.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.well, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: HxType.mono.copyWith(fontSize: 11, color: c.muted)),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.title, required this.text, required this.kind});
  final String title;
  final String text;
  final HxBannerKind kind;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: HxBanner(title: title, message: text, kind: kind),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String text;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: c.muted),
            const SizedBox(height: 16),
            Text(title, style: HxType.titleSm, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text, style: HxType.body.copyWith(color: c.muted), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            HxButton(label: action, kind: HxButtonKind.primary, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}

class _SkeletonTask extends StatelessWidget {
  const _SkeletonTask();

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        label: 'Loading tasks',
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.hairline),
          ),
        ),
      ),
    );
  }
}

class _ComputerChip extends StatelessWidget {
  const _ComputerChip({required this.machine, required this.offline, required this.onTap});
  final MachineInfo machine;
  final bool offline;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Semantics(
      button: onTap != null,
      label: 'Computer: ${machine.name}, ${offline ? 'offline' : 'online'}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Icon(Icons.computer_outlined, size: 20, color: c.foreground),
                const SizedBox(width: 10),
                Flexible(child: Text(machine.name, style: HxType.heading)),
                const SizedBox(width: 8),
                ModeTag(machine.mode),
                const Spacer(),
                Icon(Icons.circle, size: 8, color: offline ? c.muted : c.ok),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({required this.name, required this.open, required this.selected, required this.onTap});
  final String name;
  final int? open;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: open == null ? name : '$name, $open open',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? c.selected : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.checklist, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(name, style: HxType.body)),
            if (open != null) Text('$open open', style: HxType.mono.copyWith(color: c.muted)),
          ]),
        ),
      ),
    );
  }
}

class _ListsSheet extends StatelessWidget {
  const _ListsSheet({required this.state, required this.machine, required this.readOnly});
  final TodoState state;
  final String machine;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    Widget action(IconData icon, String label, Object result, {Color? color}) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          enabled: !readOnly,
          onTap: readOnly ? null : () => Navigator.pop(context, result),
          child: InkWell(
            onTap: readOnly ? null : () => Navigator.pop(context, result),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Row(children: [
                Icon(icon, size: 20, color: readOnly ? c.dim : (color ?? c.foreground)),
                const SizedBox(width: 12),
                Text(label,
                    style: HxType.bodyLg.copyWith(color: readOnly ? c.dim : (color ?? c.foreground))),
              ]),
            ),
          ),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lists', style: HxType.titleSm),
            Text('order from todo/lists.md on $machine',
                style: HxType.mono.copyWith(color: c.muted)),
            const SizedBox(height: 8),
            for (final e in state.lists)
              Semantics(
                button: true,
                selected: e.slug == state.current?.slug,
                label: e.name,
                excludeSemantics: true,
                onTap: () => Navigator.pop(context, e),
                child: InkWell(
                  onTap: () => Navigator.pop(context, e),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Row(children: [
                      SizedBox(
                        width: 28,
                        child: e.slug == state.current?.slug ? const Icon(Icons.check, size: 20) : null,
                      ),
                      Expanded(child: Text(e.name, style: HxType.bodyLg)),
                    ]),
                  ),
                ),
              ),
            Divider(color: c.hairline),
            action(Icons.add, 'New list', 'new'),
            if (state.current != null) action(Icons.edit_outlined, 'Rename list', 'rename'),
            if (state.current != null)
              action(Icons.delete_outline, 'Remove list…', 'remove', color: c.blocked),
          ],
        ),
      ),
    );
  }
}

class _AddBar extends StatelessWidget {
  const _AddBar({
    required this.hint,
    required this.enabled,
    required this.controller,
    required this.focus,
    required this.adding,
    required this.onTapStart,
    required this.onSubmit,
  });

  final String hint;
  final bool enabled;
  final TextEditingController controller;
  final FocusNode focus;
  final bool adding;
  final VoidCallback onTapStart;
  final Future<void> Function(String) onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: adding ? c.accent : c.outline),
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(Icons.add, size: 22, color: enabled ? c.accent : c.dim),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              textField: true,
              label: hint,
              excludeSemantics: true,
              child: TextField(
                controller: controller,
                focusNode: focus,
                enabled: enabled,
                textInputAction: TextInputAction.done,
                onTap: onTapStart,
                onSubmitted: (v) => onSubmit(v),
                style: _hand(18, color: c.foreground),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: _hand(18, color: c.muted),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.done, required this.label, required this.onTap, this.small = false});
  final bool done;
  final String label;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final r = small ? 9.0 : 11.5;
    return Semantics(
      key: ValueKey(label),
      button: true,
      checked: done,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                // Ticking a task gives a light tap.
                if (!done) HapticFeedback.lightImpact();
                onTap!();
              },
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            // The circle fills in 150 ms, then the check draws (200 ms).
            child: AnimatedContainer(
              duration: HxMotion.d(context, const Duration(milliseconds: 150), fade: true),
              curve: HxMotion.standard,
              width: r * 2,
              height: r * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? c.accent : const Color(0x00000000),
                border: Border.all(color: done ? c.accent : c.outline, width: 1.6),
              ),
              child: Center(
                child: DoneCheck(
                  done: done,
                  color: c.accentForeground,
                  size: r * 1.3,
                  delay: const Duration(milliseconds: 150),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A title that edits in place on a double tap: Done or focus loss saves.
class _Title extends StatefulWidget {
  const _Title({
    required this.text,
    required this.size,
    required this.done,
    required this.readOnly,
    required this.onSave,
  });
  final String text;
  final double size;
  final bool done;
  final bool readOnly;
  final void Function(String) onSave;

  @override
  State<_Title> createState() => _TitleState();
}

class _TitleState extends State<_Title> {
  var _editing = false;
  late final _controller = TextEditingController(text: widget.text);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
    _cancelEdit.addListener(_cancel);
  }

  /// Back while editing: drop the typing and leave the title as it was.
  void _cancel() {
    if (!_editing) return;
    _controller.text = widget.text;
    setState(() => _editing = false);
    _focus.unfocus();
  }

  @override
  void dispose() {
    _cancelEdit.removeListener(_cancel);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final v = _controller.text.trim();
    setState(() => _editing = false);
    if (v.isNotEmpty && v != widget.text) widget.onSave(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final style = _hand(widget.size,
        color: widget.done ? c.muted : c.foreground, strike: widget.done, strikeColor: c.muted);
    if (_editing) {
      return TextField(
        controller: _controller,
        focusNode: _focus,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _commit(),
        style: style,
        decoration: const InputDecoration(border: InputBorder.none, isDense: true),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: widget.readOnly
          ? null
          : () {
              _controller.text = widget.text;
              setState(() => _editing = true);
            },
      child: Text(widget.text, style: style),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    super.key,
    required this.task,
    required this.index,
    required this.expanded,
    required this.readOnly,
    required this.reorderIndex,
    required this.onToggle,
    required this.onExpand,
    required this.onStep,
    required this.onRename,
    required this.onAddStep,
    required this.onDelete,
    required this.onMoveStep,
    required this.onMove,
  });

  final TodoTask task;
  final int index;
  final bool expanded;
  final bool readOnly;
  final int? reorderIndex;
  final VoidCallback onToggle;
  final VoidCallback onExpand;
  final void Function(int step) onStep;
  final void Function(int? step, String title) onRename;
  final void Function(String title) onAddStep;
  final void Function(int? step) onDelete;
  final void Function(int from, int to) onMoveStep;
  final void Function(int delta)? onMove;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final steps = task.steps;
    final doneSteps = steps.where((s) => s.done).length;
    final scale = MediaQuery.textScalerOf(context).scale(18) / 18;
    final big = scale >= 1.5;
    final lifted = _Lifted.of(context);
    final card = Builder(builder: (context) => Focus(
      canRequestFocus: false,
      skipTraversal: true,
      child: Builder(builder: (context) {
      // The row being edited has a 1.5 dp accent edge.
      final editing = Focus.of(context).hasFocus;
      return Container(
      constraints: BoxConstraints(minHeight: big ? 56 : 52),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: editing ? c.accent : c.hairline,
          width: editing ? 1.5 : 1,
        ),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Tick(
                done: task.done,
                label: task.done ? 'Mark not done: ${task.title}' : 'Mark done: ${task.title}',
                onTap: readOnly ? null : onToggle,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _Title(
                    text: task.title,
                    size: 18,
                    done: task.done,
                    readOnly: readOnly,
                    onSave: (t) => onRename(null, t),
                  ),
                ),
              ),
              if (steps.isNotEmpty) _Pill('$doneSteps/${steps.length}'),
              Semantics(
                button: true,
                label: expanded ? 'Hide steps of ${task.title}' : 'Show steps of ${task.title}',
                excludeSemantics: true,
                onTap: onExpand,
                child: InkWell(
                  onTap: onExpand,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: lifted
                        ? HxIcon('grip', size: 20, color: c.muted)
                        : Icon(
                            expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                            color: c.muted,
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 8),
              child: Container(
                decoration: BoxDecoration(border: Border(left: BorderSide(color: c.hairline))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < steps.length; j++)
                      _StepRow(
                        key: ValueKey('step-$index-$j-${steps[j].title}'),
                        step: steps[j],
                        readOnly: readOnly,
                        onTick: () => onStep(j),
                        onRename: (t) => onRename(j, t),
                        onDelete: () => onDelete(j),
                        onUp: j > 0 ? () => onMoveStep(j, j - 1) : null,
                        onDown: j < steps.length - 1 ? () => onMoveStep(j, j + 1) : null,
                      ),
                    if (!readOnly) _AddStep(onAdd: onAddStep),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    }),
    ));

    final actions = <CustomSemanticsAction, VoidCallback>{
      if (!readOnly) const CustomSemanticsAction(label: 'Delete task'): () => onDelete(null),
      if (!readOnly && onMove != null) ...{
        const CustomSemanticsAction(label: 'Move up'): () => onMove!(-1),
        const CustomSemanticsAction(label: 'Move down'): () => onMove!(1),
      },
    };
    final wrapped = Semantics(
      container: true,
      customSemanticsActions: actions,
      child: card,
    );
    if (readOnly) return wrapped;
    return Dismissible(
      key: ValueKey('dismiss-$index-${task.title}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        // The row leaves when the file has been rewritten and the list
        // rebuilt, not before: so it never completes the dismissal itself.
        onDelete(null);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: c.blocked, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: wrapped,
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    super.key,
    required this.step,
    required this.readOnly,
    required this.onTick,
    required this.onRename,
    required this.onDelete,
    required this.onUp,
    required this.onDown,
  });

  final TodoStep step;
  final bool readOnly;
  final VoidCallback onTick;
  final void Function(String) onRename;
  final VoidCallback onDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final row = Semantics(
      container: true,
      customSemanticsActions: {
        if (!readOnly) const CustomSemanticsAction(label: 'Delete step'): onDelete,
        if (!readOnly && onUp != null) const CustomSemanticsAction(label: 'Move up'): onUp!,
        if (!readOnly && onDown != null) const CustomSemanticsAction(label: 'Move down'): onDown!,
      },
      child: Row(
        children: [
          _Tick(
            done: step.done,
            small: true,
            label: step.done ? 'Mark step not done: ${step.title}' : 'Mark step done: ${step.title}',
            onTap: readOnly ? null : onTick,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _Title(
                text: step.title,
                size: 16.5,
                done: step.done,
                readOnly: readOnly,
                onSave: onRename,
              ),
            ),
          ),
        ],
      ),
    );
    if (readOnly) return row;
    return Dismissible(
      key: ValueKey('dismiss-${step.title}-${identityHashCode(step)}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: context.hx.colors.blocked,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: row,
    );
  }
}

class _AddStep extends StatefulWidget {
  const _AddStep({required this.onAdd});
  final void Function(String) onAdd;

  @override
  State<_AddStep> createState() => _AddStepState();
}

class _AddStepState extends State<_AddStep> {
  var _open = false;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    if (_open) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.done,
          style: _hand(16.5, color: c.foreground),
          decoration: InputDecoration(
            hintText: 'Add step',
            hintStyle: _hand(16.5, color: c.muted),
            border: InputBorder.none,
          ),
          onSubmitted: (v) {
            widget.onAdd(v);
            _controller.clear();
            _focus.requestFocus();
          },
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Add step',
      excludeSemantics: true,
      onTap: () => setState(() => _open = true),
      child: InkWell(
        onTap: () => setState(() => _open = true),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.add, size: 18, color: c.muted),
              const SizedBox(width: 10),
              Text('Add step', style: _hand(16.5, color: c.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
