import 'dart:async';
import 'dart:convert';

import '../machine_connection.dart';
import 'core_probe.dart';
import 'core_rpc.dart';
import 'known_hosts.dart';
import 'ssh_keys.dart';
import 'ssh_transport.dart';

const missingCoreMessage = 'HyperOx core (h0x-core) was not found on this machine. '
    'If it is installed somewhere unusual, set its path under Advanced.';
const bannerMessage = 'the login prints text; see docs/machines.md';

class SshTarget {
  const SshTarget({
    required this.id,
    required this.name,
    required this.host,
    required this.username,
    this.port = 22,
    this.useKey = true,
    this.corePath = '',
  });
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;

  /// False for Tailscale SSH: no key is offered, the tailnet authorises.
  final bool useKey;

  /// Where h0x-core is on that machine when it is not in the usual places; '' = search.
  final String corePath;
}

/// 1, 2, 4, 8, 16, 30, 30... seconds.
class Backoff {
  static const steps = [1, 2, 4, 8, 16, 30];
  var _i = 0;
  Duration next() => Duration(seconds: steps[_i < steps.length - 1 ? _i++ : _i]);
  void reset() => _i = 0;
}

class _OpenCore {
  _OpenCore(this.rpc, this.windows);
  final CoreRpc rpc;
  final bool windows;
}

/// MachineConnection over SSH: `h0x-core connect` in an exec channel, spoken to
/// with [CoreRpc]. There is no bridge on this path (an SSH login is already
/// full control); only the bridge's approve/deny rule is kept here, and kill
/// and run ask for confirmation on the client.
class SshMachineConnection implements MachineConnection {
  SshMachineConnection({
    required this.target,
    required SshTransportFactory transport,
    required KnownHosts knownHosts,
    required SshKeys keys,
    Future<void> Function(Duration) delay = _realDelay,
    this.readyTimeout = const Duration(seconds: 10),
  })  : _factory = transport,
        _known = knownHosts,
        _keys = keys,
        _delay = delay;

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

  final SshTarget target;
  final SshTransportFactory _factory;
  final KnownHosts _known;
  final SshKeys _keys;
  final Future<void> Function(Duration) _delay;
  final Duration readyTimeout;

  final _state = StreamController<ConnState>.broadcast(sync: true);
  final _backoff = Backoff();
  ConnState _last = const Connecting();
  CoreRpc? _rpc;
  SshTransport? _transport;
  bool _windows = false;
  String _os = 'unknown';
  bool _closing = false;
  bool _fatal = false;
  bool _started = false;
  Completer<ConnState>? _first;
  final _pending = <String, Future<Reply> Function()>{};
  var _tokens = 0;

  Completer<bool>? _decision;
  bool _decisionIsChange = false;

  @override
  MachineInfo get machine => MachineInfo(
        id: target.id,
        name: target.name,
        os: _os,
        mode: ConnMode.ssh,
        online: _last is Ready,
      );

  /// The current state first, then every change.
  @override
  Stream<ConnState> get state => Stream<ConnState>.multi((c) {
        c.add(_last);
        final sub = _state.stream.listen(c.add, onDone: c.close);
        c.onCancel = sub.cancel;
      });

  void _emit(ConnState s) {
    _last = s;
    if (!_state.isClosed) _state.add(s);
  }

  // ---- connecting ----

  /// Starts connecting (once) and returns the first settled state: [Ready] or
  /// [Failed]. A host key waiting for the user does not settle it; watch [state].
  Future<ConnState> start() {
    final first = _first ??= Completer<ConnState>();
    if (!_started) {
      _started = true;
      unawaited(_loop());
    }
    return first.future;
  }

  void _settle(ConnState s) {
    final f = _first;
    if (f != null && !f.isCompleted) f.complete(s);
  }

