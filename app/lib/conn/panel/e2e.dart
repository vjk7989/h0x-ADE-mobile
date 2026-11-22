import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Client side of the core web panel's end-to-end channel (core ADR-064,
/// `bridge/web/e2e.rs`). Pure: no socket. Byte for byte what the Rust server
/// and the browser client do; `test/fixtures/panel_e2e_vectors.json` is the
/// frozen contract.

final _label = utf8.encode('h0x-bridge v1');
const _c2s = 1;
const _s2c = 2;
const _pubLen = 65;
const _nonceLen = 32;

final _params = ECDomainParameters('prime256v1');
final _p = BigInt.parse(
  'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
  radix: 16,
);
final _b = BigInt.parse(
  '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',
  radix: 16,
);

/// A handshake or a frame was refused; the caller closes the connection.
class PanelE2eError implements Exception {
  const PanelE2eError(this.message);
  final String message;

  @override
  String toString() => 'PanelE2eError: $message';
}

/// The server's key is not the pinned one: possible impersonation.
class PanelFingerprintMismatch extends PanelE2eError {
  const PanelFingerprintMismatch() : super('server fingerprint mismatch');
}

/// base64url without padding.
String panelB64(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Strict inverse of [panelB64]: only canonical unpadded base64url.
Uint8List panelUnb64(String text) {
  try {
    final bytes = base64Url.decode(base64Url.normalize(text));
    if (panelB64(bytes) == text) return Uint8List.fromList(bytes);
  } on FormatException {
    // falls through to the shared error
  }
  throw const PanelE2eError('bad base64');
}

/// `b64(SHA-256(S_pub))`, the value carried by the pairing link.
String panelFingerprint(List<int> serverPublic) =>
    panelB64(_sha256(Uint8List.fromList(serverPublic)));

Uint8List _sha256(Uint8List data) => SHA256Digest().process(data);

Uint8List _be(BigInt n, int len) {
  final out = Uint8List(len);
  for (var i = len - 1; i >= 0; i--) {
    out[i] = (n & BigInt.from(0xff)).toInt();
    n >>= 8;
  }
  return out;
}

BigInt _int(List<int> bytes) =>
    bytes.fold(BigInt.zero, (n, b) => (n << 8) | BigInt.from(b));

Uint8List _cat(List<List<int>> parts) =>
    Uint8List.fromList([for (final p in parts) ...p]);

Uint8List _randomBytes(int n) {
  final rng = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < n; i++) rng.nextInt(256)]);
}

BigInt _secret(List<int> bytes) {
  final d = _int(bytes);
  if (bytes.length != 32 || d == BigInt.zero || d >= _params.n) {
    throw const PanelE2eError('bad secret key');
  }
  return d;
}

Uint8List _public(BigInt d) =>
    (_params.G * d)!.getEncoded(false);

/// A 65-byte SEC1 uncompressed point; rejects points not on the curve.
ECPoint _parsePublic(List<int> bytes) {
  const bad = PanelE2eError('bad public key');
  if (bytes.length != _pubLen || bytes[0] != 4) throw bad;
  final x = _int(bytes.sublist(1, 33));
  final y = _int(bytes.sublist(33));
  if (x >= _p || y >= _p) throw bad;
  final rhs = (x * x * x - BigInt.from(3) * x + _b) % _p;
  if ((y * y) % _p != rhs) throw bad;
  return _params.curve.decodePoint(bytes)!;
}

Uint8List _ecdh(BigInt secret, ECPoint pub) =>
    _be((pub * secret)!.x!.toBigInteger()!, 32);

Uint8List _nonce(int dir, int ctr) {
  final out = Uint8List(12);
  final view = ByteData.view(out.buffer);
  view.setUint32(0, dir);
  view.setUint64(4, ctr);
  return out;
}

Uint8List _aad(int dir) {
  final tail = Uint8List(4);
  ByteData.view(tail.buffer).setUint32(0, dir);
  return _cat([_label, tail]);
}

Uint8List _field(Map<String, dynamic> hello, String key, int len) {
  final v = hello[key];
  if (v is! String) throw const PanelE2eError('bad hello');
  final bytes = panelUnb64(v);
  if (bytes.length != len) throw const PanelE2eError('bad length');
  return bytes;
}

