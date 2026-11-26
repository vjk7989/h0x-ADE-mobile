// Interop: a Dart VM client against a real `h0x-core bridge web` on 127.0.0.1,
// in an isolated home. Local only: it needs a built core.
//
//   cd app && H0X_CORE_BIN=<path to h0x-core> flutter test test/panel_interop_test.dart
//
// Without H0X_CORE_BIN every test here is skipped (CI never sets it).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/machine_connection.dart';
import 'package:hyperox/conn/panel/e2e.dart';
import 'package:hyperox/conn/panel/panel_connection.dart';
import 'package:hyperox/conn/panel/panel_link.dart';
import 'package:hyperox/data/panel_machines_repo.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Plain implements PanelSocket {
  _Plain(this._ch);
  final WebSocketChannel _ch;
  @override
  Stream<Object?> get messages => _ch.stream;
  @override
  void send(Object data) => _ch.sink.add(data);
  @override
  Future<void> close() => _ch.sink.close();
}

/// The local panel is plain ws on 127.0.0.1; the app always asks for wss.
Future<PanelSocket> _local(Uri url) async {
  final ch = IOWebSocketChannel.connect(url.replace(scheme: 'ws'));
  await ch.ready;
  return _Plain(ch);
}

void main() {
  final bin = Platform.environment['H0X_CORE_BIN'];
  final skip = bin == null || bin.isEmpty ? 'set H0X_CORE_BIN to a built h0x-core to run' : null;

  Process? core;
  Directory? home;
  late String base;
  late String code;
  late String fp;

  setUpAll(() async {
    if (skip != null) return;
    home = await Directory.systemTemp.createTemp('h0x-interop-');
    final h = home!.path;
    final env = {
      'H0X_CORE_SESSION': 'interop${pid % 100000}',
      'H0X_CORE_SOCKET': '',
      'XDG_CONFIG_HOME': '$h/config',
      'XDG_STATE_HOME': '$h/state',
      'XDG_DATA_HOME': '$h/data',
      'XDG_RUNTIME_DIR': '$h/run',
      'APPDATA': '$h/appdata',
      'LOCALAPPDATA': '$h/localappdata',
      'HOME': h,
      'USERPROFILE': h,
    };
    _env = env;
    core = await Process.start(bin!, ['bridge', 'web', '--json', '--port', '0'], environment: env);
    unawaited(core!.stderr.drain<void>());
    final line = await core!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 30));
    final json = jsonDecode(line) as Map<String, dynamic>;
    final url = Uri.parse(json['url'] as String);
    base = 'https://${url.host}:${url.port}';
    final fragment = Uri.parse(json['pair'] as String).fragment;
    final parts = Uri.splitQueryString(fragment);
    code = parts['pair']!;
    fp = parts['fp']!;
  });

  tearDownAll(() async {
    core?.kill();
    await core?.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    try {
      await home?.delete(recursive: true);
    } catch (_) {}
  });

  group('real core panel', () {
    test('a wrong fingerprint is a hard stop and the code is not used up', () async {
      final bad = PanelLink(baseUrl: base, code: code, fp: panelB64(List.filled(32, 7)));
      await expectLater(
        pairWithPanel(bad, label: 'phone', connect: _local),
        throwsA(isA<PanelFingerprintMismatch>()),
      );
    }, skip: skip);

    test('pairs, signs in again with the saved session, and lists sessions', () async {
      final p = await pairWithPanel(
        PanelLink(baseUrl: base, code: code, fp: fp),
        label: 'interop phone',
        connect: _local,
      );
      expect(p.device, 'interop phone');

      final machine = PanelMachine(id: 'i1', name: 'local', baseUrl: base, fp: fp);
      final c = PanelMachineConnection(
        panel: machine,
        secrets: () async => p.secrets,
        connect: _local,
        timeout: const Duration(seconds: 10),
      );
      addTearDown(c.close);
      expect(await c.start(), isA<Ready>());
      expect(await c.sessions(), isA<List<Session>>());
    }, skip: skip);

    test('a used code is refused', () async {
      await expectLater(
        pairWithPanel(PanelLink(baseUrl: base, code: code, fp: fp), label: 'again', connect: _local),
        throwsA(isA<PanelPairException>()),
      );
    }, skip: skip);

    test('a session from another device key says scan again', () async {
      // pair one device, then use its session with a different device key
      final p = await pairWithPanel(
        PanelLink(baseUrl: base, code: await _newCode(), fp: fp),
        label: 'second',
        connect: _local,
      );
      final other = PanelSecrets(
        token: p.secrets.token,
        deviceKey: panelB64(PanelChannel.newDeviceSecret()),
      );
      final c = PanelMachineConnection(
        panel: PanelMachine(id: 'i2', name: 'local', baseUrl: base, fp: fp),
        secrets: () async => other,
        connect: _local,
        timeout: const Duration(seconds: 10),
      );
      addTearDown(c.close);
      expect(await c.start(), isA<ScanAgain>());
    }, skip: skip);
  });
}

/// A fresh one-time code: the core prints one per `bridge pair --transport web`.
Future<String> _newCode() async {
  final r = await Process.run(
    Platform.environment['H0X_CORE_BIN']!,
    ['bridge', 'pair', '--transport', 'web', '--json'],
    environment: _env,
  );
  final out = jsonDecode((r.stdout as String).trim().split('\n').last) as Map<String, dynamic>;
  return (out['code'] ?? out['pair']).toString();
}

/// The isolated home of the core under test, set once in setUpAll.
Map<String, String> _env = const {};
