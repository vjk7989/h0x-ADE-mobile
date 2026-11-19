import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../conn/machine_connection.dart';
import '../theme/theme_controller.dart' show sharedPrefsProvider;
import 'connections.dart';

/// One machine as the inbox sees it.
class MachineSnapshot {
  const MachineSnapshot({
    required this.info,
    this.state = const Connecting(),
    this.sessions = const [],
    this.loaded = false,
    this.error,
  });

  final MachineInfo info;
  final ConnState state;
  final List<Session> sessions;

  /// Sessions were read at least once (they stay, as the last known state,
  /// when the machine drops).
  final bool loaded;

  /// Why reading sessions failed, or null.
  final String? error;

  bool get offline => state is Failed || state is HostKeyNew || state is HostKeyChanged;

  MachineSnapshot copyWith({
    ConnState? state,
    List<Session>? sessions,
    bool? loaded,
    Object? error = _keep,
  }) =>
      MachineSnapshot(
        info: info,
        state: state ?? this.state,
        sessions: sessions ?? this.sessions,
        loaded: loaded ?? this.loaded,
        error: identical(error, _keep) ? this.error : error as String?,
      );
}

const _keep = Object();

/// A session on a machine, with the inbox's own marks.
class InboxItem {
  const InboxItem({
    required this.machine,
    required this.session,
    required this.unread,
    required this.pinned,
    required this.offline,
  });

  final MachineInfo machine;
  final Session session;
  final bool unread;
  final bool pinned;

  /// Its machine is not reachable now; this is the last known state.
  final bool offline;

  String get key => '${machine.id}/${session.terminal}';
}

class InboxState {
  const InboxState({this.machines = const [], this.pinned = const {}, this.seen = const {}});

  final List<MachineSnapshot> machines;
  final Set<String> pinned;

  /// key -> the status last seen by the person.
  final Map<String, String> seen;

  bool get loading => machines.isNotEmpty && machines.every((m) => !m.loaded && m.error == null && !m.offline);
  bool get allOffline => machines.isNotEmpty && machines.every((m) => m.offline);

  List<InboxItem> items(String query) {
    final q = query.trim().toLowerCase();
    final out = <InboxItem>[];
    for (final m in machines) {
      for (final s in m.sessions) {
        final key = '${m.info.id}/${s.terminal}';
        final item = InboxItem(
          machine: m.info,
          session: s,
          unread: (s.group == AgentGroup.needsYou || s.group == AgentGroup.done) &&
              seen[key] != s.status,
          pinned: pinned.contains(key),
          offline: m.offline,
        );
        if (q.isNotEmpty) {
          final hay = '${s.agent} ${s.name} ${s.folder} ${m.info.name} ${s.message}'.toLowerCase();
          if (!hay.contains(q)) continue;
        }
        out.add(item);
      }
    }
    return out;
  }

  /// Items of one group: pinned first, then unread, then by agent and folder.
  List<InboxItem> group(AgentGroup g, String query) {
    final list = items(query).where((i) => i.session.group == g).toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (a.unread != b.unread) return a.unread ? -1 : 1;
      final byAgent = a.session.agent.compareTo(b.session.agent);
      return byAgent != 0 ? byAgent : a.session.folder.compareTo(b.session.folder);
    });
    return list;
  }

  int get needsYou => items('').where((i) => i.session.group == AgentGroup.needsYou).length;

  InboxState copyWith({
    List<MachineSnapshot>? machines,
    Set<String>? pinned,
    Map<String, String>? seen,
  }) =>
      InboxState(
        machines: machines ?? this.machines,
        pinned: pinned ?? this.pinned,
        seen: seen ?? this.seen,
      );
}

const _kPinned = 'inbox.pinned';

/// Reads every machine's sessions and keeps them current: when a machine
/// becomes ready, when its notices say something changed, and every
/// [pollEvery] (notices only reach an open app, and a missed one must not
/// leave the list stale).
class InboxController {
  InboxController(
    this.connections, {
    this.prefs,
    this.pollEvery = const Duration(seconds: 15),
  }) {
    value.value = InboxState(
      machines: [for (final c in connections) MachineSnapshot(info: c.machine)],
      pinned: {...?prefs?.getStringList(_kPinned)},
    );
  }

  final List<MachineConnection> connections;
  final SharedPreferences? prefs;
  /// Null: no polling (tests).
  final Duration? pollEvery;
  final value = ValueNotifier<InboxState>(const InboxState());
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _timer;
  var _disposed = false;

  void start() {
    for (final c in connections) {
      _subs.add(c.state.listen((s) {
        _set(c, (m) => m.copyWith(state: s));
        if (s is Ready) unawaited(_load(c));
      }));
      _subs.add(c.notices().listen((_) => unawaited(_load(c)), onError: (_) {}));
    }
    final every = pollEvery;
    if (every != null) _timer = Timer.periodic(every, (_) => unawaited(refresh()));
  }

  void _set(MachineConnection c, MachineSnapshot Function(MachineSnapshot) f) {
    if (_disposed) return;
    final i = connections.indexOf(c);
    final ms = [...value.value.machines];
    ms[i] = f(ms[i]);
    value.value = value.value.copyWith(machines: ms);
  }

  Future<void> _load(MachineConnection c) async {
    try {
      final sessions = await c.sessions();
      _set(c, (m) => m.copyWith(sessions: sessions, loaded: true, error: null));
    } catch (e) {
      _set(c, (m) => m.copyWith(error: e.toString(), loaded: true));
    }
  }

  /// Reads every machine that is ready.
  Future<void> refresh() => Future.wait([
        for (final c in connections)
          if (value.value.machines[connections.indexOf(c)].state is Ready) _load(c),
      ]);

  Future<void> retry(MachineConnection c) => _load(c);

  Future<void> togglePin(String key) async {
    final pinned = {...value.value.pinned};
    if (!pinned.remove(key)) pinned.add(key);
    value.value = value.value.copyWith(pinned: pinned);
    await prefs?.setStringList(_kPinned, pinned.toList());
  }

  void markRead(InboxItem item) {
    value.value = value.value.copyWith(
      seen: {...value.value.seen, item.key: item.session.status},
    );
  }

  void markAllRead() {
    final seen = {...value.value.seen};
    for (final i in value.value.items('')) {
      seen[i.key] = i.session.status;
    }
    value.value = value.value.copyWith(seen: seen);
  }

  MachineConnection? connectionFor(String machineId) {
    for (final c in connections) {
      if (c.machine.id == machineId) return c;
    }
    return null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    value.dispose();
  }
}

/// How often the inbox re-reads sessions; null turns polling off.
final inboxPollProvider = Provider<Duration?>((ref) => const Duration(seconds: 15));

final inboxProvider = Provider<InboxController>((ref) {
  final c = InboxController(
    ref.watch(connectionsProvider),
    prefs: _prefs(ref),
    pollEvery: ref.watch(inboxPollProvider),
  )..start();
  ref.onDispose(c.dispose);
  return c;
});

SharedPreferences? _prefs(Ref ref) {
  try {
    return ref.watch(sharedPrefsProvider);
  } catch (_) {
    return null;
  }
}
