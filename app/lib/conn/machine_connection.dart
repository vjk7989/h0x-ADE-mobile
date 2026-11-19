/// The one interface screens see (protocol.md section 3.11). Relay and SSH
/// transports implement it; nothing above this file knows which is in use.
library;

enum ConnMode { cloud, ssh }

class MachineInfo {
  const MachineInfo({
    required this.id,
    required this.name,
    required this.os,
    required this.mode,
    required this.online,
  });

  final String id;
  final String name;

  /// `linux`, `macos`, `windows`, or `unknown` until the machine says.
  final String os;
  final ConnMode mode;
  final bool online;
}

sealed class ConnState {
  const ConnState();
}

class Connecting extends ConnState {
  const Connecting();
}

/// Cloud only: the computer must approve this phone; [code] is shown to the user.
class NeedsApproval extends ConnState {
  const NeedsApproval(this.code);
  final String code;
}

/// First sight of a host key (SSH TOFU): the user must accept [fingerprint].
class HostKeyNew extends ConnState {
  const HostKeyNew(this.fingerprint);
  final String fingerprint;
}

/// The host key differs from the stored one: a blocking warning.
/// Only an explicit "replace key" (see SshMachineConnection) continues.
class HostKeyChanged extends ConnState {
  const HostKeyChanged({required this.known, required this.offered});
  final String known;
  final String offered;
}

class Ready extends ConnState {
  const Ready();
}

class Failed extends ConnState {
  const Failed(this.reason);
  final String reason;
}

/// What an agent needs from the person, for the inbox groups.
enum AgentGroup { needsYou, working, done, idle }

class Session {
  const Session({
    required this.terminal,
    required this.name,
    required this.agent,
    required this.folder,
    required this.status,
    required this.live,
    this.blockedKind,
    this.message = '',
  });

  /// The terminal address (`t7`), what every other call takes.
  final String terminal;
  final String name;
  final String agent;
  final String folder;

  /// The program's own word: idle, working, done, blocked, error; or `''`
  /// when it never reported one.
  final String status;
  final bool live;

  /// For `blocked`: permission, question or auth (null when not said).
  final String? blockedKind;
  final String message;

  AgentGroup get group {
    if (!live) return AgentGroup.idle;
    switch (status) {
      case 'blocked':
      case 'error':
        return AgentGroup.needsYou;
      case 'working':
        return AgentGroup.working;
      case 'done':
        return AgentGroup.done;
      default:
        return AgentGroup.idle;
    }
  }

  /// The relay's `sessions` entry: `{address,name,agent,folder,status,live}`.
  /// Unknown fields are ignored; a missing required one is a FormatException.
  factory Session.fromJson(Map<String, dynamic> j) {
    String req(String k) {
      final v = j[k];
      if (v is! String) throw FormatException('session: missing "$k"');
      return v;
    }

    final live = j['live'];
    if (live is! bool) throw const FormatException('session: missing "live"');
    return Session(
      terminal: req('address'),
      name: (j['name'] as String?) ?? '',
      agent: (j['agent'] as String?) ?? '',
      folder: (j['folder'] as String?) ?? '',
      status: req('status'),
      live: live,
      blockedKind: j['kind'] as String?,
      message: (j['msg'] as String?) ?? '',
    );
  }
}

class SpaceTab {
  const SpaceTab({required this.name, required this.panes});
  final String name;
  final List<String> panes;
}

class Space {
  const Space({required this.name, required this.folder, this.tabs = const []});
  final String name;
  final String folder;
  final List<SpaceTab> tabs;
}

class AgentSlot {
  const AgentSlot({required this.slot, required this.name, required this.command});
  final int slot;
  final String name;
  final String command;
}

class SpacesView {
  const SpacesView({
    this.spaces = const [],
    this.agents = const [],
    this.supported = true,
  });

  /// What a transport that cannot read spaces returns.
  const SpacesView.unsupported()
      : spaces = const [],
        agents = const [],
        supported = false;

  final List<Space> spaces;
  final List<AgentSlot> agents;
  final bool supported;

