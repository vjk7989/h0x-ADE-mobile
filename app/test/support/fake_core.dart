import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hyperox/conn/ssh/frames.dart';
import 'package:hyperox/conn/ssh/ssh_keys.dart';
import 'package:hyperox/conn/ssh/ssh_transport.dart';

import 'mem_link.dart';

class FakeCoreError implements Exception {
  FakeCoreError(this.kind, this.message);
  final String kind;
  final String message;
}

Map<String, dynamic> terminal(String address, String name, String state,
    {String? kind, String app = 'claude', String cwd = '/srv/a', bool live = true}) {
  return {
    'address': address,
    'name': name,
    'cwd': cwd,
    'cols': 100,
    'rows': 30,
    'argv': ['claude'],
    'state': live ? 'live' : 'finished',
    'status': {'state': state, 'app': app, if (kind != null) 'kind': kind, 'msg': 'msg $address'},
  };
}

/// What `h0x-core connect` would answer, for the contract fixture:
/// t1 working, t2 blocked/permission, t3 blocked/question; read t1 = "hello t1".
class FakeCoreState {
  final terminals = <String, Map<String, dynamic>>{
    't1': terminal('t1', 'build', 'working'),
    't2': terminal('t2', 'perm', 'blocked', kind: 'permission', app: 'codex', cwd: '/srv/b'),
    't3': terminal('t3', 'ask', 'blocked', kind: 'question', cwd: '/srv/c'),
  };

  /// `method params-json` of every call received, in order.
  final calls = <String>[];
  final closedChannels = <int>[];
  var _channel = 0;
  FakeCoreProcess? process;

  Object? handle(String method, Map<String, dynamic> p) {
    calls.add('$method ${jsonEncode(p)}');
    Map<String, dynamic> get() =>
        terminals[p['terminal']] ?? (throw FakeCoreError('not_found', 'no such terminal'));
    switch (method) {
      case 'terminal.list':
        return {'terminals': terminals.values.toList(), 'hidden_finished': 0, 'machines': []};
      case 'terminal.get':
        return get();
      case 'terminal.read':
        get();
        return {'text': 'hello ${p['terminal']}', 'complete': true, 'how': 'screen'};
      case 'terminal.send':
        get();
        return {'turn': 1, 'status': 'working'};
      case 'terminal.keys':
        get();
        return {'turn': 1};
      case 'terminal.interrupt':
        get();
        return {'outcome': 'stopped', 'key': 'esc'};
      case 'terminal.kill':
        final t = get();
        terminals.remove(p['terminal']);
        return t;
      case 'terminal.run':
        return terminal('t9', 'new', 'idle', cwd: p['cwd'] as String);
      case 'terminal.attach':
        get();
        final ch = ++_channel;
        return {'channel': ch, 'terminal': get(), 'resize_notifications': true, 'automatic_input': false};
      case 'events.subscribe':
        final ch = ++_channel;
        return {'channel': ch, 'seq': 0, 'terminals': terminals.values.toList()};
      default:
        throw FakeCoreError('unknown_method', method);
    }
  }
}

/// A scripted `h0x-core connect` pipe: plain hello, then frames.
class FakeCoreProcess implements RemoteProcess {
  FakeCoreProcess(this.core, {this.generation = 1}) {
    core.process = this;
  }

  final FakeCoreState core;
  final int generation;
  final _out = StreamController<List<int>>();
  final _err = StreamController<List<int>>();
  final _dec = FrameDecoder();
  final _head = BytesBuilder();
  var _plain = true;
  int? subscribedChannel;

  /// Bytes of CREDIT the client has acknowledged, over all channels.
  var creditsReceived = 0;

  @override
  Stream<List<int>> get input => _out.stream;

  @override
  Stream<List<int>> get stderr => _err.stream;

  @override
  Future<int?> exitCode({Duration timeout = Duration.zero}) async => null;

