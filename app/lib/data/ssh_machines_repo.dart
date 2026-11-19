import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/theme_controller.dart';

/// One SSH machine saved on this phone.
class SshMachine {
  const SshMachine({
    required this.id,
    required this.name,
    required this.host,
    required this.user,
    this.port = 22,
    this.tailscale = false,
    this.corePath = '',
  });

  final String id;
  final String name;

  /// Host name, IPv4, Tailscale name, or an IPv6 literal without brackets.
  final String host;
  final String user;
  final int port;

  /// Tailscale SSH: no key is offered, the tailnet authorises.
  final bool tailscale;

  /// Where h0x-core is on that machine when it is not in a usual place; '' means search.
  final String corePath;

  /// `user@host:port`, with an IPv6 host in brackets.
  String get address =>
      '$user@${host.contains(':') ? '[$host]' : host}:$port';

  SshMachine copyWith({String? name, String? corePath}) => SshMachine(
    id: id,
    name: name ?? this.name,
    host: host,
    user: user,
    port: port,
    tailscale: tailscale,
    corePath: corePath ?? this.corePath,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'user': user,
    'port': port,
    'tailscale': tailscale,
    if (corePath.isNotEmpty) 'corePath': corePath,
  };

  factory SshMachine.fromJson(Map<String, Object?> j) => SshMachine(
    id: j['id']! as String,
    name: j['name']! as String,
    host: j['host']! as String,
    user: j['user']! as String,
    port: j['port']! as int,
    tailscale: (j['tailscale'] as bool?) ?? false,
    corePath: j['corePath'] is String ? j['corePath']! as String : '',
  );

  /// The same login target (a duplicate is refused).
  bool sameTarget(SshMachine o) =>
      host.toLowerCase() == o.host.toLowerCase() &&
      port == o.port &&
      user == o.user;
}

/// A core path as typed or pasted: trimmed, and one pair of quotes around the
/// whole path (Explorer's "Copy as path" adds them) removed.
String cleanCorePath(String raw) {
  var p = raw.trim();
  if (p.length >= 2 && (p[0] == '"' || p[0] == "'") && p[p.length - 1] == p[0]) {
    p = p.substring(1, p.length - 1).trim();
  }
  return p;
}

final _hostName = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$');
final _ipv6 = RegExp(r'^[0-9A-Fa-f:.]+(%[A-Za-z0-9._-]+)?$');

/// Strips the brackets of an IPv6 literal and trims.
String normalizeHost(String raw) {
  final t = raw.trim();
  if (t.startsWith('[') && t.endsWith(']')) {
    return t.substring(1, t.length - 1);
  }
  return t;
}

/// An error message, or null when [raw] is a usable host.
String? validateHost(String raw) {
  final h = normalizeHost(raw);
  if (h.isEmpty) return 'Enter a host, IP or Tailscale name';
  if (h.contains(RegExp(r'\s'))) return 'A host has no spaces';
  if (h.contains(':')) {
    return _ipv6.hasMatch(h) ? null : 'Not a valid IPv6 address';
  }
  return _hostName.hasMatch(h) ? null : 'Not a valid host name';
}

String? validatePort(String raw) {
  final p = int.tryParse(raw.trim());
  if (p == null || p < 1 || p > 65535) return 'Port is 1 to 65535';
  return null;
}

String? validateUser(String raw) {
  final u = raw.trim();
  if (u.isEmpty) return 'Enter the user name on that machine';
  if (u.contains(RegExp(r'\s'))) return 'A user name has no spaces';
  return null;
}

String? validateName(String raw) {
  final n = raw.trim();
  if (n.isEmpty || n.length > 64) return 'Name must be 1 to 64 characters';
  return null;
}

const _kMachines = 'ssh.machines';

class SshMachinesController extends Notifier<List<SshMachine>> {
  @override
  List<SshMachine> build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_kMachines);
    if (raw == null) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      // A damaged store must not stop the app: start empty.
      return const [];
    }
    if (decoded is! List<Object?>) return const [];
    // One bad entry is skipped; the others stay.
    final out = <SshMachine>[];
    for (final m in decoded) {
      try {
        out.add(SshMachine.fromJson(m! as Map<String, Object?>));
      } catch (_) {}
    }
    return out;
  }

  /// False when the same user@host:port is already saved.
  Future<bool> add(SshMachine m) async {
    if (state.any(m.sameTarget)) return false;
    state = [...state, m];
    await _save();
    return true;
  }

  Future<void> rename(String id, String name) async {
    final err = validateName(name);
    if (err != null) throw ArgumentError(err);
    state = [
      for (final m in state) m.id == id ? m.copyWith(name: name.trim()) : m,
    ];
    await _save();
  }

  /// Sets where h0x-core is on that machine ('' goes back to searching).
  Future<void> setCorePath(String id, String path) async {
    state = [
      for (final m in state) m.id == id ? m.copyWith(corePath: cleanCorePath(path)) : m,
    ];
    await _save();
  }

  Future<void> remove(String id) async {
    state = [for (final m in state) if (m.id != id) m];
    await _save();
  }

  Future<void> _save() => ref
      .read(sharedPrefsProvider)
      .setString(_kMachines, jsonEncode([for (final m in state) m.toJson()]));
}

final sshMachinesProvider =
    NotifierProvider<SshMachinesController, List<SshMachine>>(
      SshMachinesController.new,
    );
