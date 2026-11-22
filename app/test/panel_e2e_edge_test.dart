// Edge cases for the panel E2E channel; the vectors are the core's frozen contract
// (crates/h0x-core/src/bridge/web/e2e.rs, e2e_vectors.json).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/panel/e2e.dart';
import 'package:pointycastle/export.dart' as pc;

Uint8List unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
]);

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

final p = BigInt.parse(
  'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
  radix: 16,
);
final b = BigInt.parse(
  '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',
  radix: 16,
);
final n = BigInt.parse(
  'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',
  radix: 16,
);

Uint8List be(BigInt v, int len) => unhex(v.toRadixString(16).padLeft(len * 2, '0'));

BigInt toInt(List<int> bytes) => BigInt.parse(hex(bytes), radix: 16);

/// SEC1 uncompressed encoding of (x, y), without any range or curve check.
Uint8List point(BigInt x, BigInt y) => Uint8List.fromList([4, ...be(x, 32), ...be(y, 32)]);

/// Reference AES-256-GCM frame as the spec defines it (nonce dir||ctr, AAD label||dir).
Uint8List gcm(bool seal, List<int> key, int dir, int ctr, List<int> data) {
  final nonce = Uint8List(12);
  ByteData.view(nonce.buffer)
    ..setUint32(0, dir)
    ..setUint64(4, ctr);
  final aad = Uint8List.fromList([...utf8.encode('h0x-bridge v1'), 0, 0, 0, dir]);
  final cipher = pc.GCMBlockCipher(pc.AESEngine())
    ..init(
      seal,
      pc.AEADParameters(pc.KeyParameter(Uint8List.fromList(key)), 128, nonce, aad),
    );
  return cipher.process(Uint8List.fromList(data));
}

final rejected = throwsA(
  allOf(isA<PanelE2eError>(), isNot(isA<PanelFingerprintMismatch>())),
);