/// One connection's client end: build the hello, [accept] the server's
/// answer, then [seal] and [open] frames. Any [open] error means close.
class PanelChannel {
  /// Starts a handshake with the long-term device key (a 32-byte secret, see
  /// [newDeviceSecret]). [ephemeralSecret] and [nonce] are for tests only.
  PanelChannel.start(
    Uint8List deviceSecret, {
    Uint8List? ephemeralSecret,
    Uint8List? nonce,
  }) : _d = _secret(deviceSecret),
       _ec = _secret(ephemeralSecret ?? _newSecret()),
       _cNonce = nonce ?? _randomBytes(_nonceLen) {
    if (_cNonce.length != _nonceLen) throw const PanelE2eError('bad nonce');
    _hello =
        '{"v":1,"d":"${panelB64(_public(_d))}",'
        '"e":"${panelB64(_public(_ec))}","n":"${panelB64(_cNonce)}"}';
  }

  /// A fresh device secret; the caller persists it.
  static Uint8List newDeviceSecret() => _newSecret();

  static Uint8List _newSecret() {
    while (true) {
      final bytes = _randomBytes(32);
      final d = _int(bytes);
      if (d != BigInt.zero && d < _params.n) return bytes;
    }
  }

  final BigInt _d;
  final BigInt _ec;
  final Uint8List _cNonce;
  late final String _hello;

  Uint8List? _kSend;
  Uint8List? _kRecv;
  int _sendCtr = 0;
  int _recvCtr = 0;

  /// The text frame to send first.
  String get clientHello => _hello;

  /// The device public key (65 bytes), what the server binds auth to.
  Uint8List get devicePublic => _public(_d);

  /// Checks the server hello against the pinned fingerprint and derives the
  /// keys. Throws [PanelFingerprintMismatch] when the key is not the pinned one.
  void accept(String serverHello, String pinnedFp) {
    if (_kSend != null) throw const PanelE2eError('already accepted');
    Object? json;
    try {
      json = jsonDecode(serverHello);
    } on FormatException {
      throw const PanelE2eError('bad hello');
    }
    if (json is! Map<String, dynamic> || json['v'] != 1) {
      throw const PanelE2eError('bad hello');
    }
    final sBytes = _field(json, 's', _pubLen);
    final s = _parsePublic(sBytes);
    final es = _parsePublic(_field(json, 'e', _pubLen));
    final sNonce = _field(json, 'n', _nonceLen);
    if (!_constantTimeEq(
      utf8.encode(panelFingerprint(sBytes)),
      utf8.encode(pinnedFp),
    )) {
      throw const PanelFingerprintMismatch();
    }
    final ikm = _cat([_ecdh(_ec, es), _ecdh(_ec, s), _ecdh(_d, es)]);
    final transcript = _cat([utf8.encode(_hello), utf8.encode(serverHello)]);
    final hkdf = HKDFKeyDerivator(SHA256Digest())
      ..init(
        HkdfParameters(
          ikm,
          64,
          _cat([_cNonce, sNonce]),
          _cat([_label, _sha256(transcript)]),
        ),
      );
    final okm = Uint8List(64);
    hkdf.deriveKey(null, 0, okm, 0);
    _kSend = okm.sublist(0, 32);
    _kRecv = okm.sublist(32);
  }

  /// Encrypts the next frame (ciphertext then tag).
  Uint8List sealBytes(List<int> plain) {
    final key = _kSend;
    if (key == null) throw const PanelE2eError('not accepted');
    final out = _gcm(true, key, _c2s, _sendCtr, Uint8List.fromList(plain));
    _sendCtr++;
    return out;
  }

  /// Decrypts the next frame; a failure does not advance the counter.
  Uint8List openBytes(List<int> wire) {
    final key = _kRecv;
    if (key == null) throw const PanelE2eError('not accepted');
    final out = _gcm(false, key, _s2c, _recvCtr, Uint8List.fromList(wire));
    _recvCtr++;
    return out;
  }

  /// Seals a JSON message as the server expects (UTF-8 JSON, then AES-GCM).
  Uint8List seal(Map<String, dynamic> message) =>
      sealBytes(utf8.encode(jsonEncode(message)));

  /// Opens a sealed frame into a JSON object.
  Map<String, dynamic> open(List<int> frame) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(openBytes(frame)));
    } on FormatException {
      throw const PanelE2eError('bad frame');
    }
    if (json is! Map<String, dynamic>) throw const PanelE2eError('bad frame');
    return json;
  }
}

Uint8List _gcm(bool seal, Uint8List key, int dir, int ctr, Uint8List data) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      seal,
      AEADParameters(KeyParameter(key), 128, _nonce(dir, ctr), _aad(dir)),
    );
  try {
    return cipher.process(data);
  } on InvalidCipherTextException {
    throw PanelE2eError(seal ? 'seal failed' : 'open failed');
  } on ArgumentError {
    throw PanelE2eError(seal ? 'seal failed' : 'open failed');
  }
}

bool _constantTimeEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var acc = 0;
  for (var i = 0; i < a.length; i++) {
    acc |= a[i] ^ b[i];
  }
  return acc == 0;
}
