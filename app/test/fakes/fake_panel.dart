import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hyperox/conn/panel/e2e.dart';
import 'package:hyperox/conn/panel/panel_connection.dart';
import 'package:pointycastle/export.dart';

/// A panel server in memory: the same handshake and frame sealing as core's
/// `bridge/web/e2e.rs` (server side), and the bridge messages of docs/bridge.md.
/// It holds the contract fixture: t1 working, t2 blocked on a permission,
/// t3 blocked on a question; reading t1 gives "hello t1".
class FakePanel {
  FakePanel({int keyByte = 0x11}) : _s = _bigFrom(List.filled(32, keyByte));

  static final _params = ECDomainParameters('prime256v1');
  static final _label = utf8.encode('h0x-bridge v1');

  final BigInt _s;
  var connects = 0;
  final urls = <Uri>[];
  final conns = <FakePanelConn>[];

  /// The next connects throw this many times before one works.
  var refuse = 0;

  /// Auth answers "unknown or revoked session; pair again".
  var revoked = false;

  /// Nothing after the handshake is answered (a dead network).
  var mute = false;

  /// When set, the next `sessions` answer is followed by this prompt text on
  /// t2: the prompt swapped right after the phone looked.
  String? swapPromptAfterSessions;

  /// When positive, the server hello is this many characters of padding.
  var helloPad = 0;

  String pairCode = 'CODE';
  final sessions = <String, Uint8List>{}; // session token -> device public key
  final tokens = <String>{};
  var _confirmCounter = 0;

  final terminals = <String, Map<String, Object?>>{
    't1': _term('t1', 'build', 'claude', '/srv/a', 'working', null, ''),
    't2': _term('t2', 'perm', 'codex', '/srv/b', 'blocked', 'permission', 'Allow rm -rf?'),
    't3': _term('t3', 'ask', 'claude', '/srv/c', 'blocked', 'question', 'Which one?'),
  };

  static Map<String, Object?> _term(
    String a,
    String name,
    String agent,
    String folder,
    String status,
    String? kind,
    String msg,
  ) => {
    'address': a,
    'name': name,
    'agent': agent,
    'folder': folder,
    'status': status,
    'live': true,
    'kind': kind,
    'msg': msg,
  };

  static BigInt _bigFrom(List<int> b) =>
      b.fold(BigInt.zero, (n, x) => (n << 8) | BigInt.from(x));

  static Uint8List _be32(BigInt n) {
    final out = Uint8List(32);
    for (var i = 31; i >= 0; i--) {
      out[i] = (n & BigInt.from(0xff)).toInt();
      n >>= 8;
    }
    return out;
  }

  static Uint8List pub(BigInt d) => (_params.G * d)!.getEncoded(false);

  static Uint8List _ecdh(BigInt secret, List<int> peer) =>
      _be32((_params.curve.decodePoint(peer)! * secret)!.x!.toBigInteger()!);

  /// The fingerprint a QR would carry.
  String get fp => panelFingerprint(pub(_s));

  PanelConnector get connector => (url) async {
    connects++;
    urls.add(url);
    if (refuse > 0) {
      refuse--;
      throw StateError('connection refused');
    }
    final c = FakePanelConn._(this);
    conns.add(c);
    return c;
  };

  /// Closes every open connection, as a restart or a network drop would.
  Future<void> dropAll() async {
    for (final c in List.of(conns)) {
      await c.drop();
    }
  }

  void notice(String terminal, String kind, String excerpt) {
    for (final c in conns) {
      c.push('notice', {
        'terminal': terminal,
        'agent': 'claude',
        'folder': '/srv/a',
        'kind': kind,
        'excerpt': excerpt,
      });
    }
  }

  Map<String, Object?> command(Map<String, dynamic> d) {
    final id = d['id'];
    Map<String, Object?> done(Map<String, Object?> extra) => {'id': id, 'kind': 'done', ...extra};
    Map<String, Object?> failed(String m) => {'id': id, 'kind': 'failed', 'message': m};
    final t = terminals[d['terminal']];
    switch (d['cmd']) {
      case 'sessions':
        final rows = [for (final x in terminals.values) {...x}];
        final swap = swapPromptAfterSessions;
        if (swap != null) {
          terminals['t2']!['msg'] = swap;
          swapPromptAfterSessions = null;
        }
        return done({'sessions': rows});
      case 'list':
        return done({'text': terminals.keys.join('\n')});
      case 'read':
        return t == null ? failed('no such terminal: ${d['terminal']}') : done({'text': 'hello ${t['address']}'});
      case 'send' || 'keys' || 'interrupt':
        return t == null ? failed('no such terminal: ${d['terminal']}') : done(const {'text': 'sent'});
      case 'approve' || 'deny':
        if (t == null) return failed('no such terminal: ${d['terminal']}');
        if (t['status'] != 'blocked' || t['kind'] != 'permission') {
          return failed('only a blocked permission can be approved or denied');
        }
        if (d['cmd'] == 'approve' && d['prompt_sha256'] != promptSha256(t['msg'] as String)) {
          return {'id': id, 'kind': 'failed', 'message': 'prompt_changed: the prompt changed; review it again'};
        }
        return done(const {'text': 'sent'});
      case 'kill':
        if (t == null) return failed('no such terminal: ${d['terminal']}');
        final token = 'k${++_confirmCounter}';
        tokens.add(token);
        return {'id': id, 'kind': 'needs_confirm', 'token': token, 'what': 'kill ${d['terminal']}'};
      case 'run':
        final token = 'k${++_confirmCounter}';
        tokens.add(token);
        return {'id': id, 'kind': 'needs_confirm', 'token': token, 'what': 'run ${d['command']}'};
      case 'confirm':
        return tokens.remove(d['token']) ? done(const {'text': 'done'}) : failed('unknown or used token');
      default:
        return failed('unknown command');
    }
  }
}