  /// `{spaces:[{name,folder,tabs:[{name,panes:[..]}]}],agents:[{slot,name,command}]}`;
  /// the old `[{name,folder}]` array form is accepted too.
  factory SpacesView.fromJson(Object? json) {
    final Object? rawSpaces;
    final Object? rawAgents;
    if (json is List) {
      rawSpaces = json;
      rawAgents = const [];
    } else if (json is Map) {
      rawSpaces = json['spaces'];
      rawAgents = json['agents'] ?? const [];
    } else {
      throw const FormatException('spaces: not an object or list');
    }
    if (rawSpaces is! List || rawAgents is! List) {
      throw const FormatException('spaces: "spaces"/"agents" must be lists');
    }
    String str(Map<String, dynamic> m, String k) {
      final v = m[k];
      if (v is! String) throw FormatException('spaces: missing "$k"');
      return v;
    }

    return SpacesView(
      spaces: [
        for (final s in rawSpaces.cast<Map<String, dynamic>>())
          Space(
            name: str(s, 'name'),
            folder: str(s, 'folder'),
            tabs: [
              for (final t in ((s['tabs'] ?? const []) as List).cast<Map<String, dynamic>>())
                SpaceTab(
                  name: str(t, 'name'),
                  panes: [...((t['panes'] ?? const []) as List).cast<String>()],
                ),
            ],
          ),
      ],
      agents: [
        for (final a in rawAgents.cast<Map<String, dynamic>>())
          AgentSlot(
            slot: a['slot'] is int
                ? a['slot'] as int
                : throw const FormatException('spaces: missing "slot"'),
            name: str(a, 'name'),
            command: str(a, 'command'),
          ),
      ],
    );
  }
}

/// A key as core names it: `enter`, `esc`, `tab`, `up`, `ctrl+c`, `alt+x`, `f5`, `a`.
class Key {
  const Key(this.name);
  final String name;

  static const enter = Key('enter');
  static const esc = Key('esc');
  static const tab = Key('tab');
  static const up = Key('up');
  static const down = Key('down');
  static const left = Key('left');
  static const right = Key('right');
  static const ctrlC = Key('ctrl+c');

  @override
  bool operator ==(Object other) => other is Key && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'Key($name)';
}

class TermSize {
  const TermSize(this.cols, this.rows);
  final int cols;
  final int rows;

  @override
  bool operator ==(Object other) => other is TermSize && other.cols == cols && other.rows == rows;

  @override
  int get hashCode => Object.hash(cols, rows);

  @override
  String toString() => '${cols}x$rows';
}

class TermView {
  const TermView({
    required this.initial,
    required this.bytes,
    required this.sizes,
    required this.close,
  });

  /// The size when the view opened; the first paint in [bytes] is for it.
  final TermSize initial;
  final Stream<List<int>> bytes;

  /// A new size arrives before the bytes painted for it.
  final Stream<TermSize> sizes;
  final Future<void> Function() close;
}

sealed class Reply {
  const Reply();
}

class Done extends Reply {
  const Done([this.detail = const {}]);

  /// Transport detail (for example `status`, `turn`, `outcome`); may be empty.
  final Map<String, Object?> detail;
}

class NeedsConfirm extends Reply {
  const NeedsConfirm(this.token, this.what);
  final String token;
  final String what;
}

class Locked extends Reply {
  const Locked();
}

class RateLimited extends Reply {
  const RateLimited(this.secs);
  final int secs;
}

class ReplyFailed extends Reply {
  const ReplyFailed(this.message);
  final String message;
}

class NotPaired extends Reply {
  const NotPaired();
}

class Notice {
  const Notice({
    required this.terminal,
    required this.agent,
    required this.folder,
    required this.kind,
    required this.excerpt,
  });
  final String terminal;
  final String agent;
  final String folder;

  /// needs_you, done, error, finished.
  final String kind;
  final String excerpt;
}

abstract class MachineConnection {
  MachineInfo get machine;
  Stream<ConnState> get state;
  Future<List<Session>> sessions();
  Future<SpacesView> spaces();
  Future<String> read(String terminal, {int lines = 50});
  Future<Reply> send(String terminal, String text);
  Future<Reply> keys(String terminal, List<Key> keys);
  Future<Reply> approve(String terminal);
  Future<Reply> deny(String terminal);
  Future<Reply> interrupt(String terminal);
  Future<Reply> kill(String terminal);
  Future<Reply> run(String folder, String command);
  Future<Reply> confirm(String token);

  /// The terminal's size in cells (what the program draws for).
  Future<TermSize> size(String terminal);

  /// Watch a terminal: raw VT bytes (colour included) and its size changes.
  /// Pausing the `bytes` subscription pauses the machine (flow control);
  /// cancelling it, or [TermView.close], detaches. There is no `resize`: an
  /// observer never resizes a terminal (core: observe = watch only).
  Future<TermView> view(String terminal, {int history = 5000});
  Stream<Notice> notices();
  Future<void> close();
}
