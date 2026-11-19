import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../machine_connection.dart' show TermSize;
import 'frames.dart';

/// A duplex byte pipe to `h0x-core connect` (an SSH exec channel in
/// production, an in-memory pipe in tests).
abstract class ByteLink {
  Stream<List<int>> get input;
  void write(List<int> bytes);
  Future<void> close();
}

/// A JSON-RPC error from core: `error.data.kind` is the machine-readable part.
class CoreRpcException implements Exception {
  CoreRpcException(this.code, this.message, {this.kind = '', this.hint = ''});
  final int code;
  final String message;
  final String kind;
  final String hint;
  @override
  String toString() => 'CoreRpcException($kind: $message)';
}

/// The pipe did not speak core's protocol, or it ended.
class CoreProtocolException implements Exception {
  CoreProtocolException(this.message, {this.banner = false});
  final String message;

  /// The first stdout bytes were not JSON: a login banner or shell noise.
  final bool banner;
  @override
  String toString() => 'CoreProtocolException: $message';
}

class RpcNotification {
  const RpcNotification(this.method, this.params);
  final String method;
  final Map<String, dynamic> params;
}

/// A raw attach stream: first paint, then live terminal bytes.
class AttachedStream {
  AttachedStream._(this.terminal, this.initial, this.data, this.sizes, this._close);
  final Map<String, dynamic> terminal;

  /// The terminal's size when attached (cols/rows of [terminal], else 80x24).
  final TermSize initial;

  /// Pausing the listener pauses core: CREDIT is acknowledged only for chunks
  /// the listener has received. Cancelling detaches.
  final Stream<Uint8List> data;

  /// RESIZE frames (observers get them when asked with `resize_notifications`).
  final Stream<TermSize> sizes;
  final Future<void> Function() _close;

  /// Detach (sends CLOSE on the channel).
  Future<void> close() => _close();
}

/// `events.subscribe`: the snapshot, then events as they come.
class EventSubscription {
  EventSubscription._(this.seq, this.terminals, this.events, this._close);
  final int seq;
  final List<Map<String, dynamic>> terminals;

  /// `event`, `heartbeat` and `missed` notifications.
  final Stream<RpcNotification> events;
  final Future<void> Function() _close;
  Future<void> close() => _close();
}

class _Chan {
  _Chan(this.channel, this.onCancel, this.ack) {
    raw = StreamController<Uint8List>(
      sync: true,
      onListen: pump,
      onResume: pump,
      onCancel: () => onCancel(channel),
    );
  }

  final int channel;
  final void Function(int channel) onCancel;
  final void Function(_Chan chan, int n) ack;
  late final StreamController<Uint8List> raw;
  final sizes = StreamController<TermSize>();
  final events = StreamController<RpcNotification>();
  final lines = BytesBuilder(copy: false);
  final queue = Queue<Uint8List>();
  int unacked = 0;
  bool isEvents = false;
  bool ending = false;

  /// Hands queued chunks to a listener that is not paused; each one handed
  /// over is acknowledged to core. A paused (or absent) listener leaves them
  /// queued, so core stops at its window instead of memory growing.
  void pump() {
    while (queue.isNotEmpty && raw.hasListener && !raw.isPaused) {
      final c = queue.removeFirst();
      raw.add(c);
      ack(this, c.length);
    }
    if (ending && queue.isEmpty) {
      unawaited(raw.close());
      unawaited(sizes.close());
    }
  }
}

/// Core's JSON-RPC over a framed byte stream. Transport-agnostic.
///
/// Flow: [hello] (plain, newline JSON, `framed:true`), then frames. Calls ride
/// channel 0; [attach] and [subscribe] get their own channels, and every
/// channel is acknowledged with CREDIT so core keeps sending.
class CoreRpc {
  CoreRpc(this._link, {this.generation = 1, int creditEvery = streamWindow ~/ 4})
      : _creditEvery = creditEvery {
    _in = _link.input.listen(_onBytes, onError: (Object e) => _fail(e), onDone: _onDone);
  }

  /// core's `api::GENERATION`.
  final int generation;
  final ByteLink _link;
  final int _creditEvery;
  late final StreamSubscription<List<int>> _in;

  final _decoder = FrameDecoder();
  final _calls = <int, Completer<Object?>>{};
  final _chans = <int, _Chan>{};
  final _notifications = StreamController<RpcNotification>.broadcast();
  final _closed = Completer<void>();
  final _head = BytesBuilder(copy: false);
  var _plain = true;
  var _nextId = 2;
  Completer<Map<String, dynamic>>? _hello;
  Object? _failure;

  /// Completes when the pipe ends, normally or not.
  Future<void> get closed => _closed.future;

  /// Notifications on channel 0 (none today; kept so none are dropped silently).
  Stream<RpcNotification> get notifications => _notifications.stream;