/// One server-side connection, also the [PanelSocket] the client talks to.
class FakePanelConn implements PanelSocket {
  FakePanelConn._(this.panel);
  final FakePanel panel;
  final _out = StreamController<Object?>();
  Uint8List? _kSend;
  Uint8List? _kRecv;
  int sendCtr = 0;
  int recvCtr = 0;
  Uint8List? lastFrame;
  Uint8List? devicePub;
  bool authed = false;
  bool closed = false;

  /// Every plain message the client sent after the handshake.
  final received = <Map<String, dynamic>>[];

  @override
  Stream<Object?> get messages => _out.stream;

  @override
  Future<void> close() async {
    closed = true;
    if (!_out.isClosed) await _out.close();
  }

  Future<void> drop() => close();

  @override
  void send(Object data) {
    if (closed) return;
    if (_kSend == null) {
      _hello(data as String);
      return;
    }
    final Uint8List plain;
    try {
      plain = _gcm(false, _kRecv!, 1, recvCtr, Uint8List.fromList(data as List<int>));
    } catch (_) {
      close();
      return;
    }
    recvCtr++;
    final msg = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    received.add(msg);
    if (panel.mute) return;
    _handle(msg);
  }

  void _hello(String clientHello) {
    final j = jsonDecode(clientHello) as Map<String, dynamic>;
    final d = panelUnb64(j['d'] as String);
    final ec = panelUnb64(j['e'] as String);
    final cNonce = panelUnb64(j['n'] as String);
    devicePub = d;
    final es = BigInt.parse('44' * 32, radix: 16);
    final sNonce = Uint8List.fromList(List.filled(32, 0x66));
    final sPub = FakePanel.pub(panel._s);
    final serverHello =
        '{"v":1,"s":"${panelB64(sPub)}","e":"${panelB64(FakePanel.pub(es))}","n":"${panelB64(sNonce)}"}';
    final ikm = Uint8List.fromList([
      ...FakePanel._ecdh(es, ec),
      ...FakePanel._ecdh(panel._s, ec),
      ...FakePanel._ecdh(es, d),
    ]);
    final transcript = Uint8List.fromList([...utf8.encode(clientHello), ...utf8.encode(serverHello)]);
    final hkdf = HKDFKeyDerivator(SHA256Digest())
      ..init(
        HkdfParameters(
          ikm,
          64,
          Uint8List.fromList([...cNonce, ...sNonce]),
          Uint8List.fromList([...FakePanel._label, ...SHA256Digest().process(transcript)]),
        ),
      );
    final okm = Uint8List(64);
    hkdf.deriveKey(null, 0, okm, 0);
    _kRecv = okm.sublist(0, 32);
    _kSend = okm.sublist(32);
    _out.add(panel.helloPad > 0 ? 'x' * panel.helloPad : serverHello);
  }

  static Uint8List _gcm(bool seal, Uint8List key, int dir, int ctr, Uint8List data) {
    final nonce = Uint8List(12);
    ByteData.view(nonce.buffer)
      ..setUint32(0, dir)
      ..setUint64(4, ctr);
    final tail = Uint8List(4);
    ByteData.view(tail.buffer).setUint32(0, dir);
    final c = GCMBlockCipher(AESEngine())
      ..init(seal, AEADParameters(KeyParameter(key), 128, nonce, Uint8List.fromList([...FakePanel._label, ...tail])));
    return c.process(data);
  }

  Uint8List _seal(Map<String, Object?> msg) {
    final frame = _gcm(true, _kSend!, 2, sendCtr, Uint8List.fromList(utf8.encode(jsonEncode(msg))));
    sendCtr++;
    return frame;
  }

  /// A message to the client (also used by tests).
  void push(String name, Object? data) {
    if (closed || _kSend == null) return;
    final frame = _seal({'name': name, 'data': data});
    lastFrame = frame;
    _out.add(frame);
  }

  /// The previous frame again: a replay the client must refuse.
  void replayLast() {
    if (!_out.isClosed) _out.add(lastFrame);
  }

  /// A frame sealed with a counter that skipped one: out of order.
  void pushOutOfOrder() {
    sendCtr++;
    push('heartbeat', null);
  }

  /// A binary frame of [n] bytes (for the 64 KB limit).
  void pushRaw(int n) {
    if (!_out.isClosed) _out.add(Uint8List(n));
  }

  void pushText(String text) {
    if (!_out.isClosed) _out.add(text);
  }

  void _handle(Map<String, dynamic> msg) {
    final data = msg['data'] is Map ? (msg['data'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    switch (msg['name']) {
      case 'ping':
        push('pong', null);
      case 'pair':
        if (data['token'] != panel.pairCode) {
          push('error', {'message': 'wrong or used pairing code'});
          close();
          return;
        }
        panel.pairCode = '';
        final session = 's${panel.sessions.length + 1}-${data['label']}';
        panel.sessions[session] = devicePub!;
        authed = true;
        push('paired', {'session': session, 'device': data['label'], 'id': 1});
      case 'auth':
        final key = panel.sessions[data['session']];
        if (panel.revoked || key == null || panelB64(key) != panelB64(devicePub!)) {
          push('error', {'message': 'unknown or revoked session; pair again'});
          close();
          return;
        }
        authed = true;
        push('hello', {'tunnel': false});
      case 'command':
        if (!authed) {
          push('error', {'message': 'pair or auth first'});
          close();
          return;
        }
        push('reply', panel.command(data));
    }
  }
}
