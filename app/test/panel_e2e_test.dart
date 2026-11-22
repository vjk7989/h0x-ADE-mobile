// Fixture source: vjk7989/h0x-ADE-core 8d75449bbbdc3bd879c188e18faaa16c54b4e670, crates/h0x-core/src/bridge/web/e2e_vectors.json (byte copy).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/panel/e2e.dart';

Uint8List unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
]);

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final v =
      jsonDecode(File('test/fixtures/panel_e2e_vectors.json').readAsStringSync())
          as Map<String, dynamic>;

  PanelChannel start() => PanelChannel.start(
    unhex(v['d_priv'] as String),
    ephemeralSecret: unhex(v['ec_priv'] as String),
    nonce: unhex(v['c_nonce'] as String),
  );

  PanelChannel accepted() =>
      start()..accept(v['server_hello'] as String, v['fp'] as String);

  test('hello, public key and fingerprint match the vectors', () {
    final c = start();
    expect(c.clientHello, v['client_hello']);
    expect(hex(c.devicePublic), v['d_pub']);
    expect(panelFingerprint(unhex(v['s_pub'] as String)), v['fp']);
  });

  test('c2s frames seal to the frozen wire bytes', () {
    final c = accepted();
    for (final f in (v['frames']['c2s'] as List)) {
      expect(hex(c.sealBytes(utf8.encode(f['plain'] as String))), f['wire']);
    }
  });

  test('s2c frames open to the frozen plaintext', () {
    final c = accepted();
    for (final f in (v['frames']['s2c'] as List)) {
      expect(utf8.decode(c.openBytes(unhex(f['wire'] as String))), f['plain']);
    }
  });

  test('open parses a JSON object frame', () {
    final c = accepted();
    final first = (v['frames']['s2c'] as List).first;
    expect(c.open(unhex(first['wire'] as String)), {'name': 'pong'});
  });

  test('fingerprint mismatch is a hard error', () {
    final c = start();
    expect(
      () => c.accept(v['server_hello'] as String, 'A' * 43),
      throwsA(isA<PanelFingerprintMismatch>()),
    );
  });

  test('replayed and out-of-order frames are rejected', () {
    final s2c = v['frames']['s2c'] as List;
    final c = accepted();
    expect(() => c.openBytes(unhex(s2c[1]['wire'] as String)), throwsA(isA<PanelE2eError>()));
    c.openBytes(unhex(s2c[0]['wire'] as String));
    expect(() => c.openBytes(unhex(s2c[0]['wire'] as String)), throwsA(isA<PanelE2eError>()));
    c.openBytes(unhex(s2c[1]['wire'] as String));
  });

  test('a tampered frame and a short frame are rejected', () {
    final wire = unhex((v['frames']['s2c'] as List)[0]['wire'] as String);
    wire[0] ^= 1;
    expect(() => accepted().openBytes(wire), throwsA(isA<PanelE2eError>()));
    expect(() => accepted().openBytes(Uint8List(3)), throwsA(isA<PanelE2eError>()));
  });

  test('malformed hellos are rejected', () {
    final bad = [
      '',
      '[]',
      '{"v":2}',
      (v['server_hello'] as String).replaceFirst('"v":1', '"v":2'),
      (v['server_hello'] as String).replaceFirst('"n":"', '"n":"A'),
      (v['server_hello'] as String).replaceFirst('"s":"B', '"s":"C'),
    ];
    for (final h in bad) {
      expect(() => start().accept(h, v['fp'] as String), throwsA(isA<PanelE2eError>()));
    }
  });

  test('seal and open need an accepted channel', () {
    expect(() => start().sealBytes([1]), throwsA(isA<PanelE2eError>()));
  });

  test('bad secrets are rejected and fresh ones are valid', () {
    expect(() => PanelChannel.start(Uint8List(32)), throwsA(isA<PanelE2eError>()));
    expect(() => PanelChannel.start(Uint8List(31)), throwsA(isA<PanelE2eError>()));
    final a = PanelChannel.newDeviceSecret();
    expect(a.length, 32);
    expect(PanelChannel.start(a).devicePublic.length, 65);
  });

  test('base64url is strict', () {
    expect(panelUnb64('AQI'), [1, 2]);
    for (final t in ['AQI=', 'AQJ', 'A', 'A+B_', 'AQ I']) {
      expect(() => panelUnb64(t), throwsA(isA<PanelE2eError>()));
    }
  });

  test('a failed accept kills the channel', () {
    final c = start();
    expect(() => c.accept('{}', v['fp'] as String), throwsA(isA<PanelE2eError>()));
    expect(() => c.accept(v['server_hello'] as String, v['fp'] as String), throwsA(isA<PanelE2eError>()));
    expect(() => c.sealBytes([1]), throwsA(isA<PanelE2eError>()));
  });

  test('accept is one-shot', () {
    final c = accepted();
    expect(() => c.accept(v['server_hello'] as String, v['fp'] as String), throwsA(isA<PanelE2eError>()));
  });
}