  Future<void> _loop() async {
    while (!_closing) {
      _emit(const Connecting());
      try {
        await _session();
        if (_closing) return;
        _emit(const Failed('connection lost'));
      } on SshFatal catch (e) {
        _fatal = true;
        _emit(e is SshCoreMissing ? CoreMissing(e.message) : Failed(e.message));
        _settle(_last);
        await _transport?.close();
        return;
      } catch (e) {
        if (_closing) return;
        _emit(Failed('cannot connect: $e'));
        _settle(_last);
      }
      _rpc = null;
      await _transport?.close();
      if (_closing) return;
      await _delay(_backoff.next());
    }
  }

  Future<void> _session() async {
    final key = target.useKey ? (await _keys.ensure()).key : null;
    final t = _transport = _factory(
      host: target.host,
      port: target.port,
      username: target.username,
      key: key,
      verify: _verify,
    );
    await t.connect();
    final core = await _openCore(t);
    _rpc = core.rpc;
    _windows = core.windows;
    _os = core.windows ? 'windows' : 'unix';
    _backoff.reset();
    _emit(const Ready());
    _settle(_last);
    await Future.any([core.rpc.closed, t.done]);
    await core.rpc.close();
  }

  FoundCore? _found;
  var _shell = WindowsShell.unknown;

  /// The command that starts core with [args] on this machine.
  String _coreCommand(String args) {
    final f = _found;
    if (!_windows) return unixCommand(args, override: target.corePath);
    return windowsRunCommand(f!, args, shell: _shell);
  }

  /// Unix first (one command that looks in the usual places and starts the
  /// core). If the login shell is Windows' (cmd or PowerShell), a probe finds
  /// the core and a second command starts it. Tells a missing core, a chatty
  /// login and a protocol mismatch apart.
  Future<_OpenCore> _openCore(SshTransport t) async {
    final unix = await _tryCore(t, unixCommand('connect', override: target.corePath), windows: false);
    if (unix.core != null) return unix.core!;
    // Not the unix shell's answer: this is a Windows login.
    _shell = windowsShellFrom(unix.stderr);
    final probe = await t.exec(windowsProbeCommand(override: target.corePath));
    final out = readAll(probe.input);
    final err = readAll(probe.stderr);
    await probe.exitCode(timeout: const Duration(seconds: 15));
    final found = parseWindowsProbe(await out.timeout(const Duration(seconds: 15), onTimeout: () => ''));
    await err.timeout(const Duration(seconds: 1), onTimeout: () => '');
    await probe.close();
    if (found == null) throw SshCoreMissing(missingCoreMessage);
    _found = found;
    final win = await _tryCore(t, windowsRunCommand(found, 'connect', shell: _shell), windows: true);
    if (win.core != null) return win.core!;
    throw win.fatal ?? SshFatal('could not start h0x-core');
  }

  Future<({_OpenCore? core, SshFatal? fatal, String stderr})> _tryCore(
    SshTransport t,
    String command, {
    required bool windows,
  }) async {
    final proc = await t.exec(command);
    final stderr = readAll(proc.stderr);
    final rpc = CoreRpc(proc);
    try {
      await rpc.hello();
      return (core: _OpenCore(rpc, windows), fatal: null, stderr: '');
    } on CoreRpcException catch (e) {
      await rpc.close();
      throw SshFatal(e.kind == 'unsupported_generation'
          ? "this machine's h0x-core speaks another protocol generation; update it"
          : 'h0x-core refused: ${e.message}');
    } on CoreProtocolException catch (e) {
      await rpc.close();
      final code = await proc.exitCode(timeout: const Duration(milliseconds: 500));
      final err = await stderr.timeout(const Duration(seconds: 1), onTimeout: () => '');
      if (err.contains(coreNotHere) || code == 127) throw SshCoreMissing(missingCoreMessage);
      if (!windows && windowsShellFrom(err) != WindowsShell.unknown) {
        // the login shell is Windows': the caller probes
        return (core: null, fatal: null, stderr: err);
      }
      if (e.banner && code == null) throw SshFatal(bannerMessage);
      final said = err.trim().isEmpty ? e.message : err.trim();
      if (!windows) throw SshFatal('could not start h0x-core: $said');
      return (core: null, fatal: SshFatal('could not start h0x-core: $said'), stderr: err);
    }
  }