  /// The handshake. Rejects an unsupported generation (`CoreRpcException`,
  /// kind `unsupported_generation`) and non-JSON output (banner).
  Future<Map<String, dynamic>> hello() {
    final c = _hello = Completer<Map<String, dynamic>>();
    _link.write(utf8.encode('${jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'hello',
          'params': {'generation': generation, 'framed': true},
        })}\n'));
    return c.future;
  }

  Future<Object?> call(String method, [Map<String, Object?> params = const {}]) {
    if (_plain) throw StateError('call before hello completed');
    final failure = _failure;
    if (failure != null) return Future.error(failure);
    final id = _nextId++;
    final c = _calls[id] = Completer<Object?>();
    _send(0, kindData, utf8.encode(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    })));
    return c.future;
  }

  Future<AttachedStream> attach({
    required String terminal,
    required int cols,
    required int rows,
    int history = 0,
    bool observe = true,
    bool resizeNotifications = true,
  }) async {
    final r = await call('terminal.attach', {
      'terminal': terminal,
      'cols': cols,
      'rows': rows,
      'history': history,
      'observe': observe,
      'resize_notifications': resizeNotifications,
    }) as Map<String, dynamic>;
    final channel = r['channel'] as int;
    final chan = _chans[channel]!;
    final t = (r['terminal'] as Map).cast<String, dynamic>();
    final tc = t['cols'], tr = t['rows'];
    return AttachedStream._(
      t,
      TermSize(tc is int && tc > 0 ? tc : 80, tr is int && tr > 0 ? tr : 24),
      chan.raw.stream,
      chan.sizes.stream,
      () => _closeChannel(channel, notifyCore: true),
    );
  }

  Future<EventSubscription> subscribe({Map<String, String>? labels, String? terminal}) async {
    final r = await call('events.subscribe', {
      if (labels != null) 'labels': labels,
      if (terminal != null) 'terminal': terminal,
    }) as Map<String, dynamic>;
    final channel = r['channel'];
    if (channel is! int) {
      throw CoreProtocolException('events.subscribe gave no channel (plain mode?)');
    }
    final chan = _chans[channel]!..isEvents = true;
    return EventSubscription._(
      (r['seq'] as num?)?.toInt() ?? 0,
      [for (final t in (r['terminals'] as List? ?? const [])) (t as Map).cast<String, dynamic>()],
      chan.events.stream,
      () => _closeChannel(channel, notifyCore: true),
    );
  }

  Future<void> close() async {
    _fail(CoreProtocolException('closed locally'));
    await _in.cancel();
    await _link.close();
  }

  // ---- inbound ----

  void _onBytes(List<int> chunk) {
    try {
      if (_plain) {
        _head.add(chunk);
        final all = _head.toBytes();
        final nl = all.indexOf(0x0a);
        if (nl < 0) return;
        _head.clear();
        _plain = false;
        _onHelloLine(all.sublist(0, nl));
        if (_failure != null) return;
        chunk = all.sublist(nl + 1);
      }
      for (final f in _decoder.add(chunk)) {
        _onFrame(f);
      }
    } on FrameException catch (e) {
      _fail(CoreProtocolException(e.message));
      _link.close();
    }
  }

  void _onHelloLine(List<int> line) {
    final text = utf8.decode(line, allowMalformed: true).trim();
    final pending = _hello;
    if (!text.startsWith('{')) {
      final shown = text.length > 200 ? '${text.substring(0, 200)}...' : text;
      final e = CoreProtocolException('expected JSON from h0x-core, got: $shown', banner: true);
      _fail(e);
      _link.close();
      return;
    }
    Object? msg;
    try {
      msg = jsonDecode(text);
    } on FormatException {
      final e = CoreProtocolException('expected JSON from h0x-core, got: $text', banner: true);
      _fail(e);
      _link.close();
      return;
    }
    if (msg is! Map || msg['id'] != 1) {
      _fail(CoreProtocolException('unexpected first message'));
      _link.close();
      return;
    }
    final err = msg['error'];
    if (err is Map) {
      final e = _rpcError(err.cast<String, dynamic>());
      pending?.completeError(e);
      _fail(e);
      _link.close();
      return;
    }
    final result = msg['result'];
    if (result is! Map || result['framed'] != true) {
      final e = CoreProtocolException('core did not switch to framed mode');
      pending?.completeError(e);
      _fail(e);
      _link.close();
      return;
    }
    pending?.complete(result.cast<String, dynamic>());
  }

  void _onFrame(Frame f) {
    if (f.channel == 0) {
      if (f.kind == kindData) _onMessage(f.payload);
      return; // other kinds on channel 0 are ignored, as core ignores them
    }
    final chan = _chans[f.channel];
    switch (f.kind) {
      case kindData:
        if (chan == null) return;
        if (chan.isEvents) {
          _ack(chan, f.payload.length);
          _onEventBytes(chan, f.payload);
        } else {
          chan.queue.add(f.payload);
          chan.pump();
        }
      case kindResize:
        if (chan != null && f.payload.length == 4) {
          final d = ByteData.sublistView(f.payload);
          chan.sizes.add(TermSize(d.getUint16(0, Endian.little), d.getUint16(2, Endian.little)));
        }
      case kindClose:
        _closeChannel(f.channel, notifyCore: false);
      default: // CREDIT/RESIZE/FOCUS/...: nothing to do for an observer; unknown kinds are ignored
        break;
    }
  }

  void _ack(_Chan chan, int n) {
    chan.unacked += n;
    if (chan.unacked >= _creditEvery) {
      final b = ByteData(4)..setUint32(0, chan.unacked, Endian.little);
      chan.unacked = 0;
      _send(chan.channel, kindCredit, b.buffer.asUint8List());
    }
  }

  void _onEventBytes(_Chan chan, Uint8List bytes) {
    chan.lines.add(bytes);
    final all = chan.lines.takeBytes();
    var start = 0;
    for (var i = 0; i < all.length; i++) {
      if (all[i] != 0x0a) continue;
      final line = utf8.decode(all.sublist(start, i), allowMalformed: true).trim();
      start = i + 1;
      if (line.isEmpty) continue;
      try {
        final m = jsonDecode(line) as Map;
        chan.events.add(RpcNotification(
          m['method'] as String? ?? '',
          ((m['params'] as Map?) ?? const {}).cast<String, dynamic>(),
        ));
      } catch (_) {
        // a line that is not a notification is dropped
      }
    }
    if (start < all.length) chan.lines.add(all.sublist(start));
  }

  void _onMessage(Uint8List payload) {
    final Object? m;
    try {
      m = jsonDecode(utf8.decode(payload));
    } on FormatException {
      return;
    }
    if (m is! Map) return;
    final id = m['id'];
    if (id is int && (m.containsKey('result') || m.containsKey('error'))) {
      final c = _calls.remove(id);
      if (c == null) return;
      final err = m['error'];
      if (err is Map) {
        c.completeError(_rpcError(err.cast<String, dynamic>()));
        return;
      }
      final result = m['result'];
      // Register a stream channel before anyone can await the reply: data frames
      // may already be behind it in the same read.
      if (result is Map && result['channel'] is int) {
        final ch = result['channel'] as int;
        _chans.putIfAbsent(
          ch,
          () => _Chan(ch, (c) => unawaited(_closeChannel(c, notifyCore: true)), _ack),
        );
      }
      c.complete(result);
    } else if (m['method'] is String) {
      _notifications.add(RpcNotification(
        m['method'] as String,
        ((m['params'] as Map?) ?? const {}).cast<String, dynamic>(),
      ));
    }
  }

  CoreRpcException _rpcError(Map<String, dynamic> err) {
    final data = err['data'];
    return CoreRpcException(
      (err['code'] as num?)?.toInt() ?? -32603,
      err['message'] as String? ?? '',
      kind: data is Map ? (data['kind'] as String? ?? '') : '',
      hint: data is Map ? (data['hint'] as String? ?? '') : '',
    );
  }

  // ---- outbound / teardown ----

  void _send(int channel, int kind, List<int> payload) {
    if (_failure != null) return;
    _link.write(encodeFrame(channel, kind, payload));
  }

  Future<void> _closeChannel(int channel, {required bool notifyCore}) async {
    final chan = _chans.remove(channel);
    if (chan == null) return;
    if (notifyCore) {
      _send(channel, kindClose, const []);
      chan.queue.clear();
    }
    // not awaited: close() of a stream nobody listens to never completes
    chan.ending = true;
    chan.pump(); // a core-side close still delivers what is queued, then ends
    unawaited(chan.events.close());
  }

  void _onDone() {
    if (_plain && _head.length > 0) {
      final text = utf8.decode(_head.takeBytes(), allowMalformed: true).trim();
      _fail(CoreProtocolException('h0x-core ended after: $text', banner: true));
    } else {
      _fail(CoreProtocolException('connection closed'));
    }
  }

  void _fail(Object e) {
    if (_failure != null) return;
    _failure = e;
    final hello = _hello;
    if (hello != null && !hello.isCompleted) hello.completeError(e);
    for (final c in _calls.values) {
      c.completeError(e);
    }
    _calls.clear();
    for (final chan in _chans.values) {
      chan.queue.clear();
      chan.ending = true;
      chan.pump();
      unawaited(chan.events.close());
    }
    _chans.clear();
    if (!_closed.isCompleted) _closed.complete();
  }
}