void main() {
  final v =
      jsonDecode(File('test/fixtures/panel_e2e_vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  final serverHello = v['server_hello'] as String;
  final fields = jsonDecode(serverHello) as Map<String, dynamic>;
  final fp = v['fp'] as String;
  final kC2s = unhex(v['k_c2s'] as String);
  final kS2c = unhex(v['k_s2c'] as String);
  final s2c = v['frames']['s2c'] as List;
  final c2s = v['frames']['c2s'] as List;

  PanelChannel start() => PanelChannel.start(
    unhex(v['d_priv'] as String),
    ephemeralSecret: unhex(v['ec_priv'] as String),
    nonce: unhex(v['c_nonce'] as String),
  );

  PanelChannel accepted() => start()..accept(serverHello, fp);

  /// The server hello in the server's own field order, with fields swapped in.
  String hello({String v = '1', String? s, String? e, String? n, String extra = ''}) =>
      '{"v":$v,"s":"${s ?? fields['s']}","e":"${e ?? fields['e']}",'
      '"n":"${n ?? fields['n']}"$extra}';

  /// A valid P-256 point with a small x (so x + p still fits in 32 bytes).
  (BigInt, BigInt) smallPoint() {
    for (var x = BigInt.zero; ; x += BigInt.one) {
      final rhs = (x * x * x - BigInt.from(3) * x + b) % p;
      final y = rhs.modPow((p + BigInt.one) >> 2, p);
      if ((y * y) % p == rhs) return (x, y);
    }
  }

  test('the helpers reproduce the frozen server hello and c2s frame', () {
    expect(hello(), serverHello);
    expect(hex(gcm(true, kC2s, 1, 0, [])), c2s[0]['wire']);
  });

  test('server keys that are not valid uncompressed P-256 points are rejected', () {
    final s = unhex(v['s_pub'] as String);
    final (x, y) = (toInt(s.sublist(1, 33)), toInt(s.sublist(33)));
    final bad = <List<int>>[
      [0], // SEC1 point at infinity
      point(BigInt.zero, BigInt.zero), // identity as 65 zero-ish bytes
      [2, ...s.sublist(1, 33)], // compressed form of the real key
      [2, ...s.sublist(1)], // 65 bytes with a compressed prefix
      s.sublist(0, 64),
      [...s, 0],
      Uint8List(0),
      point(x, y + BigInt.one), // off the curve
      point(x, (p - BigInt.one)), // off the curve, y at the top of the field
      point(p, y), // x == p
      Uint8List.fromList([4, ...List.filled(64, 0xff)]), // x, y > p
    ];
    for (final key in bad) {
      final k = panelB64(key);
      expect(
        () => start().accept(hello(s: k), panelFingerprint(key)),
        rejected,
        reason: 's = ${hex(key)}',
      );
      expect(() => start().accept(hello(e: k), fp), rejected, reason: 'e = ${hex(key)}');
    }
  });

  test('a coordinate written as itself plus p is rejected though its residue is on the curve', () {
    final (x, y) = smallPoint();
    final good = point(x, y);
    start().accept(hello(s: panelB64(good)), panelFingerprint(good));
    final big = point(x + p, y);
    expect(
      () => start().accept(hello(s: panelB64(big)), panelFingerprint(big)),
      rejected,
    );
    expect(() => start().accept(hello(e: panelB64(big)), fp), rejected);
  });

  test('a server nonce of 0, 31 or 33 bytes is rejected', () {
    for (final len in [0, 31, 33, 64]) {
      expect(
        () => start().accept(hello(n: panelB64(Uint8List(len))), fp),
        rejected,
        reason: 'len $len',
      );
    }
    start().accept(hello(n: panelB64(Uint8List(32))), fp);
  });

  test('unknown hello fields are accepted and the changed transcript fails the first frame', () {
    for (final extra in [',"x":"y"', ',"z":{"a":[1,null]}', ',"":0']) {
      final c = start()..accept(hello(extra: extra), fp);
      expect(
        () => c.openBytes(unhex(s2c[0]['wire'] as String)),
        rejected,
        reason: extra,
      );
    }
  });

  test('a duplicate hello field is rejected like the rust server', () {
    for (final extra in [',"v":1', ',"n":"${fields['n']}"', ',"s":"${fields['s']}"']) {
      expect(() => start().accept(hello(extra: extra), fp), rejected, reason: extra);
    }
  });

  test('versions other than the integer 1 are rejected', () {
    for (final ver in ['0', '2', '"1"', '-1', 'null', 'true', '[1]', '18446744073709551617']) {
      expect(() => start().accept(hello(v: ver), fp), rejected, reason: 'v = $ver');
    }
    expect(
      () => start().accept(serverHello.replaceFirst('"v":1,', ''), fp),
      rejected,
      reason: 'v missing',
    );
  });

  test('a float version is rejected like the rust server', () {
    for (final ver in ['1.0', '1e0']) {
      expect(() => start().accept(hello(v: ver), fp), rejected, reason: 'v = $ver');
    }
  });

  test('a pinned fingerprint that is not the exact canonical text is a mismatch', () {
    expect(fp, contains('_'));
    for (final pin in [
      '$fp=',
      fp.substring(0, 42),
      '${fp}A',
      fp.replaceAll('_', '/'),
      fp.replaceAll('K', '+'),
      fp.toLowerCase(),
      ' $fp',
      '',
    ]) {
      expect(
        () => start().accept(serverHello, pin),
        throwsA(isA<PanelFingerprintMismatch>()),
        reason: 'pin "$pin"',
      );
    }
  });

  test('accept called twice is refused and keeps the first keys', () {
    final c = accepted();
    expect(() => c.accept(serverHello, fp), rejected);
    expect(() => c.accept(hello(n: panelB64(Uint8List(32))), fp), rejected);
    expect(hex(c.sealBytes([])), c2s[0]['wire']);
    expect(utf8.decode(c.openBytes(unhex(s2c[0]['wire'] as String))), s2c[0]['plain']);
  });

  test('every frame operation before accept is refused', () {
    final c = start();
    expect(() => c.sealBytes([]), rejected);
    expect(() => c.seal({}), rejected);
    expect(() => c.openBytes(unhex(s2c[0]['wire'] as String)), rejected);
    expect(() => c.open(unhex(s2c[0]['wire'] as String)), rejected);
  });

  test('a frame sealed for the c2s direction does not open as s2c', () {
    final mine = accepted().sealBytes(utf8.encode('{"name":"ping"}'));
    expect(() => accepted().openBytes(mine), rejected);
    expect(() => accepted().openBytes(unhex(c2s[0]['wire'] as String)), rejected);
    final plain = utf8.encode('{}');
    // Right key, wrong direction in nonce and AAD; and the c2s key with the s2c direction.
    expect(() => accepted().open(gcm(true, kS2c, 1, 0, plain)), rejected);
    expect(() => accepted().open(gcm(true, kC2s, 2, 0, plain)), rejected);
    expect(accepted().open(gcm(true, kS2c, 2, 0, plain)), isEmpty);
  });

  test('a frame for a counter ahead of the expected one is rejected', () {
    final c = accepted();
    expect(() => c.open(gcm(true, kS2c, 2, 5, utf8.encode('{}'))), rejected);
    expect(c.open(gcm(true, kS2c, 2, 0, utf8.encode('{}'))), isEmpty);
  });

  // Counter exhaustion near 2^64 is not tested: the counters are private and reaching
  // them needs 2^63+ frames.

  test('failed opens of every kind do not advance the counter', () {
    final c = accepted();
    final first = unhex(s2c[0]['wire'] as String);
    final tampered = Uint8List.fromList(first)..[first.length - 1] ^= 1;
    for (final wire in [<int>[], Uint8List(15), tampered, unhex(c2s[1]['wire'] as String)]) {
      expect(() => c.openBytes(wire), rejected);
      expect(() => c.open(wire), rejected);
    }
    expect(c.open(first), {'name': 'pong'});
    expect(utf8.decode(c.openBytes(unhex(s2c[1]['wire'] as String))), 'x');
  });

  test('an empty map and a 64 KiB message seal to the spec frames', () {
    final c = accepted();
    final big = {'data': 'a' * 65536};
    final w0 = c.seal({});
    final w1 = c.seal(big);
    expect(w0.length, 2 + 16);
    expect(utf8.decode(gcm(false, kC2s, 1, 0, w0)), '{}');
    expect(w1.length, jsonEncode(big).length + 16);
    expect(utf8.decode(gcm(false, kC2s, 1, 1, w1)), jsonEncode(big));
  });

  test('an empty map and a 64 KiB server frame open', () {
    final c = accepted();
    final big = jsonEncode({'data': 'é' * 32768});
    expect(c.open(gcm(true, kS2c, 2, 0, utf8.encode('{}'))), isEmpty);
    final got = c.open(gcm(true, kS2c, 2, 1, utf8.encode(big)));
    expect(got['data'], 'é' * 32768);
  });

  test('a tag-only frame opens to empty bytes but not to a JSON object', () {
    final wire = gcm(true, kS2c, 2, 0, []);
    expect(wire.length, 16);
    expect(accepted().openBytes(wire), isEmpty);
    expect(() => accepted().open(wire), rejected);
  });

  test('non-UTF-8, non-JSON and non-object plaintexts are an open error', () {
    final plains = <List<int>>[
      [0xff, 0xfe, 0xfd],
      [0xc3], // truncated UTF-8 sequence
      utf8.encode('not json'),
      utf8.encode('{"a":'),
      utf8.encode('[1,2]'),
      utf8.encode('[]'),
      utf8.encode('null'),
      utf8.encode('"s"'),
      utf8.encode('7'),
    ];
    for (final plain in plains) {
      expect(
        () => accepted().open(gcm(true, kS2c, 2, 0, plain)),
        rejected,
        reason: hex(plain),
      );
    }
  });

  test('two channels with the same device secret send different hellos', () {
    final d = unhex(v['d_priv'] as String);
    final a = jsonDecode(PanelChannel.start(d).clientHello) as Map<String, dynamic>;
    final c = jsonDecode(PanelChannel.start(d).clientHello) as Map<String, dynamic>;
    expect(a['d'], c['d']);
    expect(hex(panelUnb64(a['d'] as String)), v['d_pub']);
    expect(a['e'], isNot(c['e']));
    expect(a['n'], isNot(c['n']));
    expect(panelUnb64(a['n'] as String).length, 32);
    expect(panelUnb64(a['e'] as String).length, 65);
  });

  test('fresh device secrets are 32 bytes, distinct and in 1..n-1', () {
    final seen = <String>{};
    for (var i = 0; i < 300; i++) {
      final s = PanelChannel.newDeviceSecret();
      expect(s.length, 32);
      final d = toInt(s);
      expect(d > BigInt.zero && d < n, isTrue, reason: hex(s));
      expect(seen.add(hex(s)), isTrue);
    }
  });

  test('device and ephemeral secrets outside 1..n-1 or not 32 bytes are rejected', () {
    final bad = <Uint8List>[
      Uint8List.fromList(List.filled(32, 0xff)),
      be(n, 32),
      be(n + BigInt.one, 32),
      Uint8List(0),
      Uint8List(33)..[32] = 1,
      Uint8List.fromList([0, ...unhex(v['d_priv'] as String)]),
    ];
    for (final s in bad) {
      expect(() => PanelChannel.start(s), rejected, reason: hex(s));
      expect(
        () => PanelChannel.start(unhex(v['d_priv'] as String), ephemeralSecret: s),
        rejected,
        reason: 'ephemeral ${hex(s)}',
      );
    }
    expect(PanelChannel.start(be(n - BigInt.one, 32)).devicePublic.length, 65);
    expect(PanelChannel.start(be(BigInt.one, 32)).devicePublic.length, 65);
  });

  test('a client nonce that is not 32 bytes is rejected', () {
    final d = unhex(v['d_priv'] as String);
    for (final len in [0, 31, 33]) {
      expect(() => PanelChannel.start(d, nonce: Uint8List(len)), rejected, reason: 'len $len');
    }
  });
}
