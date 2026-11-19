import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../widgets/hx_icon_compat.dart';
import '../conn/machine_connection.dart';
import '../state/connections.dart';
import '../state/spaces.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../widgets/app_shell.dart';
import '../widgets/hx.dart';
import '../widgets/hx_bits.dart';
import '../widgets/hx_icons.dart';

/// A machine's spaces, tabs and split panes as a read-only map (design: Spaces).
class SpacesScreen extends ConsumerStatefulWidget {
  const SpacesScreen({super.key, this.onOpenPane, this.onNavigate});

  /// Opens a pane's terminal (default: the router's agent route).
  final void Function(MachineInfo machine, String terminal)? onOpenPane;
  final void Function(NavDest dest)? onNavigate;

  @override
  ConsumerState<SpacesScreen> createState() => _SpacesScreenState();
}

class _SpacesScreenState extends ConsumerState<SpacesScreen> {
  String? _machineId;
  String? _loadedFor;
  int _selSpace = 0;
  int _selTab = 0;

  MachineConnection? _conn(List<MachineConnection> all) {
    if (all.isEmpty) return null;
    for (final c in all) {
      if (c.machine.id == _machineId) return c;
    }
    return all.first;
  }

  void _openPane(MachineConnection conn, String terminal) {
    if (widget.onOpenPane != null) {
      widget.onOpenPane!(conn.machine, terminal);
    } else {
      context.push('/agent/${conn.machine.id}/$terminal');
    }
  }

