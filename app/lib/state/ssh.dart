import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../conn/ssh/known_hosts.dart';
import '../conn/ssh/ssh_keys.dart';

final secretStoreProvider = Provider<SecretStore>((ref) => FlutterSecretStore());

final sshKeysProvider = Provider<SshKeys>((ref) => SshKeys(ref.watch(secretStoreProvider)));

final knownHostsProvider = Provider<KnownHosts>((ref) => KnownHosts(ref.watch(secretStoreProvider)));

/// Copy and Share of the public key line (tests replace both).
final copyTextProvider = Provider<Future<void> Function(String)>(
  (ref) => (text) => Clipboard.setData(ClipboardData(text: text)),
);

final shareTextProvider = Provider<Future<void> Function(String)>(
  (ref) => (text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  },
);
