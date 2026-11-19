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
/// screen lays the local terminal out at the width the computer reports.
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

  AgentPhase phase = AgentPhase.attaching;
  Session? session;
  TermSize? size;

  /// Why attaching failed, if it did.
  String? error;

  /// The history is replaying: from the attach until the bytes have been
  /// quiet for [_replayQuiet]. The core does not say how much there is, so
  /// [replayProgress] measures the bytes against an estimate of the history
  /// asked for (5000 lines of about 80 bytes), never past 95 %.
  bool replaying = false;
  int replayedBytes = 0;
  static const _replayEstimate = 5000 * 80;
  static const _replayQuiet = Duration(milliseconds: 400);
  Timer? _replayTimer;

  /// 0 to 1 while replaying; 1 once replayed.
  double get replayProgress =>
      replaying ? (replayedBytes / _replayEstimate).clamp(0.0, 0.95) : 1.0;

  void _endReplay() {
    _replayTimer?.cancel();
    if (!replaying) return;
    replaying = false;
    _notify();
  }

  /// The wait before the next try after a drop, and how many drops there have
  /// been (the countdown ring restarts on each).
  Duration? retryIn;
  int retryEpoch = 0;

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
    phase = AgentPhase.attaching;
    replaying = true;
    replayedBytes = 0;
    error = null;
    _notify();
    try {
      final v = await conn.view(terminalId);
      if (_disposed) {
        unawaited(v.close());
        return;
      }
      _view = v;
      // The screen sizes the local terminal to the computer's width; the
      // computer's own terminal is never resized from here.
      size = v.initial;
      _sizesSub = v.sizes.listen((s) {
        size = s;
        _notify();
      });
      _bytesSub = v.bytes.listen(_onBytes, onDone: _onViewDone);
      // A quiet terminal sends nothing: do not wait for output forever.
      _settle = Timer(settleAfter, () {
        _markReady();
        if (replayedBytes == 0) _endReplay();
      });
    } catch (e) {
      error = '$e';
      phase = AgentPhase.reconnecting;
      replaying = false;
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
    if (replaying) {
      replayedBytes += chunk.length;
      _replayTimer?.cancel();
      _replayTimer = Timer(_replayQuiet, _endReplay);
      _notify();
    }
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
    if (_disposed) return;
    if (phase != AgentPhase.finished) {
      phase = AgentPhase.reconnecting;
      _notify();
    }
  }

  void _onState(ConnState s) {
    if (_disposed) return;
    if (s is Failed) {
      retryIn = s.retryIn;
      retryEpoch++;
    } else if (s is Ready) {
      retryIn = null;
    }
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
    _replayTimer?.cancel();
    // Not awaited: cancelling must never hold up the next attach.
    unawaited(_bytesSub?.cancel());
    unawaited(_sizesSub?.cancel());
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
    _replayTimer?.cancel();
    unawaited(_stateSub?.cancel());
    unawaited(_detach());
    selection.dispose();
    super.dispose();
  }
}
