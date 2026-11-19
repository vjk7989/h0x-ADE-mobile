import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide Key;
import 'package:flutter/scheduler.dart';
import 'package:xterm/xterm.dart';

import '../conn/machine_connection.dart';

enum AgentPhase {
  /// Opening the view and replaying history.
  attaching,
  ready,

  /// The connection dropped; the last output stays, dimmed.
  reconnecting,

  /// The terminal's process exited.
  finished,
}

/// The most text one message may carry (the relay's limit; kept on SSH too).
const kMaxMessageBytes = 60 * 1024;

bool messageTooLong(String text) => utf8.encode(text).length > kMaxMessageBytes;

/// One open terminal on one machine: the xterm [Terminal] fed from
/// `view()`, the session facts for the header and prompt card, and the
/// calls the screen makes. It never resizes the computer's terminal: the
/// terminal follows the size the computer reports.
class AgentController extends ChangeNotifier {
  AgentController(
    this.conn,
    this.terminalId, {
    this.pollEvery = const Duration(seconds: 3),
    this.settleAfter = const Duration(milliseconds: 1500),
  });

  final MachineConnection conn;
  final String terminalId;
  final Duration pollEvery;
  final Duration settleAfter;

  final Terminal terminal = Terminal(maxLines: 5000);
  final TerminalController selection = TerminalController();

  /// DEBUG trace (temporary).
  final List<String> trace = [];

  AgentPhase phase = AgentPhase.attaching;
  Session? session;
  TermSize? size;

  /// Why attaching failed, if it did.
  String? error;

  TermView? _view;
  StreamSubscription<List<int>>? _bytesSub;
  StreamSubscription<TermSize>? _sizesSub;
  StreamSubscription<ConnState>? _stateSub;
  Timer? _poll;
  Timer? _settle;
  bool _disposed = false;
  bool _wasReady = false;

  // Output waits here and is written once per frame.
  final StringBuffer _pending = StringBuffer();
  bool _frameScheduled = false;
  late final ByteConversionSink _decoder = utf8.decoder
      .startChunkedConversion(StringConversionSink.fromStringSink(_decoded));
  final StringBuffer _decoded = StringBuffer();

  Future<void> start() async {
    _stateSub = conn.state.listen(_onState);
    await _attach();
    unawaited(_refreshSession());
    _poll = Timer.periodic(pollEvery, (_) => _refreshSession());
  }

  Future<void> _attach() async {
    trace.add('attach');
    phase = AgentPhase.attaching;
    error = null;
    _notify();
    try {
      final v = await conn.view(terminalId);
      if (_disposed) {
        unawaited(v.close());
        return;
      }
      _view = v;
      size = v.initial;
      terminal.resize(v.initial.cols, v.initial.rows);
      _sizesSub = v.sizes.listen((s) {
        size = s;
        terminal.resize(s.cols, s.rows);
        _notify();
      });
      _bytesSub = v.bytes.listen(_onBytes, onDone: _onViewDone);
      // A quiet terminal sends nothing: do not wait for output forever.
      _settle = Timer(settleAfter, _markReady);
    } catch (e) {
      error = '$e';
      phase = AgentPhase.reconnecting;
      _notify();
    }
  }

  void _markReady() {
    if (phase == AgentPhase.attaching) {
      phase = AgentPhase.ready;
      _wasReady = true;
      _notify();
    }
  }

  void _onBytes(List<int> chunk) {
    _decoder.add(chunk);
    final text = _decoded.toString();
    _decoded.clear();
    if (text.isNotEmpty) {
      _pending.write(text);
      _scheduleWrite();
    }
    _markReady();
  }

  /// At most one write to the terminal per frame.
  void _scheduleWrite() {
    if (_frameScheduled || _disposed) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      if (_disposed) return;
      final text = _pending.toString();
      _pending.clear();
      if (text.isNotEmpty) terminal.write(text);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _onViewDone() {
    trace.add('viewDone phase=$phase');
    if (_disposed) return;
    if (phase != AgentPhase.finished) {
      phase = AgentPhase.reconnecting;
      _notify();
    }
  }

  void _onState(ConnState s) {
    trace.add('state ${s.runtimeType} phase=$phase');
    if (_disposed) return;
    if (s is Ready) {
      // Back after a drop: replay from the top.
      if (phase == AgentPhase.reconnecting) {
        terminal.write('\x1b[2J\x1b[3J\x1b[H');
        unawaited(_detach().then((_) => _attach()));
      }
    } else if (s is Failed || s is Connecting) {
      if (_wasReady && phase != AgentPhase.finished) {
        phase = AgentPhase.reconnecting;
        _notify();
      }
    }
  }

  Future<void> _detach() async {
    _settle?.cancel();
    await _bytesSub?.cancel();
    await _sizesSub?.cancel();
    _bytesSub = _sizesSub = null;
    final v = _view;
    _view = null;
    if (v != null) {
      // Not awaited: a transport may take long to answer a close.
      unawaited(v.close().catchError((Object _) {}));
    }
  }

  Future<void> _refreshSession() async {
    if (_disposed) return;
    try {
      final all = await conn.sessions();
      if (_disposed) return;
      Session? mine;
      for (final s in all) {
        if (s.terminal == terminalId) mine = s;
      }
      session = mine;
      if (mine != null && !mine.live) phase = AgentPhase.finished;
      _notify();
    } catch (_) {
      // The next poll tries again; a drop shows through [state].
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshNow() => _refreshSession();

  // ---- calls ----

  Future<Reply> send(String text) => conn.send(terminalId, text);
  Future<Reply> sendKeys(List<Key> keys) => conn.keys(terminalId, keys);
  Future<Reply> approve() => conn.approve(terminalId);
  Future<Reply> deny() => conn.deny(terminalId);
  Future<Reply> interrupt() => conn.interrupt(terminalId);
  Future<Reply> kill() => conn.kill(terminalId);
  Future<Reply> confirm(String token) => conn.confirm(token);

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _settle?.cancel();
    unawaited(_stateSub?.cancel());
    unawaited(_detach());
    selection.dispose();
    super.dispose();
  }
}