  // ---- host keys (trust on first use) ----

  Future<bool> _verify(String type, String fingerprint) async {
    switch (await _known.check(target.host, target.port, fingerprint)) {
      case HostKeyCheck.match:
        return true;
      case HostKeyCheck.unknown:
        _decisionIsChange = false;
        _emit(HostKeyNew(fingerprint));
      case HostKeyCheck.mismatch:
        _decisionIsChange = true;
        _emit(HostKeyChanged(
          known: await _known.lookup(target.host, target.port) ?? '',
          offered: fingerprint,
        ));
    }
    final d = _decision = Completer<bool>();
    final ok = await d.future;
    _decision = null;
    if (ok) {
      await _known.trust(target.host, target.port, fingerprint);
      _emit(const Connecting());
    }
    return ok;
  }

  /// The user accepts a first-seen host key. Ignored for a changed key.
  void acceptHostKey() {
    if (!_decisionIsChange) _decision?.complete(true);
  }

  /// The user explicitly replaces a changed host key. Ignored for a new key.
  void replaceHostKey() {
    if (_decisionIsChange) _decision?.complete(true);
  }

  void rejectHostKey() => _decision?.complete(false);

  // ---- calls ----

  Future<CoreRpc> _ready() async {
    if (_last is! Ready) {
      // A Failed state ends the wait only when no reconnect follows.
      await state.firstWhere((s) => s is Ready || (s is Failed && _fatal)).timeout(
            readyTimeout,
            onTimeout: () => throw StateError('not connected: ${_describeState()}'),
          );
    }
    final rpc = _rpc;
    if (rpc == null || _last is! Ready) throw StateError('not connected: ${_describeState()}');
    return rpc;
  }

  String _describeState() => switch (_last) {
        Failed(:final reason) => reason,
        HostKeyNew() || HostKeyChanged() => 'waiting for the host key decision',
        _ => 'connecting',
      };

  Future<Reply> _reply(Future<Object?> Function(CoreRpc rpc) f) async {
    try {
      final r = await f(await _ready());
      return Done(r is Map ? r.cast<String, Object?>() : const {});
    } on CoreRpcException catch (e) {
      return ReplyFailed(e.hint.isEmpty ? e.message : '${e.message} (${e.hint})');
    } on CoreProtocolException catch (e) {
      return ReplyFailed('connection lost: ${e.message}');
    } on StateError catch (e) {
      return ReplyFailed(e.message);
    }
  }

  static Session _toSession(Map<String, dynamic> t) {
    final st = (t['status'] as Map?)?.cast<String, dynamic>();
    final fg = (t['foreground'] as Map?)?.cast<String, dynamic>();
    final argv = (t['argv'] as List?)?.cast<String>() ?? const [];
    final app = (st?['app'] as String?)?.trim() ?? '';
    final agent = app.isNotEmpty
        ? app
        : (t['template'] as String?) ??
            (fg?['name'] as String?) ??
            (argv.isNotEmpty ? argv.first : '');
    final address = t['address'] as String? ?? '';
    return Session(
      terminal: address,
      name: (t['name'] as String?) ?? address,
      agent: agent,
      folder: (t['cwd'] as String?) ?? '',
      status: (st?['state'] as String?) ?? '',
      live: t['state'] == 'live',
      blockedKind: st?['kind'] as String?,
      message: (st?['msg'] as String?) ?? '',
    );
  }

  @override
  Future<List<Session>> sessions() async {
    final r = await (await _ready()).call('terminal.list') as Map;
    return [for (final t in (r['terminals'] as List)) _toSession((t as Map).cast<String, dynamic>())];
  }

  @override
  Future<String> read(String terminal, {int lines = 50}) async {
    final r = await (await _ready()).call('terminal.read', {'terminal': terminal, 'lines': lines})
        as Map;
    return r['text'] as String? ?? '';
  }

  @override
  Future<Reply> send(String terminal, String text) =>
      _reply((c) => c.call('terminal.send', {'terminal': terminal, 'text': text}));

