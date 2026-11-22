import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../widgets/hx_icon_compat.dart';
import '../config.dart';
import '../conn/machine_connection.dart';
import '../conn/machine_directory.dart';
import '../data/machine_status.dart';
import '../data/ssh_gateway.dart';
import '../data/panel_machines_repo.dart';
import '../data/ssh_machines_repo.dart';
import '../session_state.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../state/inbox.dart';
import '../widgets/app_shell.dart';
import '../widgets/hx.dart';
import '../widgets/hx_bits.dart';
import '../widgets/hx_refresh.dart';
import '../widgets/hx_transitions.dart';
import '../widgets/machine_sheets.dart';
import '../widgets/status_motion.dart';

String osLabel(String os) => switch (os) {
  'linux' => 'Linux',
  'macos' => 'macOS',
  'windows' => 'Windows',
  'unix' => 'Unix',
  _ => 'Unknown OS',
};

/// The state word of a row: online, offline, blocked, or checking.
String stateWord(MachineEntry e) {
  final s = e.status;
  if (e.ssh == null) return e.info.online ? 'online' : 'offline';
  if (s == null) return 'checking';
  if (s.hostKeyChanged) return 'blocked';
  if (s.online) return 'online';
  return 'offline';
}

/// The row's one screen-reader sentence: name, OS, mode, state.
String rowLabel(MachineEntry e) {
  final word = stateWord(e);
  final mode = e.mode == ConnMode.ssh ? 'SSH' : 'account';
  final state = word == 'blocked' ? 'host key changed, blocked' : word;
  return '${e.info.name}, ${osLabel(e.info.os)}, $mode, $state';
}

/// One list for both modes, grouped by how the phone reaches the machine.
class MachinesScreen extends ConsumerStatefulWidget {
  const MachinesScreen({super.key});

  @override
  ConsumerState<MachinesScreen> createState() => _MachinesScreenState();
}

