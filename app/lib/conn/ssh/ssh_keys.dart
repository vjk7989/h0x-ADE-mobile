import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:pointycastle/digests/sha256.dart';

/// Where secrets live. Production: Android Keystore-backed secure storage.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecretStore implements SecretStore {
  FlutterSecretStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// `SHA256:<base64 without padding>` of an SSH public key blob, as
/// `ssh-keygen -l` prints it.
String sha256Fingerprint(Uint8List keyBlob) {
  final digest = SHA256Digest().process(keyBlob);
  return 'SHA256:${base64.encode(digest).replaceAll('=', '')}';
}

class PhoneKey {
  PhoneKey._(this.pair);
  final OpenSSHEd25519KeyPair pair;

  Uint8List get _blob => pair.toPublicKey().encode();

  /// `ssh-ed25519 AAAA... hyperox-<device>`: the line for `authorized_keys`.
  String get publicLine => 'ssh-ed25519 ${base64.encode(_blob)} ${pair.comment}';

  String get fingerprint => sha256Fingerprint(_blob);
}

class KeyResult {
  const KeyResult(this.key, {required this.addAgain});
  final PhoneKey key;

  /// True when this key replaces one that existed (regenerated, or the stored
  /// one was lost): the user must add the new public line to every machine again.
  final bool addAgain;
}

/// The phone's own ed25519 key. The private key (OpenSSH PEM) is only ever in
/// the [SecretStore].
class SshKeys {
  SshKeys(this._store, {this.device = 'phone'});

  static const storeKey = 'hyperox.ssh.key.v1';
  final SecretStore _store;
  final String device;

  Future<PhoneKey?> _load() async {
    final String? pem;
    try {
      pem = await _store.read(storeKey);
    } catch (_) {
      return null; // keystore reset: the entry cannot be decrypted
    }
    if (pem == null) return null;
    try {
      final pairs = SSHKeyPair.fromPem(pem);
      final pair = pairs.whereType<OpenSSHEd25519KeyPair>().firstOrNull;
      return pair == null ? null : PhoneKey._(pair);
    } catch (_) {
      return null;
    }
  }

  /// The stored key, or null when there is none (does not generate).
  Future<PhoneKey?> existing() => _load();

  /// The key, generated on first use. Idempotent: later calls return the same
  /// key. [KeyResult.addAgain] is true only when a stored key was lost.
  Future<KeyResult> ensure() async {
    final have = await _load();
    if (have != null) return KeyResult(have, addAgain: false);
    final lost = await _hadEntry();
    return KeyResult(await _generate(), addAgain: lost);
  }

  /// A new key replaces the old one. The old public line stops working.
  Future<KeyResult> regenerate() async => KeyResult(await _generate(), addAgain: true);

  Future<bool> _hadEntry() async {
    try {
      return await _store.read(storeKey) != null;
    } catch (_) {
      return true;
    }
  }

  Future<PhoneKey> _generate() async {
    final sk = nacl.SigningKey.generate();
    final pair = OpenSSHEd25519KeyPair(
      Uint8List.fromList(sk.verifyKey.asTypedList),
      Uint8List.fromList(sk.asTypedList), // seed + public, 64 bytes
      'hyperox-$device',
    );
    await _store.write(storeKey, pair.toPem());
    return PhoneKey._(pair);
  }
}