  @override
  void write(List<int> bytes) {
    if (_plain) {
      _head.add(bytes);
      final all = _head.toBytes();
      final nl = all.indexOf(0x0a);
      if (nl < 0) return;
      _head.clear();
      _plain = false;
      final req = jsonDecode(utf8.decode(all.sublist(0, nl))) as Map;
      if ((req['params'] as Map)['generation'] != generation) {
        _out.add(utf8.encode('${jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'error': {
                'code': -32000,
                'message': 'protocol generation not supported',
                'data': {'kind': 'unsupported_generation', 'hint': ''}
              }
            })}\n'));
        return;
      }
      _out.add(helloReply());
      bytes = all.sublist(nl + 1);
    }
    for (final f in _dec.add(bytes)) {
      if (f.channel == 0 && f.kind == kindData) {
        _onRequest(jsonDecode(utf8.decode(f.payload)) as Map<String, dynamic>);
      } else if (f.kind == kindCredit) {
        creditsReceived += ByteData.sublistView(f.payload).getUint32(0, Endian.little);
      } else if (f.kind == kindClose) {
        core.closedChannels.add(f.channel);
      }
    }
  }

  void _onRequest(Map<String, dynamic> req) {
    final id = req['id'];
    final method = req['method'] as String;
    final params = ((req['params'] as Map?) ?? const {}).cast<String, dynamic>();
    Object? body;
    try {
      final result = core.handle(method, params);
      if (method == 'events.subscribe') subscribedChannel = (result as Map)['channel'] as int;
      body = {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on FakeCoreError catch (e) {
      body = {
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': -32000,
          'message': e.message,
          'data': {'kind': e.kind, 'hint': ''}
        }
      };
    }
    _out.add(jsonFrame(0, body));
  }

  /// Terminal bytes on a stream channel.
  void pushData(int channel, List<int> data) => _out.add(encodeFrame(channel, kindData, data));

  /// A RESIZE frame (u16 LE cols, u16 LE rows) on a stream channel.
  void pushResize(int channel, int cols, int rows) {
    final d = ByteData(4)
      ..setUint16(0, cols, Endian.little)
      ..setUint16(2, rows, Endian.little);
    _out.add(encodeFrame(channel, kindResize, d.buffer.asUint8List()));
  }

  void pushEvent(Map<String, dynamic> params, {String method = 'event'}) {
    _out.add(encodeFrame(subscribedChannel!, kindData,
        utf8.encode('${jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params})}\n')));
  }

  /// The link drops (the SSH session ends).
  void drop() => _out.close();

  @override
  Future<void> close() async {
    if (!_out.isClosed) await _out.close();
    if (!_err.isClosed) await _err.close();
  }
}

/// A process that is not core: prints [stdout]/[stderr] and (if [code] is set) exits.
class ScriptedProcess implements RemoteProcess {
  ScriptedProcess({String stdout = '', String stderr = '', this.code}) {
    if (stdout.isNotEmpty) _out.add(utf8.encode(stdout));
    if (stderr.isNotEmpty) _err.add(utf8.encode(stderr));
    if (code != null) {
      _out.close();
      _err.close();
    }
  }
  final int? code;
  final _out = StreamController<List<int>>();
  final _err = StreamController<List<int>>();

  @override
  Stream<List<int>> get input => _out.stream;

  @override
  Stream<List<int>> get stderr => _err.stream;

  @override
  Future<int?> exitCode({Duration timeout = Duration.zero}) async => code;

  @override
  void write(List<int> bytes) {}

  @override
  Future<void> close() async {
    if (!_out.isClosed) await _out.close();
    if (!_err.isClosed) await _err.close();
  }
}

/// Fake SSH session: [onExec] decides what each command is.
class FakeSshTransport implements SshTransport {
  FakeSshTransport({
    required this.onExec,
    required this.verify,
    this.connectError,
    this.hostKey = 'SHA256:hostkey',
  });

  final RemoteProcess Function(String command) onExec;
  final HostKeyVerifier verify;
  final Object? connectError;
  final String hostKey;
  final commands = <String>[];
  final _done = Completer<void>();
  var closed = false;

  @override
  Future<void> connect() async {
    if (connectError != null) throw connectError!;
    final ok = await verify('ssh-ed25519', hostKey);
    if (!ok) throw SshFatal('host key refused');
  }

  @override
  Future<RemoteProcess> exec(String command) async {
    commands.add(command);
    return onExec(command);
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    closed = true;
    if (!_done.isCompleted) _done.complete();
  }
}

/// A SecretStore in memory.
class MemSecrets implements SecretStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));