class _MachinesScreenState extends ConsumerState<MachinesScreen> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(machineStatusProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final entries = MachineDirectory.merge(
      cloud: ref.watch(cloudMachinesProvider),
      ssh: ref.watch(sshMachinesProvider),
      panel: ref.watch(panelMachinesProvider),
      status: ref.watch(machineStatusProvider),
    );
    final account = [for (final e in entries) if (e.ssh == null) e];
    final ssh = [for (final e in entries) if (e.ssh != null) e];
    final online = entries.where((e) => stateWord(e) == 'online').length;
    final wide = MediaQuery.sizeOf(context).width >= kRailBreakpoint;
    MachineEntry? picked;
    for (final e in entries) {
      if (e.info.id == _selected) picked = e;
    }
    picked ??= entries.isEmpty ? null : entries.first;
    final selectedId = wide ? picked?.info.id : null;
    void select(MachineEntry e) => setState(() => _selected = e.info.id);

    final list = Stack(
      children: [
        SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text('Machines', style: HxType.title),
                          ),
                          if (entries.isNotEmpty)
                            Text(
                              '${entries.length} '
                              '${entries.length == 1 ? 'machine' : 'machines'}'
                              ' · $online online',
                              style: HxType.mono.copyWith(
                                color: c.muted,
                                fontSize: 11.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More options',
                      onSelected: (v) {
                        if (v == 'refresh') {
                          ref.read(machineStatusProvider.notifier).refresh();
                        } else {
                          context.push('/settings/theme');
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                        PopupMenuItem(value: 'theme', child: Text('Theme')),
                      ],
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const _EmptyState()
                    : HxRefresh(
                        onRefresh: ref.read(machineStatusProvider.notifier).refresh,
                        child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
                        children: [
                          if (account.isNotEmpty)
                            _Section(
                              label: 'ACCOUNT',
                              entries: account,
                              selectedId: selectedId,
                              onSelect: wide ? select : null,
                            ),
                          if (ssh.isNotEmpty)
                            _Section(
                              label: 'SSH · THIS PHONE',
                              entries: ssh,
                              selectedId: selectedId,
                              onSelect: wide ? select : null,
                            ),
                        ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        if (entries.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            child: _AddFab(onTap: () => context.go('/machines/add')),
          ),
      ],
    );
    if (!wide || picked == null) return list;
    return Row(
      children: [
        SizedBox(width: 360, child: list),
        VerticalDivider(width: 1, color: c.hairline),
        Expanded(
          child: SafeArea(
            bottom: false,
            // The detail pane fades through when another machine is picked.
            child: HxFadeThrough(
              id: picked.info.id,
              child: _MachineDetail(entry: picked),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddFab extends StatelessWidget {
  const _AddFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final r = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: 'Add machine',
      excludeSemantics: true,
      onTap: onTap,
      // A blurred shadow (black 25 %, y +8, blur 8), no border, and a 1 px
      // white 22 % highlight along the top, inset 16 dp (tokens section 8).
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.solid,
          borderRadius: r,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: r,
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56, minWidth: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: c.solidForeground),
                        const SizedBox(width: 8),
                        Text(
                          'Add machine',
                          style: HxType.bodyLg.copyWith(color: c.solidForeground),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 16,
              right: 16,
              height: 1,
              child: IgnorePointer(
                child: ColoredBox(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        const Center(child: HxMark(size: 72)),
        const SizedBox(height: 16),
        Text(
          'No machines yet',
          textAlign: TextAlign.center,
          style: HxType.titleSm,
        ),
        const SizedBox(height: 8),
        Text(
          'Add a computer that runs HyperOx. Pick how this phone reaches it.',
          textAlign: TextAlign.center,
          style: HxType.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: 24),
        if (kAccountMode) ...[
          _ModeCard(
            title: 'Same account',
            tag: 'account',
            tagColor: c.accent,
            body: 'Computers signed in to HyperOx appear here on their own.',
            icon: Icons.cloud_outlined,
            onTap: () => context.go('/machines/add'),
          ),
          const SizedBox(height: 12),
        ],
        _ModeCard(
          title: 'SSH',
          tag: 'ssh',
          tagColor: c.done,
          body: 'Any host, IP or Tailscale name. No account needed.',
          icon: Icons.terminal,
          onTap: () => context.go('/machines/add'),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.tag,
    required this.tagColor,
    required this.body,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String tag;
  final Color tagColor;
  final String body;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Semantics(
      button: true,
      label: 'Add machine: $title',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: c.well,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: c.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(title, style: HxType.heading),
                            HxTag(tag, color: tagColor),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: HxType.bodySm.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: c.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatefulWidget {
  const _Section({
    required this.label,
    required this.entries,
    this.selectedId,
    this.onSelect,
  });

  final String label;
  final List<MachineEntry> entries;
  final String? selectedId;
  final void Function(MachineEntry)? onSelect;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  /// Machines shown so far: one that is not here was just added and grows in.
  final _seen = <String>{};
  var _first = true;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final label = widget.label;
    final entries = widget.entries;
    final selectedId = widget.selectedId;
    final onSelect = widget.onSelect;
    final first = _first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _first = false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Semantics(
            header: true,
            child: Text(label, style: HxType.labelXs.copyWith(color: c.muted)),
          ),
        ),
        HxCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.hairline),
                Appear(
                  key: ValueKey(entries[i].info.id),
                  animate: _seen.add(entries[i].info.id) && !first,
                  child: _MachineRow(
                    entry: entries[i],
                    selected: entries[i].info.id == selectedId,
                    onSelect: onSelect == null
                        ? null
                        : () => onSelect(entries[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The detail pane of the two-pane layout: the selected machine's facts,
/// agents, and the actions that need room (machines board 03).
class _MachineDetail extends ConsumerWidget {
  const _MachineDetail({required this.entry});

  final MachineEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hx.colors;
    final word = stateWord(entry);
    final wordColor = switch (word) {
      'online' => c.ok,
      'blocked' => c.blocked,
      _ => c.muted,
    };
    final isSsh = entry.ssh != null;
    final row = _MachineRow(entry: entry);
    final inbox = ref.watch(inboxProvider).value;
    Widget kv(String k, String v) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(k, style: HxType.mono.copyWith(color: c.muted)),
          ),
          Expanded(child: Text(v, style: HxType.mono)),
        ],
      ),
    );
    final sshMachine = entry.ssh;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.well,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                entry.info.os == 'windows'
                    ? Icons.desktop_windows_outlined
                    : Icons.dns_outlined,
                size: 26,
                color: c.muted,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(entry.info.name, style: HxType.titleLg),
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      HxTag(
                        isSsh ? 'ssh' : 'account',
                        color: isSsh ? c.done : c.accent,
                      ),
                      Text(word, style: HxType.mono.copyWith(color: wordColor)),
                    ],
                  ),
                ],
              ),
            ),
            if (sshMachine != null)
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: 'Rename ${entry.info.name}',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => row._rename(context, ref, sshMachine),
                ),
              ),
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                tooltip: 'More options for ${entry.info.name}',
                icon: const Icon(Icons.more_vert),
                onPressed: () => row._actions(context, ref),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionLabel('Connection'),
        HxCard(
          child: Column(
            children: [
              kv(
                'mode',
                isSsh
                    ? (sshMachine!.tailscale ? 'ssh · tailscale' : 'ssh · key')
                    : 'account · relay',
              ),
              kv('os', osLabel(entry.info.os).toLowerCase()),
              kv('address', entry.address.isEmpty ? '-' : entry.address),
              kv('seen', word == 'online' ? 'now' : 'not reachable'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        ValueListenableBuilder<InboxState>(
          valueListenable: inbox,
          builder: (context, state, _) {
            final snap = state.machines.where((m) => m.info.id == entry.info.id);
            final sessions = snap.isEmpty ? const <Session>[] : snap.first.sessions;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionLabel('Agents', count: sessions.length),
                SizedBox(
                  width: double.infinity,
                  child: HxCard(
                  padding: EdgeInsets.zero,
                  child: sessions.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No agents running.',
                            style: HxType.bodySm.copyWith(color: c.muted),
                          ),
                        )
                      : Column(
                          children: [
                            for (final s in sessions)
                              ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 56),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(s.agent, style: HxType.bodyLg),
                                            Text(
                                              shortFolder(s.folder),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: HxType.mono.copyWith(
                                                color: c.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      HxTag(
                                        groupWord(s.group, kind: s.blockedKind),
                                        color: groupColor(c, s.group),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: HxButton(
                label: 'Open inbox',
                kind: HxButtonKind.primary,
                semanticsLabel: 'Open inbox of ${entry.info.name}',
                onPressed: () => context.go('/inbox'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: HxButton(
                label: 'Spaces',
                semanticsLabel: 'Open spaces of ${entry.info.name}',
                onPressed: () => context.go('/spaces'),
              ),
            ),
          ],
        ),
        if (sshMachine != null) ...[
          const SizedBox(height: 12),
          HxButton(
            label: 'Remove from this phone',
            kind: HxButtonKind.danger,
            onPressed: () => row._remove(context, ref, sshMachine),
          ),
        ],
      ],
    );
  }
}

class _MachineRow extends ConsumerWidget {
  const _MachineRow({required this.entry, this.onSelect, this.selected = false});

  final MachineEntry entry;

  /// Wide layout: a tap selects the row for the detail pane.
  final VoidCallback? onSelect;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hx.colors;
    final word = stateWord(entry);
    final wordColor = switch (word) {
      'online' => c.ok,
      'blocked' => c.blocked,
      _ => c.muted,
    };
    final isSsh = entry.ssh != null;
    final os = osLabel(entry.info.os).toLowerCase();
    final meta = isSsh ? '$os · ${entry.address}' : os;
    // From 1.5x text the row stacks: name, meta by line, tag, state.
    final stacked = MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.5;
    final tag = HxTag(isSsh ? 'ssh' : 'account', color: isSsh ? c.done : c.accent);
    final state = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(color: wordColor),
        const SizedBox(width: 4),
        Text(word, style: HxType.mono.copyWith(color: wordColor)),
      ],
    );
    final name = Text(
      entry.info.name,
      maxLines: stacked ? 3 : 1,
      overflow: TextOverflow.ellipsis,
      style: HxType.heading.copyWith(fontWeight: FontWeight.w500),
    );
    final icon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        entry.info.os == 'windows'
            ? Icons.desktop_windows_outlined
            : Icons.dns_outlined,
        size: 20,
        color: c.muted,
      ),
    );
    final Widget body = stacked
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    name,
                    // The meta line wraps by line at its separators.
                    Text(
                      meta.replaceAll(' · ', '\n'),
                      style: HxType.mono.copyWith(color: c.muted),
                    ),
                    const SizedBox(height: 4),
                    tag,
                    const SizedBox(height: 2),
                    state,
                  ],
                ),
              ),
            ],
          )
        : Row(
            children: [
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    name,
                    // One line, cut with an ellipsis (the full address is in
                    // the actions sheet and the detail pane).
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HxType.mono.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [tag, const SizedBox(height: 2), state],
              ),
            ],
          );
    void tap() => onSelect != null ? onSelect!() : context.go('/inbox');
    return Column(
      children: [
        Semantics(
          button: true,
          selected: selected,
          label: rowLabel(entry),
          excludeSemantics: true,
          onTap: tap,
          onLongPress: () => _actions(context, ref),
          child: HxPressable(
            radius: 12,
            scale: false,
            onTap: tap,
            onLongPress: () => _actions(context, ref),
            child: Container(
              decoration: BoxDecoration(
                color: selected ? c.selected : null,
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.all(12),
              child: body,
            ),
          ),
        ),
        if (entry.status?.hostKeyChanged ?? false)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: _ReviewStrip(
              name: entry.info.name,
              onReview: () => reviewHostKey(context, ref, entry.ssh!),
            ),
          ),
      ],
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final c = context.hx.colors;
    final m = entry.ssh;
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.popover,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(entry.info.name, style: HxType.heading),
                        ),
                        if (entry.address.isNotEmpty)
                          Text(
                            entry.address,
                            style: HxType.mono.copyWith(color: c.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _SheetItem(
              icon: Icons.terminal,
              label: 'Open sessions',
              onTap: () => Navigator.pop(ctx, 'open'),
            ),
            if (m != null) ...[
              _SheetItem(
                icon: Icons.edit_outlined,
                label: 'Rename',
                onTap: () => Navigator.pop(ctx, 'rename'),
              ),
              _SheetItem(
                icon: Icons.copy_outlined,
                label: 'Copy address',
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
              _SheetItem(
                icon: Icons.key_outlined,
                label: 'Show host key',
                onTap: () => Navigator.pop(ctx, 'key'),
              ),
              _SheetItem(
                icon: Icons.delete_outline,
                label: 'Remove from this phone',
                color: c.blocked,
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (pick == null || !context.mounted) return;
    switch (pick) {
      case 'open':
        context.go('/inbox');
      case 'rename':
        await _rename(context, ref, m!);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m!.address));
      case 'key':
        await _showKey(context, ref, m!);
      case 'remove':
        await _remove(context, ref, m!);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, SshMachine m) async {
    final repo = ref.read(sshMachinesProvider.notifier);
    final ctl = TextEditingController(text: m.name);
    String? error;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Rename ${m.name}'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Name', errorText: error),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final err = validateName(ctl.text);
                if (err != null) {
                  setState(() => error = err);
                } else {
                  Navigator.pop(ctx, ctl.text);
                }
              },
              child: const Text('Rename'),
            ),
          ],
        ),
      ),
    );
    // The controller is not disposed here: the dialog is still animating out.
    if (name != null) await repo.rename(m.id, name);
  }

  Future<void> _showKey(BuildContext context, WidgetRef ref, SshMachine m) async {
    final fp = await ref.read(sshGatewayProvider).knownFingerprint(m);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Host key'),
        content: fp == null
            ? const Text('No host key is trusted yet. Connect once to see it.')
            : FingerprintBox(fingerprint: fp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, SshMachine m) async {
    // Removing the machine disposes this row and its ref: take both first.
    final repo = ref.read(sshMachinesProvider.notifier);
    final status = ref.read(machineStatusProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.name}?'),
        content: const Text(
          'It is removed from this phone only. The computer is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await repo.remove(m.id);
      status.forget(m.id);
    }
  }
}

