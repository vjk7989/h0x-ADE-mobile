import 'dart:async';

import 'package:hyperox/conn/machine_connection.dart';

/// An in-memory MachineConnection for screen and contract tests. It holds the
/// contract fixture: t1 working, t2 blocked on a permission, t3 blocked on a
/// question; reading t1 gives "hello t1".
class FakeConnection implements MachineConnection {
  FakeConnection({
    this.mode = ConnMode.ssh,
    this.id = 'fake',
    this.name = 'fake',
    Map<String, Session>? sessions,
  }) {
    if (sessions != null) live = sessions;
  }

  final ConnMode mode;
  final String id;
  final String name;
  ConnState _last = const Ready();
  final _state = StreamController<ConnState>.broadcast(sync: true);
  final _notices = StreamController<Notice>.broadcast(sync: true);
  final _views = <String, StreamController<List<int>>>{};
  final _pending = <String, String>{};
  final log = <String>[];
  var _tokens = 0;
  var closed = false;

  var live = <String, Session>{
    't1': const Session(
        terminal: 't1', name: 'build', agent: 'claude', folder: '/srv/a', status: 'working', live: true),
    't2': const Session(
        terminal: 't2',
        name: 'perm',
        agent: 'codex',
        folder: '/srv/b',
        status: 'blocked',
        live: true,
        blockedKind: 'permission'),
    't3': const Session(
        terminal: 't3',
        name: 'ask',
        agent: 'claude',
        folder: '/srv/c',
        status: 'blocked',
        live: true,
        blockedKind: 'question'),
  };

  @override
  MachineInfo get machine =>
      MachineInfo(id: id, name: name, os: 'linux', mode: mode, online: !closed && _last is Ready);

  @override
  Stream<ConnState> get state => Stream<ConnState>.multi((c) {
        c.add(_last);
        final sub = _state.stream.listen(c.add, onDone: c.close);
        c.onCancel = sub.cancel;
      });

  void setState(ConnState s) {
    _last = s;
    _state.add(s);
  }

  void emitNotice(Notice n) => _notices.add(n);

  void emitView(String terminal, List<int> bytes) => _views[terminal]?.add(bytes);

  @override
  Future<List<Session>> sessions() async => live.values.toList();

  /// What spaces() gives (tests replace it); [spacesError] makes it throw.
  SpacesView spacesView = const SpacesView(
    spaces: [
      Space(name: 'app', folder: '/srv/a', tabs: [
        SpaceTab(name: 'main', panes: ['build'])
      ])
    ],
    agents: [AgentSlot(slot: 1, name: 'claude', command: 'claude')],
  );
  Object? spacesError;

  @override
  Future<SpacesView> spaces() async {
    if (spacesError != null) throw spacesError!;
    return spacesView;
  }

  Reply _unknown(String t) => ReplyFailed('no such terminal: $t');

  @override
  Future<String> read(String terminal, {int lines = 50}) async {
    if (!live.containsKey(terminal)) throw StateError('no such terminal: $terminal');
    return 'hello $terminal';
  }

  @override
  Future<Reply> send(String terminal, String text) async {
    if (!live.containsKey(terminal)) return _unknown(terminal);
    log.add('send $terminal $text');
    return const Done();
  }

  @override
  Future<Reply> keys(String terminal, List<Key> keys) async {
    if (!live.containsKey(terminal)) return _unknown(terminal);
    log.add('keys $terminal ${keys.map((k) => k.name).join(',')}');
    return const Done();
  }

  Future<Reply> _answer(String terminal, Key key) async {
    final s = live[terminal];
    if (s == null) return _unknown(terminal);
    if (s.status != 'blocked' || s.blockedKind != 'permission') {
      return const ReplyFailed('only a blocked permission can be approved or denied');
    }
    return keys(terminal, [key]);
  }

  @override
  Future<Reply> approve(String terminal) => _answer(terminal, Key.enter);

  @override
  Future<Reply> deny(String terminal) => _answer(terminal, Key.esc);

  @override
  Future<Reply> interrupt(String terminal) async {
    if (!live.containsKey(terminal)) return _unknown(terminal);
    log.add('interrupt $terminal');
    return const Done();
  }

  Reply _confirmLater(String what, String action) {
    final token = 'c${++_tokens}';
    _pending[token] = action;
    return NeedsConfirm(token, what);
  }

  @override
  Future<Reply> kill(String terminal) async {
    if (!live.containsKey(terminal)) return _unknown(terminal);
    return _confirmLater('kill $terminal', 'kill $terminal');
  }

  @override
  Future<Reply> run(String folder, String command) async =>
      _confirmLater('run $command in $folder', 'run $folder $command');

  @override
  Future<Reply> confirm(String token) async {
    final action = _pending.remove(token);
    if (action == null) return const ReplyFailed('unknown or used token');
    log.add(action);
    if (action.startsWith('kill ')) live = {...live}..remove(action.substring(5));
    return const Done();
  }

  @override
  Future<TermSize> size(String terminal) async {
    if (!live.containsKey(terminal)) throw StateError('no such terminal: $terminal');
    return const TermSize(80, 24);
  }

  final _sizes = <String, StreamController<TermSize>>{};

  void emitSize(String terminal, TermSize s) => _sizes[terminal]?.add(s);

  @override
  Future<TermView> view(String terminal, {int history = 5000}) async {
    if (!live.containsKey(terminal)) throw StateError('no such terminal: $terminal');
    final bytes = StreamController<List<int>>(onCancel: () => _views.remove(terminal));
    final sizes = StreamController<TermSize>();
    _views[terminal] = bytes;
    _sizes[terminal] = sizes;
    return TermView(
      initial: const TermSize(80, 24),
      bytes: bytes.stream,
      sizes: sizes.stream,
      close: () async {
        _views.remove(terminal);
        _sizes.remove(terminal);
        // not awaited: close() of a stream nobody listens to never completes
        unawaited(bytes.close());
        unawaited(sizes.close());
      },
    );
  }

  @override
  Stream<Notice> notices() => _notices.stream;

  /// The machine's files, by absolute path.
  final files = <String, String>{};
  var writes = 0;
  Object? writeError;

  /// Called before each read (tests change a file "on the computer" here).
  void Function(String path)? onRead;

  @override
  Future<String> appHome() async => '/home/me/.config/h0x-ade';

  @override
  Future<String?> readFile(String path) async {
    onRead?.call(path);
    return files[path];
  }

  @override
  Future<void> writeFile(String path, String text) async {
    if (writeError != null) throw writeError!;
    writes++;
    files[path] = text;
  }

  @override
  Future<void> close() async {
    closed = true;
    for (final v in _views.values) {
      await v.close();
    }
    await _notices.close();
    await _state.close();
  }
}