  @override
  Future<Reply> keys(String terminal, List<Key> keys) => _reply(
      (c) => c.call('terminal.keys', {'terminal': terminal, 'keys': [for (final k in keys) k.name]}));

  /// The bridge's rule: only a blocked permission can be answered; anything
  /// else (a question, auth, a working agent) is refused.
  Future<Reply> _answer(String terminal, Key key) async {
    try {
      final t = await (await _ready()).call('terminal.get', {'terminal': terminal}) as Map;
      final s = _toSession(t.cast<String, dynamic>());
      if (s.status != 'blocked' || s.blockedKind != 'permission') {
        final what = s.status == 'blocked' ? 'a ${s.blockedKind ?? 'blocked'} prompt' : s.status;
        return ReplyFailed('refused: only a blocked permission can be approved or denied (this is $what)');
      }
    } on CoreRpcException catch (e) {
      return ReplyFailed(e.message);
    } on CoreProtocolException catch (e) {
      return ReplyFailed('connection lost: ${e.message}');
    } on StateError catch (e) {
      return ReplyFailed(e.message);
    }
    return keys(terminal, [key]);
  }

  @override
  Future<Reply> approve(String terminal) => _answer(terminal, Key.enter);

  @override
  Future<Reply> deny(String terminal) => _answer(terminal, Key.esc);

  @override
  Future<Reply> interrupt(String terminal) =>
      _reply((c) => c.call('terminal.interrupt', {'terminal': terminal}));

  Reply _confirmLater(String what, Future<Reply> Function() action) {
    final token = 'c${++_tokens}';
    _pending[token] = action;
    return NeedsConfirm(token, what);
  }

  @override
  Future<Reply> kill(String terminal) async => _confirmLater(
      'kill $terminal', () => _reply((c) => c.call('terminal.kill', {'terminal': terminal})));

  /// [folder] is passed to core unchanged (`C:\Users\x\proj` stays as given).
  @override
  Future<Reply> run(String folder, String command) async => _confirmLater(
      'run "$command" in $folder',
      () => _reply((c) => c.call('terminal.run', {'line': command, 'cwd': folder})));

  @override
  Future<Reply> confirm(String token) async {
    final action = _pending.remove(token);
    if (action == null) return const ReplyFailed('unknown or already used confirmation');
    return action();
  }

  // ---- files ----

  String? _home;

  @override
  Future<String> appHome() async {
    final cached = _home;
    if (cached != null) return cached;
    final rpc = await _ready();
    final line = _windows
        ? r'if defined H0X_ADE_HOME (echo %H0X_ADE_HOME%) else if defined XDG_CONFIG_HOME '
              r'(echo %XDG_CONFIG_HOME%\h0x-ade) else (echo %USERPROFILE%\.config\h0x-ade)'
        : r'printf %s "${H0X_ADE_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/h0x-ade}"';
    final r = await rpc.call('machine.exec', {'line': line}) as Map<String, dynamic>;
    final out = utf8.decode(base64.decode(r['stdout'] as String? ?? ''), allowMalformed: true).trim();
    if (r['code'] != 0 || out.isEmpty) {
      throw StateError('cannot find the app folder on ${target.name}');
    }
    return _home = out;
  }

  @override
  Future<String?> readFile(String path) async {
    final rpc = await _ready();
    final text = StringBuffer();
    var offset = 1;
    // core may give a long file in several parts, whole lines each
    while (true) {
      final Map<String, dynamic> r;
      try {
        r = await rpc.call('file.read', {'path': path, 'offset': offset}) as Map<String, dynamic>;
      } on CoreRpcException catch (e) {
        if (e.kind == 'not_found') return null;
        rethrow;
      }
      text.write(r['text'] as String? ?? '');
      final last = r['last'] as int? ?? 0;
      if (last >= (r['lines'] as int? ?? 0)) break;
      offset = last + 1;
    }
    return text.toString();
  }

