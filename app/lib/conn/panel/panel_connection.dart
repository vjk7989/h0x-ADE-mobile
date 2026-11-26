import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show SHA256Digest;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/panel_machines_repo.dart';
import '../machine_connection.dart';
import '../ssh/ssh_connection.dart' show Backoff;
import 'e2e.dart';
import 'panel_link.dart';

/// The server refuses anything larger than this, both ways (core bridge docs).
const panelMaxFrame = 64 * 1024;

/// The server hello is about 300 bytes; the core accepts at most 1 KB.
const panelMaxHello = 1024;

/// Lowercase hex SHA-256 of the UTF-8 text: what `approve` carries so core
/// can refuse when the prompt is no longer the one the phone showed.
String promptSha256(String prompt) => SHA256Digest()
    .process(Uint8List.fromList(utf8.encode(prompt)))
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// A text frame (the hello) or a binary frame (everything after it).
abstract class PanelSocket {
  Stream<Object?> get messages;
  void send(Object data);
  Future<void> close();
}

typedef PanelConnector = Future<PanelSocket> Function(Uri url);

class _ChannelSocket implements PanelSocket {
  _ChannelSocket(this._ch);
  final WebSocketChannel _ch;

  @override
  Stream<Object?> get messages => _ch.stream;

  @override
  void send(Object data) => _ch.sink.add(data);

  @override
  Future<void> close() => _ch.sink.close();
}

Future<PanelSocket> connectPanelSocket(Uri url) async {
  final ch = WebSocketChannel.connect(url);
  await ch.ready;
  return _ChannelSocket(ch);
}

Uri _wsUrl(String baseUrl) {
  final u = Uri.parse(baseUrl);
  return Uri(scheme: 'wss', host: u.host, port: u.hasPort ? u.port : null, path: '/ws');
}

/// One sealed connection: the handshake is done, [messages] are decrypted
/// JSON objects. Any bad frame (replayed, out of order, too big, text after
/// the hello) ends it with an error.
class _Wire {
  _Wire._(this._socket, this._chan, this._fp);
  final PanelSocket _socket;
  final PanelChannel _chan;
  final String _fp;
  final _in = StreamController<Map<String, dynamic>>();
  final _hello = Completer<void>();
  StreamSubscription<Object?>? _sub;
  bool _accepted = false;

  Stream<Map<String, dynamic>> get messages => _in.stream;

  static Future<_Wire> open(
    Uri url,
    String fp,
    Uint8List deviceSecret,
    PanelConnector connect,
    Duration timeout,
  ) async {
    final sock = await connect(url).timeout(timeout);
    final w = _Wire._(sock, PanelChannel.start(deviceSecret), fp);
    w._sub = sock.messages.listen(w._onData, onError: w._fail, onDone: w._done);
    try {
      sock.send(w._chan.clientHello);
      await w._hello.future.timeout(timeout);
    } catch (_) {
      await w.close();
      rethrow;
    }
    return w;
  }