  Future<void> _pickMachine(List<MachineConnection> all, MachineConnection current) async {
    final picked = await showModalBottomSheet<MachineConnection>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in all)
              ListTile(
                minTileHeight: 56,
                leading: const Icon(Icons.computer_outlined),
                title: Text(c.machine.name),
                subtitle: Text(c.machine.online ? 'online' : 'offline'),
                trailing: c.machine.id == current.machine.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _machineId = picked.machine.id;
        _selSpace = 0;
        _selTab = 0;
      });
    }
  }

  Future<void> _startAgent(MachineConnection conn, Space space, SpacesView view) async {
    final slot = await showModalBottomSheet<AgentSlot>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SlotsSheet(space: space, machine: conn.machine, slots: view.agents),
    );
    if (slot == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _StartDialog(slot: slot, space: space, machine: conn.machine),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    var r = await conn.run(space.folder, slot.command);
    if (r is NeedsConfirm) r = await conn.confirm(r.token);
    messenger.showSnackBar(SnackBar(
      content: Text(r is Done ? 'Started ${slot.name}' : _failText(r)),
    ));
    if (r is Done) await ref.read(spacesControllerProvider(conn.machine.id)).load();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(connectionsProvider);
    final conn = _conn(all);
    if (conn == null) {
      return ScreenBody(
        body: Column(
          children: [
            const ScreenHeader(title: 'Spaces'),
            Expanded(
              child: _Message(
                icon: Icons.dashboard_outlined,
                title: 'No machines yet',
                text: 'Add a machine to see its spaces.',
                action: 'Add machine',
                onAction: () => (widget.onNavigate ?? (d) => context.go(d.path))(NavDest.machines),
              ),
            ),
          ],
        ),
      );
    }
    final controller = ref.watch(spacesControllerProvider(conn.machine.id));
    if (_loadedFor != conn.machine.id) {
      _loadedFor = conn.machine.id;
      Future<void>.microtask(controller.load);
    }
    return ScreenBody(
      body: ValueListenableBuilder<SpacesData>(
        valueListenable: controller.value,
        builder: (context, data, _) => _body(context, all, conn, controller, data),
      ),
    );
  }

  Widget _body(BuildContext context, List<MachineConnection> all, MachineConnection conn,
      SpacesController controller, SpacesData data) {
    final c = context.hx.colors;
    final wide = MediaQuery.sizeOf(context).width >= kRailBreakpoint;
    final view = data.view;
    final count = view?.spaces.length ?? 0;
    final subtitle = data.loading && view == null
        ? 'loading…'
        : data.offline
            ? 'last known'
            : view == null
                ? conn.machine.name
                : count == 0
                    ? 'no spaces'
                    : '${conn.machine.name} · $count space${count == 1 ? '' : 's'}';
    final header = ScreenHeader(title: 'Spaces', subtitle: subtitle);
    final picker = _MachineChip(
      machine: conn.machine,
      offline: data.offline,
      onTap: all.length > 1 ? () => _pickMachine(all, conn) : null,
    );

    final notes = <Widget>[
      if (data.offline)
        _Note(
          icon: Icons.cloud_off_outlined,
          title: '${conn.machine.name} is offline',
          text: 'This is the last known layout. Panes open again when it is back.',
        ),
      if (view != null && !view.supported)
        _Note(
          icon: Icons.warning_amber_outlined,
          title: 'Update HyperOx on this computer',
          text: "This computer's h0x-core is too old to share its spaces. "
              'Agents still show in the Inbox.',
          action: 'Open Inbox',
          onAction: () => (widget.onNavigate ?? (d) => context.go(d.path))(NavDest.inbox),
        ),
      if (data.error != null)
        _Note(icon: Icons.error_outline, title: "Spaces didn't load", text: data.error!),
    ];

    Widget content;
    if (data.loading && view == null) {
      content = ListView(
        padding: const EdgeInsets.all(16),
        children: [for (var i = 0; i < 2; i++) const _SkeletonSpace()],
      );
    } else if (view == null || !view.supported) {
      content = ListView(padding: const EdgeInsets.only(bottom: 16), children: notes);
    } else if (view.spaces.isEmpty) {
      content = ListView(children: [
        ...notes,
        _Message(
          icon: Icons.dashboard_outlined,
          title: 'No spaces on ${conn.machine.name}',
          text: 'Spaces are made on the computer. You can still start an agent here; '
              'it opens in the home folder.',
          action: 'Start agent',
          onAction: data.offline
              ? null
              : () => _startAgent(conn, const Space(name: 'home', folder: '~'), view),
        ),
      ]);
    } else if (wide) {
      content = _wide(context, conn, controller, data, view, notes);
    } else {
      content = RefreshIndicator(
        onRefresh: controller.load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: [
              ...notes,
              for (final s in view.spaces)
                _SpaceCard(
                  space: s,
                  data: data,
                  enabled: !data.offline,
                  stack: MediaQuery.textScalerOf(context).scale(14) >= 21,
                  onStart: () => _startAgent(conn, s, view),
                  onPane: (t) => _openPane(conn, t),
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        header,
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: picker),
        Expanded(child: ColoredBox(color: c.screen, child: content)),
      ],
    );
  }

  /// The selected tab's panes side by side, filling the height, each with
  /// the live last lines (spaces board 03). Four or more wrap in rows of two.
  Widget _widePanes(MachineConnection conn, SpacesData data, List<String> panes) {
    Widget card(String pane) => _PaneCard(
      pane: pane,
      session: data.sessionOf(pane),
      conn: conn,
      preview: true,
      expand: true,
      onTap: () {
        final s = data.sessionOf(pane);
        if (s != null) _openPane(conn, s.terminal);
      },
    );
    final perRow = panes.length <= 3 ? panes.length : 2;
    final rows = (panes.length / perRow).ceil();
    return Column(
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < perRow; j++) ...[
                  if (j > 0) const SizedBox(width: 8),
                  Expanded(
                    child: r * perRow + j < panes.length
                        ? card(panes[r * perRow + j])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _wide(BuildContext context, MachineConnection conn, SpacesController controller,
      SpacesData data, SpacesView view, List<Widget> notes) {
    final c = context.hx.colors;
    final si = _selSpace.clamp(0, view.spaces.length - 1);
    final space = view.spaces[si];
    final ti = space.tabs.isEmpty ? -1 : _selTab.clamp(0, space.tabs.length - 1);
    return Row(
      children: [
        SizedBox(
          width: 260,
          child: ListView(
            children: [
              for (var i = 0; i < view.spaces.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(children: [
                    Expanded(child: Text(view.spaces[i].name, style: HxType.heading)),
                    Text(shortFolder(view.spaces[i].folder),
                        style: HxType.mono.copyWith(color: c.muted)),
                  ]),
                ),
                if (view.spaces[i].tabs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('no tabs', style: HxType.mono.copyWith(color: c.muted)),
                  ),
                for (var j = 0; j < view.spaces[i].tabs.length; j++)
                  _TabRow(
                    name: view.spaces[i].tabs[j].name,
                    panes: view.spaces[i].tabs[j].panes.length,
                    selected: i == si && j == ti,
                    onTap: () => setState(() {
                      _selSpace = i;
                      _selTab = j;
                    }),
                  ),
              ],
            ],
          ),
        ),
        VerticalDivider(width: 1, color: c.hairline),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...notes,
              Row(children: [
                Expanded(
                  child: Text(ti < 0 ? space.name : '${space.name} · ${space.tabs[ti].name}',
                      style: HxType.titleLg),
                ),
                _StartButton(enabled: !data.offline, onTap: () => _startAgent(conn, space, view)),
              ]),
              const SizedBox(height: 12),
              if (ti < 0)
                const _NoTabs()
              else
                SizedBox(
                  height: (MediaQuery.sizeOf(context).height - 200).clamp(240.0, 680.0),
                  child: _widePanes(conn, data, space.tabs[ti].panes),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _failText(Reply r) => switch (r) {
      ReplyFailed(:final message) => message,
      Locked() => 'The computer is locked.',
      RateLimited(:final secs) => 'Too many requests. Try again in $secs s.',
      NotPaired() => 'This phone is not approved on that computer.',
      NeedsConfirm() => 'Needs confirmation.',
      Done() => 'Done.',
    };

class _MachineChip extends StatelessWidget {
  const _MachineChip({required this.machine, required this.offline, required this.onTap});
  final MachineInfo machine;
  final bool offline;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final state = offline ? 'offline' : 'online';
    final big = MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.5;
    final stateText = Text(
      '● $state',
      style: HxType.mono.copyWith(color: offline ? c.muted : c.ok),
    );
    return Semantics(
      button: onTap != null,
      label: 'Machine: ${machine.name}, $state${onTap != null ? ', change' : ''}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.computer_outlined, size: 20, color: c.foreground),
                  const SizedBox(width: 10),
                  Expanded(
                    child: big
                        // From 1.5x the tag and state go on a second line.
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                machine.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HxType.heading,
                              ),
                              Wrap(
                                spacing: 8,
                                children: [ModeTag(machine.mode), stateText],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Flexible(
                                child: Text(
                                  machine.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: HxType.heading,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ModeTag(machine.mode),
                              const SizedBox(width: 8),
                              stateText,
                            ],
                          ),
                  ),
                  if (onTap != null) Icon(Icons.unfold_more, size: 20, color: c.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, required this.text, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HxBanner(title: title, message: text, kind: HxBannerKind.info),
            if (action != null) HxButton(label: action!, onPressed: onAction, minHeight: 48),
          ],
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String text;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: c.muted),
            const SizedBox(height: 16),
            Text(title, style: HxType.titleSm, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text, style: HxType.body.copyWith(color: c.muted), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            HxButton(label: action, kind: HxButtonKind.primary, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}

class _SkeletonSpace extends StatelessWidget {
  const _SkeletonSpace();

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: 'Loading spaces',
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.hairline),
          ),
        ),
      ),
    );
  }
}

/// A tonal button: the `selected` fill, a Lucide `play`, "Start agent"
/// 13.5/600, 48 dp tall, radius 12 (spaces board 01).
class _StartButton extends StatelessWidget {
  const _StartButton({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = dark ? c.accent : c.foreground;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Start agent',
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Material(
          color: c.selected,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? onTap : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HxIcon('play', size: 18, color: tint),
                  const SizedBox(width: 6),
                  Text(
                    'Start agent',
                    style: HxType.weight(HxType.bodyLg, 600).copyWith(fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoTabs extends StatelessWidget {
  const _NoTabs();

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.outline),
      ),
      child: Text('No tabs: start an agent to open one',
          textAlign: TextAlign.center, style: HxType.caption.copyWith(color: c.muted)),
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({required this.name, required this.panes, required this.selected, required this.onTap});
  final String name;
  final int panes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Tab $name, $panes pane${panes == 1 ? '' : 's'}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? c.selected : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(Icons.dashboard_outlined, size: 18, color: selected ? c.foreground : c.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: HxType.body)),
            Text('$panes pane${panes == 1 ? '' : 's'}',
                style: HxType.mono.copyWith(color: selected ? c.foreground : c.muted)),
          ]),
        ),
      ),
    );
  }
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({
    required this.space,
    required this.data,
    required this.enabled,
    required this.stack,
    required this.onStart,
    required this.onPane,
  });

  final Space space;
  final SpacesData data;
  final bool enabled;
  final bool stack;
  final VoidCallback onStart;
  final void Function(String terminal) onPane;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: HxCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(space.name, style: HxType.heading),
                      Text(
                        '${shortFolder(space.folder)} · ${space.tabs.length} tab${space.tabs.length == 1 ? '' : 's'}',
                        style: HxType.mono.copyWith(color: c.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StartButton(enabled: enabled, onTap: onStart),
              ],
            ),
            if (space.tabs.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 12), child: _NoTabs()),
            for (final tab in space.tabs) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Text(tab.name, style: HxType.bodySm.copyWith(color: c.muted)),
              ),
              _paneGrid(tab.panes),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pane(String pane) {
    final s = data.sessionOf(pane);
    return _PaneCard(
      pane: pane,
      session: s,
      conn: null,
      preview: false,
      onTap: s == null ? null : () => onPane(s.terminal),
    );
  }

  /// The panes of a tab, side by side as on the board: 1 pane full width,
  /// 2 or 3 in one row of equal panes, 4 or more in rows of two. At large
  /// text they stack as a list. Panes are 104 dp tall (128 for 3).
  Widget _paneGrid(List<String> panes) {
    if (panes.isEmpty) return const SizedBox.shrink();
    if (stack) {
      return Column(
        children: [
          for (final p in panes)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: _pane(p)),
        ],
      );
    }
    final perRow = panes.length <= 3 ? panes.length : 2;
    final height = panes.length == 3 ? 128.0 : 104.0;
    final rows = <Widget>[];
    for (var i = 0; i < panes.length; i += perRow) {
      final slice = panes.sublist(i, (i + perRow).clamp(0, panes.length));
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + perRow < panes.length ? 8 : 0),
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < perRow; j++) ...[
                  if (j > 0) const SizedBox(width: 8),
                  Expanded(
                    child: j < slice.length ? _pane(slice[j]) : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _PaneCard extends StatelessWidget {
  const _PaneCard({
    required this.pane,
    required this.session,
    required this.conn,
    required this.preview,
    required this.onTap,
    this.expand = false,
  });

  final String pane;
  final Session? session;
  final MachineConnection? conn;
  final bool preview;
  final VoidCallback? onTap;

  /// Fill the height the parent gives (the wide layout).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final s = session;
    final finished = s == null || !s.live;
    final g = s?.group ?? AgentGroup.idle;
    final word = finished ? 'exited' : groupWord(g, kind: s.blockedKind);
    final tone = finished ? c.muted : groupColor(c, g);
    final needs = !finished && g == AgentGroup.needsYou;
    final command = s == null ? '' : s.agent;
    final label = '$pane${command.isEmpty ? '' : ', $command'}, $word';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // A needs-you pane has a 1.5 dp `working` edge; the others a hairline
        // on `well` (dark) or #f6f6f4 (light).
        color: dark ? c.well : c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: needs ? c.working : (finished ? c.outline : c.hairline),
          width: needs ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                pane,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HxType.weight(HxType.bodyLg, 600).copyWith(fontSize: 13.5),
              ),
            ),
          ]),
          if (command.isNotEmpty)
            Text(
              command,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HxType.mono.copyWith(color: c.muted, fontSize: 11.5),
            ),
          if (preview && conn != null && s != null)
            Flexible(child: _Preview(conn: conn!, terminal: s.terminal)),
          if (expand) const Spacer() else const SizedBox(height: 6),
          HxTag(word, color: tone),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(borderRadius: BorderRadius.circular(10), onTap: onTap, child: card),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.conn, required this.terminal});
  final MachineConnection conn;
  final String terminal;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return FutureBuilder<String>(
      future: conn.read(terminal, lines: 6).catchError((_) => ''),
      builder: (context, snap) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          snap.data ?? '',
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: HxType.mono.copyWith(fontSize: 11, color: c.muted),
        ),
      ),
    );
  }
}

