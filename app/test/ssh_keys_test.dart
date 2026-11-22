import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyperox/conn/ssh/known_hosts.dart';
import 'package:hyperox/conn/ssh/ssh_keys.dart';

class MemStore implements SecretStore {
  final map = <String, String>{};
  bool throwOnRead = false;

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) throw StateError('keystore reset');
    return map[key];
  }

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

class FlakyStore extends MemStore {
  int failNext = 0;

  @override
  Future<String?> read(String key) async {
    if (failNext > 0) {
      failNext--;
      throw StateError('transient');
    }
    return super.read(key);
  }
}

void main() {
  group('SshKeys', () {
    test('is generated once and then stable', () async {
      final store = MemStore();
      final keys = SshKeys(store, device: 'pixel');
      final a = await keys.ensure();
      final b = await keys.ensure();
      expect(a.addAgain, isFalse);
      expect(b.addAgain, isFalse);
      expect(b.key.publicLine, a.key.publicLine);
      // a second SshKeys over the same storage reads the same key
      expect((await SshKeys(store).ensure()).key.publicLine, a.key.publicLine);
    });

    test('existing() does not generate', () async {
      final store = MemStore();
      expect(await SshKeys(store).existing(), isNull);
      expect(store.map, isEmpty);
    });

    test('the exported line has the OpenSSH shape and parses', () async {
      final line = (await SshKeys(MemStore(), device: 'pixel').ensure()).key.publicLine;
      final parts = line.split(' ');
      expect(parts, hasLength(3));
      expect(parts[0], 'ssh-ed25519');
      expect(parts[2], 'hyperox-pixel');
      final blob = Uint8List.fromList(base64.decode(parts[1]));
      expect(SSHHostKey.getType(blob), 'ssh-ed25519');
      expect(blob, hasLength(4 + 11 + 4 + 32), reason: 'type string + 32-byte key');
    });

    test('the stored private key signs and its public half matches the line', () async {
      final store = MemStore();
      final key = (await SshKeys(store).ensure()).key;
      final pem = store.map[SshKeys.storeKey]!;
      expect(pem, contains('OPENSSH PRIVATE KEY'));
      final pair = SSHKeyPair.fromPem(pem).single as OpenSSHEd25519KeyPair;
      final msg = Uint8List.fromList([1, 2, 3]);
      final sig = pair.sign(msg);
      expect(SSHSignature.getType(sig.encode()), 'ssh-ed25519');
      expect(key.publicLine.split(' ')[1], base64.encode(pair.toPublicKey().encode()));
    });

    test('regenerate gives a different key and asks to add it again', () async {
      final keys = SshKeys(MemStore());
      final a = await keys.ensure();
      final b = await keys.regenerate();
      expect(b.key.publicLine, isNot(a.key.publicLine));
      expect(b.addAgain, isTrue);
      expect((await keys.ensure()).key.publicLine, b.key.publicLine);
    });

    test('a lost keystore makes a new key plus the add-again notice', () async {
      final store = MemStore();
      final keys = SshKeys(store);
      final a = await keys.ensure();
      store.throwOnRead = true;
      expect(await keys.existing(), isNull);
      store.throwOnRead = false;
      store.map[SshKeys.storeKey] = 'garbage, not a pem';
      final b = await keys.ensure();
      expect(b.addAgain, isTrue);
      expect(b.key.publicLine, isNot(a.key.publicLine));
    });

    test('a read error never overwrites the stored key', () async {
      final store = MemStore();
      final a = await SshKeys(store).ensure();
      final pem = store.map[SshKeys.storeKey];
      store.throwOnRead = true;
      await expectLater(SshKeys(store).ensure(), throwsStateError);
      expect(store.map[SshKeys.storeKey], pem);
      store.throwOnRead = false;
      expect((await SshKeys(store).ensure()).key.publicLine, a.key.publicLine);
    });

    test('a single transient read error is retried and the key is kept', () async {
      final store = FlakyStore();
      final a = await SshKeys(store).ensure();
      store.failNext = 1;
      final b = await SshKeys(store).ensure();
      expect(b.addAgain, isFalse);
      expect(b.key.publicLine, a.key.publicLine);
    });

    test('fingerprint matches ssh-keygen -l for a sample key', () {
      // from: ssh-keygen -t ed25519 -f k; ssh-keygen -lf k.pub
      const line =
          'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM0DgHZQtR2Pvk9uF4Lo9Dqp2+yAsAc9I7pke6yX/pIr sample';
      final blob = Uint8List.fromList(base64.decode(line.split(' ')[1]));
      expect(sha256Fingerprint(blob), 'SHA256:+eXtb2qOFLpCvYIKHKqDmKWxIHpIcPN9F1pSLZM8f4I');
    });
  });

  group('KnownHosts', () {
    test('first sight is unknown, then match, then mismatch', () async {
      final kh = KnownHosts(MemStore());
      expect(await kh.check('box', 22, 'SHA256:a'), HostKeyCheck.unknown);
      await kh.trust('box', 22, 'SHA256:a');
      expect(await kh.check('box', 22, 'SHA256:a'), HostKeyCheck.match);
      expect(await kh.check('box', 22, 'SHA256:b'), HostKeyCheck.mismatch);
      expect(await kh.lookup('box', 22), 'SHA256:a');
    });

    test('the same host on another port is a separate entry', () async {
      final kh = KnownHosts(MemStore());
      await kh.trust('box', 22, 'SHA256:a');
      expect(await kh.check('box', 2222, 'SHA256:z'), HostKeyCheck.unknown);
    });

    test('IPv6 literals key with brackets and survive a round trip', () async {
      final store = MemStore();
      final kh = KnownHosts(store);
      await kh.trust('::1', 22, 'SHA256:v6');
      expect(KnownHosts.entryKey('::1', 22), '[::1]:22');
      expect(KnownHosts.entryKey('[::1]', 22), '[::1]:22');
      expect(await KnownHosts(store).check('[::1]', 22, 'SHA256:v6'), HostKeyCheck.match);
    });

    test('replace after a mismatch, forget, and host case', () async {
      final kh = KnownHosts(MemStore());
      await kh.trust('Box.Local', 22, 'SHA256:a');
      expect(await kh.check('box.local', 22, 'SHA256:a'), HostKeyCheck.match);
      await kh.trust('box.local', 22, 'SHA256:new');
      expect(await kh.check('box.local', 22, 'SHA256:new'), HostKeyCheck.match);
      await kh.forget('box.local', 22);
      expect(await kh.lookup('box.local', 22), isNull);
    });

    test('corrupt stored data reads as empty, not a crash', () async {
      final store = MemStore()..map[KnownHosts.storeKey] = '{not json';
      expect(await KnownHosts(store).lookup('x', 22), isNull);
    });
  });
}