  void _onData(Object? data) {
    if (!_accepted) {
      if (data is! String) return _fail(const PanelE2eError('binary before hello'));
      if (data.length > panelMaxHello) return _fail(const PanelE2eError('hello too large'));
      try {
        _chan.accept(data, _fp);
      } catch (e) {
        return _fail(e);
      }
      _accepted = true;
      _hello.complete();
      return;
    }
    if (data is! List<int>) return _fail(const PanelE2eError('text after hello'));
    if (data.length > panelMaxFrame) return _fail(const PanelE2eError('frame too large'));
    try {
      _in.add(_chan.open(data));
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object e) {
    if (!_hello.isCompleted) _hello.completeError(e);
    if (!_in.isClosed) {
      _in.addError(e);
      _in.close();
    }
    unawaited(close());
  }

  void _done() {
    if (!_hello.isCompleted) _hello.completeError(StateError('closed before the handshake'));
    if (!_in.isClosed) _in.close();
  }

  void send(String name, Map<String, Object?> data) {
    final bytes = utf8.encode(jsonEncode({'name': name, 'data': data}));
    if (bytes.length + 16 > panelMaxFrame) throw const PanelE2eError('message too large');
    _socket.send(_chan.sealBytes(bytes));
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    // not awaited: with no listener a controller's close never completes
    if (!_in.isClosed) unawaited(_in.close());
    try {
      await _socket.close();
    } catch (_) {}
  }
}

/// Pairing was refused (wrong or used code, too many tries).
class PanelPairException implements Exception {
  const PanelPairException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PanelPairing {
  const PanelPairing({required this.secrets, required this.device});
  final PanelSecrets secrets;

  /// The name the computer gave this phone.
  final String device;
}

/// Pairs with the computer behind [link] and returns what to save. Throws
/// [PanelFingerprintMismatch] when the key is not the one in the link,
/// [PanelPairException] when the computer refuses the code.
Future<PanelPairing> pairWithPanel(
  PanelLink link, {
  required String label,
  PanelConnector connect = connectPanelSocket,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final secret = PanelChannel.newDeviceSecret();
  final wire = await _Wire.open(_wsUrl(link.baseUrl), link.fp, secret, connect, timeout);
  try {
    wire.send('pair', {'token': link.code, 'label': label});
    await for (final m in wire.messages.timeout(timeout)) {
      final data = m['data'];
      if (m['name'] == 'paired' && data is Map && data['session'] is String) {
        return PanelPairing(
          secrets: PanelSecrets(token: data['session'] as String, deviceKey: panelB64(secret)),
          device: (data['device'] as String?) ?? '',
        );
      }
      if (m['name'] == 'error') {
        throw PanelPairException(
          data is Map && data['message'] is String ? data['message'] as String : 'refused',
        );
      }
    }
    throw const PanelPairException('the computer closed the connection');
  } finally {
    await wire.close();
  }
}

const _promptChanged = 'The prompt changed — review it again';

const _scanAgainText = 'This phone is no longer paired. Scan the QR again.';

/// The session is over (expired, revoked or never saved): the person scans
/// the QR again. The connection stops retrying.
class ScanAgain extends Failed {
  const ScanAgain() : super(_scanAgainText);
}

/// The computer's key is not the pinned one: a hard stop, never retried. The
/// person can only scan its QR again.
class KeyChanged extends Failed {
  const KeyChanged() : super('Security key changed — scan again');
}

class _AuthRefused implements Exception {
  const _AuthRefused(this.message, {this.scanAgain = false});
  final String message;
  final bool scanAgain;
}

/// MachineConnection over the desktop panel's `/ws` (core ADR-064): wss,
/// sealed frames, the bridge commands. The panel decides what a command may
/// do; this side only keeps the approve-what-you-saw rule.
class PanelMachineConnection implements MachineConnection {
  PanelMachineConnection({
    required this.panel,
    required this.secrets,
    this.connect = connectPanelSocket,
    Future<void> Function(Duration) delay = _realDelay,
    this.timeout = const Duration(seconds: 15),
    this.pingEvery = const Duration(seconds: 20),
    this.idleLimit = const Duration(seconds: 50),
  }) : _delay = delay;

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);

  final PanelMachine panel;

  /// Where the token and device key live; null when they are gone.
  final Future<PanelSecrets?> Function() secrets;
  final PanelConnector connect;
  final Future<void> Function(Duration) _delay;
  final Duration timeout;
  final Duration pingEvery;
  final Duration idleLimit;

  final _state = StreamController<ConnState>.broadcast(sync: true);
  final _notices = StreamController<Notice>.broadcast();
  final _backoff = Backoff();
  ConnState _last = const Connecting();
  Completer<ConnState>? _first;
  bool _started = false;
  bool _closing = false;
  _Wire? _wire;
  var _ids = 0;
  final _pending = <int, Completer<Reply>>{};
  final _shown = <String, String>{};
  var _lastSeen = DateTime.now();

  @override
  MachineInfo get machine => MachineInfo(
    id: panel.id,
    name: panel.name,
    os: 'unknown',
    mode: ConnMode.cloud,
    online: _last is Ready,
  );

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

  void _settle(ConnState s) {
    final f = _first;
    if (f != null && !f.isCompleted) f.complete(s);
  }

  /// Starts connecting (once); returns the first settled state.
  Future<ConnState> start() {
    final first = _first ??= Completer<ConnState>();
    if (!_started) {
      _started = true;
      unawaited(_loop());
    }
    return first.future;
  }

  Future<void> _loop() async {
    while (!_closing) {
      _emit(const Connecting());
      Duration wait;
      try {
        await _session();
        if (_closing) return;
        wait = _backoff.next();
        _emit(Failed('connection lost', retryIn: wait));
      } on PanelFingerprintMismatch {
        _emit(const KeyChanged());
        _settle(_last);
        return;
      } on _AuthRefused catch (e) {
        if (_closing) return;
        if (e.scanAgain) {
          _emit(const ScanAgain());
          _settle(_last);
          return;
        }
        wait = _backoff.next();
        _emit(Failed(e.message, retryIn: wait));
        _settle(_last);
      } catch (e) {
        if (_closing) return;
        wait = _backoff.next();
        _emit(Failed('cannot connect: $e', retryIn: wait));
        _settle(_last);
      }
      if (_closing) return;
      await _delay(wait);
    }
  }

  Future<void> _session() async {
    final s = await secrets();
    if (_closing) return;
    if (s == null) throw const _AuthRefused('not paired', scanAgain: true);
    final wire = await _Wire.open(
      _wsUrl(panel.baseUrl),
      panel.fp,
      panelUnb64(s.deviceKey),
      connect,
      timeout,
    );
    if (_closing) {
      await wire.close();
      return;
    }
    final authed = Completer<void>();
    final done = Completer<void>();
    _lastSeen = DateTime.now();
    final sub = wire.messages.listen(
      (m) => _dispatch(m, authed),
      onError: (Object e) {
        // before sign-in the error belongs to the sign-in, after it to the session
        final c = authed.isCompleted ? done : authed;
        if (!c.isCompleted) c.completeError(e);
      },
      onDone: () {
        if (!authed.isCompleted) authed.completeError(StateError('closed before sign-in'));
        if (!done.isCompleted) done.complete();
      },
    );
    Timer? ping;
    try {
      wire.send('auth', {'session': s.token});
      await authed.future.timeout(timeout);
      if (_closing) return;
      _wire = wire;
      _backoff.reset();
      _emit(const Ready());
      _settle(_last);
      ping = Timer.periodic(pingEvery, (_) {
        if (DateTime.now().difference(_lastSeen) > idleLimit) {
          unawaited(wire.close());
          return;
        }
        try {
          wire.send('ping', const {});
        } catch (_) {}
      });
      await done.future;
    } finally {
      ping?.cancel();
      _wire = null;
      await sub.cancel();
      await wire.close();
      _failPending('connection lost');
    }
  }

  void _dispatch(Map<String, dynamic> m, Completer<void> authed) {
    _lastSeen = DateTime.now();
    final raw = m['data'];
    final data = raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
    switch (m['name']) {
      case 'hello':
        if (!authed.isCompleted) authed.complete();
      case 'error':
        if (!authed.isCompleted) {
          final why = (data['message'] as String?) ?? 'refused';
          authed.completeError(_AuthRefused(why, scanAgain: why.contains('pair again')));
        }
      case 'reply':
        final id = data['id'];
        final c = id is int ? _pending.remove(id) : null;
        c?.complete(_toReply(data));
      case 'notice':
        if (data['terminal'] is String && !_notices.isClosed) {
          _notices.add(Notice(
            terminal: data['terminal'] as String,
            agent: (data['agent'] as String?) ?? '',
            folder: (data['folder'] as String?) ?? '',
            kind: (data['kind'] as String?) ?? '',
            excerpt: (data['excerpt'] as String?) ?? '',
          ));
        }
    }
  }

  void _failPending(String why) {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(ReplyFailed(why));
    }
    _pending.clear();
  }