  @override
  Future<void> writeFile(String path, String text) async {
    await (await _ready()).call('file.write', {
      'path': path,
      'data': base64.encode(utf8.encode(text)),
    });
  }

  // ---- spaces: a second exec (core's bridge keeps them) ----

  @override
  Future<SpacesView> spaces() async {
    await _ready();
    final t = _transport!;
    final proc = await t.exec(
        _coreCommand('bridge spaces --show --json'));
    final out = readAll(proc.input);
    final err = readAll(proc.stderr);
    final code = await proc.exitCode(timeout: const Duration(seconds: 15));
    final text = (await out).trim();
    final errText = (await err).trim();
    if (code != null && code != 0) {
      // an h0x-core without `bridge spaces --show`
      final old = errText.contains('unrecognized') ||
          errText.contains('unexpected argument') ||
          errText.contains('unknown');
      if (old) return const SpacesView.unsupported();
      throw StateError('spaces: ${errText.isEmpty ? 'exit $code' : errText}');
    }
    if (text.isEmpty || text == 'null') return const SpacesView();
    return SpacesView.fromJson(jsonDecode(text));
  }

  // ---- streams ----

  @override
  Future<TermSize> size(String terminal) async {
    final t = await (await _ready()).call('terminal.get', {'terminal': terminal}) as Map;
    final cols = t['cols'], rows = t['rows'];
    if (cols is! int || rows is! int) throw StateError('core gave no size for $terminal');
    return TermSize(cols, rows);
  }

  /// Watch only: core sends the terminal's own size (we pass 80x24 as the
  /// viewer size, which an observer never applies) and RESIZE frames.
  @override
  Future<TermView> view(String terminal, {int history = 5000}) async {
    final a = await (await _ready()).attach(
      terminal: terminal,
      cols: 80,
      rows: 24,
      history: history,
    );
    return TermView(initial: a.initial, bytes: a.data, sizes: a.sizes, close: a.close);
  }

  @override
  Stream<Notice> notices() {
    late StreamController<Notice> c;
    var active = false;
    c = StreamController<Notice>(
      onListen: () {
        active = true;
        unawaited(_watchEvents(() => active, c));
      },
      onCancel: () => active = false,
    );
    return c.stream;
  }

  Future<void> _watchEvents(bool Function() active, StreamController<Notice> c) async {
    while (active() && !_closing) {
      try {
        final sub = await (await _ready()).subscribe();
        await for (final e in sub.events) {
          if (!active()) break;
          final n = await _notice(e);
          if (n != null && !c.isClosed) c.add(n);
        }
        await sub.close();
      } catch (_) {
        // the link dropped: wait for the reconnect below
      }
      if (!active() || _closing) break;
      await _delay(const Duration(seconds: 1));
    }
  }

  /// A status change to blocked, done or error, or a finished terminal.
  Future<Notice?> _notice(RpcNotification e) async {
    if (e.method != 'event') return null;
    final address = e.params['terminal'] as String?;
    if (address == null) return null;
    final data = (e.params['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    String kind;
    String excerpt = '';
    switch (e.params['type']) {
      case 'status':
        final st = (data['status'] as Map?)?.cast<String, dynamic>();
        kind = switch (st?['state']) {
          'blocked' => 'needs_you',
          'done' => 'done',
          'error' => 'error',
          _ => '',
        };
        excerpt = (st?['msg'] as String?) ?? '';
      case 'finished':
        kind = 'finished';
      default:
        return null;
    }
    if (kind.isEmpty) return null;
    var agent = '';
    var folder = '';
    try {
      final t = await (await _ready()).call('terminal.get', {'terminal': address}) as Map;
      final s = _toSession(t.cast<String, dynamic>());
      agent = s.agent;
      folder = s.folder;
    } catch (_) {
      // the notice still goes out, without the extras
    }
    return Notice(terminal: address, agent: agent, folder: folder, kind: kind, excerpt: excerpt);
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    rejectHostKey();
    _settle(const Failed('closed'));
    await _rpc?.close();
    await _transport?.close();
    _rpc = null;
    await _state.close();
  }
}
