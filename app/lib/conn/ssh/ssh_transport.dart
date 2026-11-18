import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'core_rpc.dart';
import 'ssh_keys.dart';

/// A failure retrying cannot fix (login refused, host key refused, bad setup).
/// Its [message] is shown to the user as is.
class SshFatal implements Exception {
  SshFatal(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One running remote command: stdout is the [ByteLink] input.
abstract class RemoteProcess implements ByteLink {
  Stream<List<int>> get stderr;

  /// The exit status, or null when the server reports none or [timeout] passed.
  Future<int?> exitCode({Duration timeout = const Duration(seconds: 2)});
}

/// Called with the key type and its `SHA256:...` fingerprint; false refuses.
typedef HostKeyVerifier = FutureOr<bool> Function(String type, String fingerprint);

/// An authenticated SSH session that can run commands.
abstract class SshTransport {
  /// Completes when the session is up; throws [SshFatal] when retrying is pointless.
  Future<void> connect();
  Future<RemoteProcess> exec(String command);

  /// Completes when the session ends, for any reason.
  Future<void> get done;
  Future<void> close();
}

typedef SshTransportFactory = SshTransport Function({
  required String host,
  required int port,
  required String username,
  required PhoneKey? key,
  required HostKeyVerifier verify,
});

SshTransport dartssh2Transport({
  required String host,
  required int port,
  required String username,
  required PhoneKey? key,
  required HostKeyVerifier verify,
}) =>
    _Dartssh2Transport(host, port, username, key, verify);

class _Dartssh2Transport implements SshTransport {
  _Dartssh2Transport(this.host, this.port, this.username, this.key, this.verify);
  final String host;
  final int port;
  final String username;
  final PhoneKey? key;
  final HostKeyVerifier verify;
  SSHClient? _client;

  @override
  Future<void> connect() async {
    final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 10));
    final client = _client = SSHClient(
      socket,
      username: username,
      // No key (Tailscale SSH): the client offers the `none` method and the
      // tailnet decides.
      identities: key == null ? null : [key!.pair],
      onVerifyHostKey: verify,
    );
    try {
      await client.authenticated;
    } on SSHAuthError {
      throw SshFatal(key == null
          ? 'login refused: this machine does not accept a login without a key'
          : 'login refused: add the phone key to ~/.ssh/authorized_keys on this machine');
    } on SSHHostkeyError {
      throw SshFatal('host key refused');
    }
  }

  @override
  Future<RemoteProcess> exec(String command) async =>
      _Process(await _client!.execute(command));

  @override
  Future<void> get done => _client?.done ?? Future<void>.value();

  @override
  Future<void> close() async => _client?.close();
}

class _Process implements RemoteProcess {
  _Process(this._s);
  final SSHSession _s;

  @override
  Stream<List<int>> get input => _s.stdout;

  @override
  Stream<List<int>> get stderr => _s.stderr;

  @override
  void write(List<int> bytes) => _s.write(Uint8List.fromList(bytes));

  @override
  Future<int?> exitCode({Duration timeout = const Duration(seconds: 2)}) async {
    try {
      return await _s.waitForExit(timeout: timeout);
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<void> close() async => _s.close();
}

/// Reads a process stream to the end as text; a stream error ends it quietly.
Future<String> readAll(Stream<List<int>> s) async {
  final bytes = <int>[];
  try {
    await for (final c in s) {
      bytes.addAll(c);
    }
  } catch (_) {}
  return utf8.decode(bytes, allowMalformed: true);
}
