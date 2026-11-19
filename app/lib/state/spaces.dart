import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../conn/machine_connection.dart';
import 'connections.dart';

class SpacesData {
  const SpacesData({
    this.view,
    this.sessions = const {},
    this.loading = true,
    this.error,
    this.offline = false,
  });

  /// The last spaces read (kept when the machine drops: last known layout).
  final SpacesView? view;

  /// Sessions by terminal name and by address, to find what a pane runs.
  final Map<String, Session> sessions;
  final bool loading;
  final String? error;
  final bool offline;

  Session? sessionOf(String pane) => sessions[pane];

  SpacesData copyWith({
    SpacesView? view,
    Map<String, Session>? sessions,
    bool? loading,
    Object? error = _keep,
    bool? offline,
  }) =>
      SpacesData(
        view: view ?? this.view,
        sessions: sessions ?? this.sessions,
        loading: loading ?? this.loading,
        error: identical(error, _keep) ? this.error : error as String?,
        offline: offline ?? this.offline,
      );
}

const _keep = Object();

/// One machine's spaces: loaded on demand, re-read when asked.
class SpacesController {
  SpacesController(this.conn);
  final MachineConnection conn;
  final value = ValueNotifier<SpacesData>(const SpacesData());
  var _disposed = false;

  Future<void> load() async {
    if (_disposed) return;
    value.value = value.value.copyWith(loading: true, error: null);
    try {
      final view = await conn.spaces();
      final sessions = await conn.sessions();
      if (_disposed) return;
      value.value = SpacesData(
        view: view,
        sessions: {
          for (final s in sessions) s.terminal: s,
          for (final s in sessions) if (s.name.isNotEmpty) s.name: s,
        },
        loading: false,
        offline: false,
      );
    } catch (e) {
      if (_disposed) return;
      // StateError('not connected: ...') means the machine is not reachable;
      // anything else is a failure of this read.
      final offline = e is StateError && e.message.startsWith('not connected');
      value.value = value.value.copyWith(
        loading: false,
        offline: offline,
        error: offline ? null : e.toString(),
      );
    }
  }

  void dispose() {
    _disposed = true;
    value.dispose();
  }
}

final spacesControllerProvider = Provider.family<SpacesController, String>((ref, machineId) {
  final conn = ref.watch(connectionsProvider).firstWhere((c) => c.machine.id == machineId);
  final c = SpacesController(conn);
  ref.onDispose(c.dispose);
  return c;
});