  Reply _toReply(Map<String, dynamic> d) {
    switch (d['kind']) {
      case 'done':
        return Done({
          if (d['text'] is String) 'text': d['text'],
          if (d['sessions'] is List) 'sessions': d['sessions'],
        });
      case 'needs_confirm':
        return NeedsConfirm((d['token'] as String?) ?? '', (d['what'] as String?) ?? '');
      case 'locked':
        return const Locked();
      case 'rate_limited':
        return RateLimited(d['retry_secs'] is int ? d['retry_secs'] as int : 0);
      case 'not_paired':
        return const NotPaired();
      case 'prompt_changed':
        return const ReplyFailed(_promptChanged);
      case 'failed':
        // Core reports a changed prompt as a failure whose message starts with its kind.
        final message = (d['message'] as String?) ?? 'failed';
        if (message.startsWith('prompt_changed')) return const ReplyFailed(_promptChanged);
        return ReplyFailed(message);
      default:
        return const ReplyFailed('unknown reply');
    }
  }

  Future<Reply> _cmd(String cmd, [Map<String, Object?> args = const {}]) async {
    final w = _wire;
    if (w == null) return const ReplyFailed('not connected');
    final id = ++_ids;
    final c = _pending[id] = Completer<Reply>();
    try {
      w.send('command', {'cmd': cmd, 'id': id, ...args});
    } catch (e) {
      _pending.remove(id);
      return ReplyFailed('$e');
    }
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        return const ReplyFailed('no answer from the computer');
      },
    );
  }

  Future<List<Session>> _fetch() async {
    final r = await _cmd('sessions');
    final list = r is Done ? r.detail['sessions'] : null;
    if (list is! List) throw StateError(r is ReplyFailed ? r.message : 'no sessions answer');
    return [for (final j in list) Session.fromJson((j as Map).cast<String, dynamic>())];
  }

  @override
  Future<List<Session>> sessions() async {
    final list = await _fetch();
    _shown
      ..clear()
      ..addEntries([for (final s in list) MapEntry(s.terminal, s.message)]);
    return list;
  }

  @override
  Future<SpacesView> spaces() async => const SpacesView.unsupported();

  @override
  Future<String> read(String terminal, {int lines = 50}) async {
    final r = await _cmd('read', {'terminal': terminal, 'lines': lines});
    if (r is Done) return (r.detail['text'] as String?) ?? '';
    throw StateError(r is ReplyFailed ? r.message : 'cannot read $terminal');
  }

  @override
  Future<Reply> send(String terminal, String text) =>
      _cmd('send', {'terminal': terminal, 'text': text});

  @override
  Future<Reply> keys(String terminal, List<Key> keys) =>
      _cmd('keys', {'terminal': terminal, 'keys': [for (final k in keys) k.name]});

  /// Approve or deny only what the person was shown (the same rule as the SSH
  /// path): the terminal must still be blocked on the same permission prompt.
  Future<Reply> _answer(String terminal, String cmd) async {
    final approve = cmd == 'approve';
    final seen = _shown.remove(terminal);
    if (seen == null) return const ReplyFailed('review the prompt first');
    final List<Session> now;
    try {
      now = await _fetch();
    } catch (e) {
      return ReplyFailed('$e');
    }
    final s = now.where((x) => x.terminal == terminal).firstOrNull;
    if (s == null) return ReplyFailed('no such terminal: $terminal');
    if (s.status != 'blocked' || s.blockedKind != 'permission') {
      final what = s.status == 'blocked' ? 'a ${s.blockedKind ?? 'blocked'} prompt' : s.status;
      return ReplyFailed('refused: only a blocked permission can be approved or denied (this is $what)');
    }
    if (s.message != seen) return const ReplyFailed('the prompt changed, review it again');
    return _cmd(cmd, {'terminal': terminal, if (approve) 'prompt_sha256': promptSha256(seen)});
  }

  @override
  Future<Reply> approve(String terminal) => _answer(terminal, 'approve');

  @override
  Future<Reply> deny(String terminal) => _answer(terminal, 'deny');

  @override
  Future<Reply> interrupt(String terminal) => _cmd('interrupt', {'terminal': terminal});

  @override
  Future<Reply> kill(String terminal) => _cmd('kill', {'terminal': terminal});

  @override
  Future<Reply> run(String folder, String command) =>
      _cmd('run', {'folder': folder, 'command': command});

  @override
  Future<Reply> confirm(String token) => _cmd('confirm', {'token': token});

  @override
  Future<TermSize> size(String terminal) =>
      Future.error(UnsupportedError('the panel has no terminal size'));

  @override
  Future<TermView> view(String terminal, {int history = 5000}) =>
      Future.error(UnsupportedError('the panel has no live terminal view'));

  @override
  Stream<Notice> notices() => _notices.stream;

  @override
  Future<String> appHome() => Future.error(UnsupportedError('files need SSH'));

  @override
  Future<String?> readFile(String path) => Future.error(UnsupportedError('files need SSH'));

  @override
  Future<void> writeFile(String path, String text) =>
      Future.error(UnsupportedError('files need SSH'));

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _settle(const Failed('closed'));
    await _wire?.close();
    _failPending('closed');
    await _state.close();
    await _notices.close();
  }
}