class _SheetItem extends StatelessWidget {
  const _SheetItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final fg = color ?? c.foreground;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(label, style: HxType.bodyLg.copyWith(color: fg)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewStrip extends StatelessWidget {
  const _ReviewStrip({required this.name, required this.onReview});

  final String name;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: c.blocked.withAlpha(18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.blocked),
      ),
      child: Row(
        children: [
          Icon(Icons.gpp_maybe_outlined, size: 20, color: c.blocked),
          const SizedBox(width: 8),
          Expanded(child: Text('Host key changed', style: HxType.bodySm)),
          Semantics(
            button: true,
            label: 'Review host key change for $name',
            excludeSemantics: true,
            onTap: onReview,
            child: InkWell(
              onTap: onReview,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 72),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('Review', style: HxType.bodyLg),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a connection that waits on the changed key, shows the review sheet
/// ("Don't connect" is primary), and replaces the stored key only after a
/// second, explicit confirmation.
Future<void> reviewHostKey(
  BuildContext context,
  WidgetRef ref,
  SshMachine m,
) async {
  final session = ref.read(sshGatewayProvider).open(m);
  final status = ref.read(machineStatusProvider.notifier);
  final changed = Completer<HostKeyChanged?>();
  final sub = session.state.listen((s) {
    if (changed.isCompleted) return;
    if (s is HostKeyChanged) changed.complete(s);
    if (s is Ready || s is Failed) changed.complete(null);
  });
  unawaited(session.start());
  try {
    final hk = await changed.future.timeout(
      kProbeTimeout,
      onTimeout: () => null,
    );
    if (hk == null) {
      if (context.mounted) {
        showHxSnack(context, 'Could not reach ${m.name} to compare the key.');
      }
      return;
    }
    if (!context.mounted) return;
    final trust = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.hx.colors.popover,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => HostKeyChangedSheet(
        machineName: m.name,
        address: m.address,
        known: hk.known,
        offered: hk.offered,
        onDontConnect: () => Navigator.pop(ctx, false),
        onTrustNew: () => Navigator.pop(ctx, true),
      ),
    );
    if (trust != true || !context.mounted) {
      session.rejectHostKey();
      return;
    }
    final really = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trust the new key?'),
        content: FingerprintBox(fingerprint: hk.offered, caption: 'New host key'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trust new key'),
          ),
        ],
      ),
    );
    if (really == true) {
      session.replaceHostKey();
      await session.start().timeout(
        kProbeTimeout,
        onTimeout: () => const Failed('timed out'),
      );
    } else {
      session.rejectHostKey();
    }
  } finally {
    await sub.cancel();
    await session.close();
    unawaited(status.refresh());
  }
}
