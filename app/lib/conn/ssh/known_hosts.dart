import 'dart:convert';

import 'ssh_keys.dart';

/// What the stored fingerprint says about a host key just offered.
enum HostKeyCheck { unknown, match, mismatch }

/// Trust on first use, per `host:port`. Fingerprints are `SHA256:...` strings.
class KnownHosts {
  KnownHosts(this._store);

  static const storeKey = 'hyperox.ssh.known_hosts.v1';
  final SecretStore _store;

  /// `host:port`; an IPv6 literal is bracketed: `[::1]:22`.
  static String entryKey(String host, int port) {
    final h = host.contains(':') && !host.startsWith('[') ? '[$host]' : host;
    return '${h.toLowerCase()}:$port';
  }

  Future<Map<String, String>> _all() async {
    final raw = await _store.read(storeKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  /// Every trusted host: `host:port` to its fingerprint, in name order.
  Future<Map<String, String>> entries() async {
    final all = await _all();
    return {for (final k in all.keys.toList()..sort()) k: all[k]!};
  }

  /// Forgets one entry by its `host:port` key (as listed by [entries]).
  Future<void> forgetEntry(String key) async {
    final all = await _all();
    if (all.remove(key) != null) await _store.write(storeKey, jsonEncode(all));
  }

  Future<String?> lookup(String host, int port) async => (await _all())[entryKey(host, port)];

  Future<HostKeyCheck> check(String host, int port, String fingerprint) async {
    final known = await lookup(host, port);
    if (known == null) return HostKeyCheck.unknown;
    return known == fingerprint ? HostKeyCheck.match : HostKeyCheck.mismatch;
  }

  /// Accept a new key, or replace a changed one (the explicit "Replace key").
  Future<void> trust(String host, int port, String fingerprint) async {
    final all = await _all();
    all[entryKey(host, port)] = fingerprint;
    await _store.write(storeKey, jsonEncode(all));
  }

  Future<void> forget(String host, int port) async {
    final all = await _all();
    if (all.remove(entryKey(host, port)) != null) {
      await _store.write(storeKey, jsonEncode(all));
    }
  }
}