class _SlotsSheet extends StatelessWidget {
  const _SlotsSheet({required this.space, required this.machine, required this.slots});
  final Space space;
  final MachineInfo machine;
  final List<AgentSlot> slots;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Start an agent', style: HxType.titleSm),
            Text('in ${space.name} · ${shortFolder(space.folder)} · new tab',
                style: HxType.mono.copyWith(color: c.muted)),
            const SizedBox(height: 12),
            if (slots.isEmpty)
              Text('This computer has no agent slots. Set them in its Settings › Agents.',
                  style: HxType.body.copyWith(color: c.muted)),
            for (final s in slots)
              Semantics(
                button: true,
                label: 'Start ${s.name}, slot ${s.slot}',
                excludeSemantics: true,
                onTap: () => Navigator.pop(context, s),
                child: InkWell(
                  onTap: () => Navigator.pop(context, s),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.well, borderRadius: BorderRadius.circular(8)),
                        child: Text('${s.slot}', style: HxType.mono),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(s.name, style: HxType.bodyLg),
                            Text(s.command, style: HxType.mono.copyWith(color: c.muted)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text("Slots mirror the computer's Settings › Agents.",
                style: HxType.caption.copyWith(color: c.muted)),
          ],
        ),
      ),
    );
  }
}

class _StartDialog extends StatelessWidget {
  const _StartDialog({required this.slot, required this.space, required this.machine});
  final AgentSlot slot;
  final Space space;
  final MachineInfo machine;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return AlertDialog(
      backgroundColor: c.card,
      title: Text('Start ${slot.name}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Runs ${slot.command} in ${shortFolder(space.folder)} on ${machine.name}, in a new tab of ${space.name}.',
              style: HxType.body),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.well, borderRadius: BorderRadius.circular(10)),
            child: Text('\$ ${slot.command}', style: HxType.mono),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          autofocus: false,
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Start'),
        ),
      ],
    );
  }
}
