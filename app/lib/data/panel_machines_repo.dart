import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/ssh.dart';
import '../theme/theme_controller.dart';

/// One computer paired by scanning the desktop panel QR. The session token and
/// the device key live in the secret store, never here.
class PanelMachine {
  const PanelMachine({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.fp,
    this.label = '',
  });

  final String id;
  final String name;

  /// `https://host[:port]`; https only.
  final String baseUrl;

  /// Fingerprint of the panel's certificate key, from the QR.
  final String fp;
  final String label;

  PanelMachine copyWith({String? name}) =>
      PanelMachine(id: id, name: name ?? this.name, baseUrl: baseUrl, fp: fp, label: label);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'fp': fp,
    if (label.isNotEmpty) 'label': label,
  };

  factory PanelMachine.fromJson(Map<String, Object?> j) {
    final url = j['baseUrl']! as String;
    if (!url.startsWith('https://')) throw const FormatException('https only');
    return PanelMachine(
      id: j['id']! as String,
      name: j['name']! as String,
      baseUrl: url,
      fp: j['fp']! as String,
      label: j['label'] is String ? j['label']! as String : '',
    );
  }
}

/// The secrets of one panel machine: the 30-day session token and the device
/// private key (both base64 or opaque strings).
class PanelSecrets {
  const PanelSecrets({required this.token, required this.deviceKey});
  final String token;
  final String deviceKey;
}

const _kPanelMachines = 'panel.machines';
String _tokenKey(String id) => 'hyperox.panel.$id.token.v1';
String _deviceKeyKey(String id) => 'hyperox.panel.$id.key.v1';

class PanelMachinesController extends Notifier<List<PanelMachine>> {
  @override
  List<PanelMachine> build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_kPanelMachines);
    if (raw == null) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    if (decoded is! List<Object?>) return const [];
    final out = <PanelMachine>[];
    for (final m in decoded) {
      try {
        out.add(PanelMachine.fromJson(m! as Map<String, Object?>));
      } catch (_) {}
    }
    return out;
  }

  /// Saves the secrets first, then the machine. False when the same panel
  /// (base URL) is already paired.
  Future<bool> add(PanelMachine m, PanelSecrets secrets) async {
    if (state.any((o) => o.baseUrl == m.baseUrl)) return false;
    final store = ref.read(secretStoreProvider);
    await store.write(_tokenKey(m.id), secrets.token);
    await store.write(_deviceKeyKey(m.id), secrets.deviceKey);
    state = [...state, m];
    await _save();
    return true;
  }

  Future<void> rename(String id, String name) async {
    final n = name.trim();
    if (n.isEmpty || n.length > 64) throw ArgumentError('Name must be 1 to 64 characters');
    state = [for (final m in state) m.id == id ? m.copyWith(name: n) : m];
    await _save();
  }

  /// Removes the machine and its secrets.
  Future<void> remove(String id) async {
    state = [for (final m in state) if (m.id != id) m];
    await _save();
    final store = ref.read(secretStoreProvider);
    await store.delete(_tokenKey(id));
    await store.delete(_deviceKeyKey(id));
  }

  /// The secrets, or null when storage definitively has none. A read error is
  /// retried once, then thrown: it must never look like "no secrets", and
  /// nothing is written on that path.
  Future<PanelSecrets?> secrets(String id) async {
    final store = ref.read(secretStoreProvider);
    Future<String?> read(String key) async {
      try {
        return await store.read(key);
      } catch (_) {
        try {
          return await store.read(key);
        } catch (e) {
          throw StateError('cannot read the pairing secrets: $e; try again');
        }
      }
    }

    final token = await read(_tokenKey(id));
    final key = await read(_deviceKeyKey(id));
    if (token == null || key == null) return null;
    return PanelSecrets(token: token, deviceKey: key);
  }

  Future<void> _save() => ref
      .read(sharedPrefsProvider)
      .setString(_kPanelMachines, jsonEncode([for (final m in state) m.toJson()]));
}

final panelMachinesProvider =
    NotifierProvider<PanelMachinesController, List<PanelMachine>>(PanelMachinesController.new);
