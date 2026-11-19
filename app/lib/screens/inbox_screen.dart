import 'dart:async';

import 'package:flutter/semantics.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../widgets/hx_icon_compat.dart';
import '../config.dart';
import '../conn/machine_connection.dart';
import '../state/inbox.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../widgets/app_shell.dart';
import '../widgets/hx.dart';
import '../widgets/hx_bits.dart';
import '../widgets/hx_icons.dart';
import 'agent_screen.dart';

/// Every agent on every machine, grouped by who needs whom (design: Inbox).
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key, this.onOpen, this.onNavigate});

  /// Opens an agent (default: the router's `/agent/:machine/:terminal`).
  final void Function(InboxItem item)? onOpen;
  final void Function(NavDest dest)? onNavigate;

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final _search = TextEditingController();
  String _query = '';
  InboxItem? _selected;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(InboxItem item) {
    ref.read(inboxProvider).markRead(item);
    if (widget.onOpen != null) {
      widget.onOpen!(item);
    } else if (MediaQuery.sizeOf(context).width >= kRailBreakpoint) {
      setState(() => _selected = item);
    } else {
      context.push('/agent/${item.machine.id}/${item.session.terminal}');
    }
  }

  Future<void> _answer(InboxItem item, bool approve) async {
    final conn = ref.read(inboxProvider).connectionFor(item.machine.id);
    if (conn == null) return;
    final r = approve
        ? await conn.approve(item.session.terminal)
        : await conn.deny(item.session.terminal);
    if (!mounted) return;
    if (r is! Done) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_replyText(r))));
    }
    unawaited(ref.read(inboxProvider).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(inboxProvider);
    final wide = MediaQuery.sizeOf(context).width >= kRailBreakpoint;
    return ScreenBody(
      body: ValueListenableBuilder<InboxState>(
        valueListenable: controller.value,
        builder: (context, state, _) {
          final list = _list(context, controller, state);
          if (!wide) return list;
          return Row(
            children: [
              SizedBox(width: 360, child: list),
              VerticalDivider(width: 1, color: context.hx.colors.hairline),
              Expanded(child: _detail(context, _selected ?? _firstOf(state))),
            ],
          );
        },
      ),
    );
  }

  /// The agent to show when none was picked: the first one that needs the
  /// person, else the first one.
  InboxItem? _firstOf(InboxState state) {
    final needs = state.group(AgentGroup.needsYou, '');
    if (needs.isNotEmpty) return needs.first;
    final all = state.items('');
    return all.isEmpty ? null : all.first;
  }

  Widget _detail(BuildContext context, InboxItem? s) {
    final c = context.hx.colors;
    if (s == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No agents yet',
            style: HxType.body.copyWith(color: c.muted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // The agent opens beside the list (inbox board 03).
    return AgentScreen(
      key: ValueKey('${s.machine.id}/${s.session.terminal}'),
      machineId: s.machine.id,
      terminal: s.session.terminal,
      embedded: true,
    );
  }

  Widget _list(BuildContext context, InboxController controller, InboxState state) {
    final c = context.hx.colors;
    final needs = state.needsYou;
    final machines = state.machines.length;
    final subtitle = state.machines.isEmpty
        ? null
        : state.loading
            ? 'syncing…'
            : state.allOffline
                ? 'all machines offline'
                : '$needs need you · $machines machine${machines == 1 ? '' : 's'}';
    final header = ScreenHeader(
      title: 'Inbox',
      subtitle: subtitle,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More: mark all read, sort',
          icon: const Icon(Icons.more_vert),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onSelected: (_) => controller.markAllRead(),
          itemBuilder: (_) => const [PopupMenuItem(value: 'read', child: Text('Mark all read'))],
        ),
      ],
    );

    if (state.machines.isEmpty) {
      return Column(children: [header, Expanded(child: _Empty(onAdd: () => _go(context)))]);
    }

    final children = <Widget>[
      _SearchField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        onClear: () => setState(() {
          _search.clear();
          _query = '';
        }),
      ),
      if (state.allOffline)
        _Banner(
          title: 'All machines are offline',
          message: 'Showing the last state from the last time they answered. Pull to retry, or check Machines.',
          action: 'Open Machines',
          kind: HxBannerKind.info,
          onAction: () => (widget.onNavigate ?? (d) => context.go(d.path))(NavDest.machines),
        ),
      for (final m in state.machines)
        if (m.state is Failed && !state.allOffline && !m.loaded)
          _Banner(
            title: "${m.info.name} didn't answer",
            message: '${(m.state as Failed).reason}. Its agents are hidden until it answers.',
            action: 'Retry ${m.info.name}',
            kind: HxBannerKind.error,
            onAction: () => controller.retry(controller.connectionFor(m.info.id)!),
          ),
      if (kAccountMode)
        for (final m in state.machines)
          if (m.state is NeedsApproval)
            _ApprovalBanner(name: m.info.name, code: (m.state as NeedsApproval).code),
    ];

    if (state.loading) {
      children.addAll([for (var i = 0; i < 3; i++) const _SkeletonRow()]);
    } else {
      var any = false;
      for (final g in AgentGroup.values) {
        final items = state.group(g, _query);
        if (items.isEmpty) continue;
        any = true;
        children.add(SectionLabel(
          groupWord(g),
          count: items.length,
          dot: groupColor(c, g),
        ));
        for (final i in items) {
          children.add(AgentRow(
            item: i,
            onOpen: () => _open(i),
            onAnswer: (approve) => _answer(i, approve),
            onPin: () => controller.togglePin(i.key),
            onMarkRead: () => controller.markRead(i),
          ));
        }
      }
      if (!any) {
        children.add(Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _query.isEmpty ? 'No agents running on these machines.' : 'No agent matches "$_query".',
            textAlign: TextAlign.center,
            style: HxType.body.copyWith(color: c.muted),
          ),
        ));
      }
    }

    return Column(
      children: [
        header,
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(padding: const EdgeInsets.only(bottom: 16), children: children),
          ),
        ),
      ],
    );
  }

  void _go(BuildContext context) =>
      (widget.onNavigate ?? (d) => context.go(d.path))(NavDest.machines);
}

String _replyText(Reply r) => switch (r) {
      ReplyFailed(:final message) => message,
      Locked() => 'The computer is locked.',
      RateLimited(:final secs) => 'Too many requests. Try again in $secs s.',
      NotPaired() => 'This phone is not approved on that computer.',
      NeedsConfirm() => 'Needs confirmation.',
      Done() => 'Done.',
    };

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged, required this.onClear});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.outline),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search, size: 20, color: c.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                textField: true,
                label: 'Search agents, folders, machines',
                excludeSemantics: true,
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: HxType.body,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search agents, folders, machines',
                    hintStyle: HxType.body.copyWith(color: c.muted),
                  ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              HxIconButton(icon: Icons.close, label: 'Clear search', onPressed: onClear),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.title,
    required this.message,
    required this.action,
    required this.kind,
    required this.onAction,
  });

  final String title;
  final String message;
  final String action;
  final HxBannerKind kind;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HxBanner(title: title, message: message, kind: kind),
            HxButton(label: action, onPressed: onAction, minHeight: 48),
          ],
        ),
      );
}

/// Account only (hidden while [kAccountMode] is off).
class _ApprovalBanner extends StatelessWidget {
  const _ApprovalBanner({required this.name, required this.code});
  final String name;
  final String code;

  @override
  Widget build(BuildContext context) {
    final spaced = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: HxBanner(
        title: 'Approve on $name',
        message: 'code $spaced, waiting',
        kind: HxBannerKind.info,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: c.muted),
            const SizedBox(height: 16),
            Text('No agents yet', style: HxType.titleSm),
            const SizedBox(height: 8),
            Text(
              'Agents from every machine land here, grouped by who needs you. Add a machine to start.',
              textAlign: TextAlign.center,
              style: HxType.body.copyWith(color: c.muted),
            ),
            const SizedBox(height: 20),
            HxButton(
              label: 'Add machine',
              icon: Icons.add,
              kind: HxButtonKind.primary,
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Semantics(
        label: 'Loading agents',
        child: Container(
          height: 84,
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

/// One agent of the inbox. [compact] drops the inline Approve / Deny and
/// tightens the row to 72 dp (the agent screen's sidebar reuses it).
class AgentRow extends StatelessWidget {
  const AgentRow({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onAnswer,
    required this.onPin,
    this.onMarkRead,
    this.compact = false,
    this.selected = false,
  });

  final bool compact;
  final bool selected;
  final InboxItem item;
  final VoidCallback onOpen;
  final void Function(bool approve) onAnswer;
  final VoidCallback onPin;

  /// Mark this agent read (null: no swipe actions, as in the sidebar).
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final s = item.session;
    final g = s.group;
    final word = item.offline ? 'offline' : groupWord(g, kind: s.blockedKind);
    final tone = item.offline ? c.muted : groupColor(c, g);
    final where = shortFolder(s.folder);
    final label = '${s.agent} in $where on ${item.machine.name}, $word'
        '${s.message.isEmpty ? '' : ': ${s.message}'}'
        '${item.unread ? ', unread' : ''}${item.pinned ? ', pinned' : ''}';
    final canAnswer = !compact &&
        !item.offline &&
        g == AgentGroup.needsYou &&
        s.status == 'blocked' &&
        s.blockedKind == 'permission';
    final detail = s.message.isEmpty ? s.name : s.message;
    final markRead = onMarkRead;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: _SwipeActions(
        enabled: markRead != null && !compact,
        pinned: item.pinned,
        onPin: onPin,
        onMarkRead: markRead ?? () {},
        child: Container(
        decoration: BoxDecoration(
          color: selected ? c.selected : c.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? c.accent : c.hairline),
        ),
        child: Column(
          children: [
            Semantics(
              button: true,
              selected: selected,
              label: label,
              excludeSemantics: true,
              onTap: onOpen,
              onLongPress: markRead == null ? onPin : () => _menu(context),
              // Pin and Mark read are also screen-reader actions.
              customSemanticsActions: {
                CustomSemanticsAction(label: item.pinned ? 'Unpin' : 'Pin'): onPin,
                if (markRead != null) const CustomSemanticsAction(label: 'Mark read'): markRead,
              },
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onOpen,
                onLongPress: markRead == null ? onPin : () => _menu(context),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: compact ? 72 : 84),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AgentTile(s.agent, color: tone),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  Text(s.agent, style: HxType.heading),
                                  Text(where, style: HxType.mono.copyWith(color: c.muted)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(detail, style: HxType.bodySm),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(item.machine.name,
                                      style: HxType.mono.copyWith(color: c.muted)),
                                  ModeTag(item.machine.mode),
                                  HxTag(word, color: tone),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (item.pinned)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: HxIcon('pin', size: 14, color: c.muted),
                          ),
                        if (item.unread)
                          Padding(
                            padding: const EdgeInsets.only(left: 10, top: 4),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: c.done, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (canAnswer)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final stacked = MediaQuery.textScalerOf(context).scale(15) >= 22;
                    final approve = HxButton(
                      label: 'Approve',
                      icon: Icons.check,
                      kind: HxButtonKind.primary,
                      semanticsLabel: 'Approve ${s.agent}: ${s.message}',
                      minHeight: 48,
                      onPressed: () => onAnswer(true),
                    );
                    final deny = HxButton(
                      label: 'Deny',
                      semanticsLabel: 'Deny ${s.agent}: ${s.message}',
                      minHeight: 48,
                      onPressed: () => onAnswer(false),
                    );
                    return stacked
                        ? Column(children: [approve, const SizedBox(height: 8), deny])
                        : Row(children: [
                            Expanded(child: deny),
                            const SizedBox(width: 8),
                            Expanded(child: approve),
                          ]);
                  },
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  /// Long-press: the same two actions as the swipe, as a menu.
  Future<void> _menu(BuildContext context) async {
    final c = context.hx.colors;
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
            const SizedBox(height: 8),
            _MenuItem(
              icon: 'pin',
              label: item.pinned ? 'Unpin' : 'Pin',
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            _MenuItem(
              icon: 'check',
              label: 'Mark read',
              onTap: () => Navigator.pop(ctx, 'read'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (pick == 'pin') onPin();
    if (pick == 'read') onMarkRead?.call();
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label, required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
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
                HxIcon(icon, size: 20, color: c.foreground),
                const SizedBox(width: 16),
                Text(label, style: HxType.bodyLg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that swipes left to show two 76 x 88 actions (Pin / Unpin and Mark
/// read) on the `raised` fill. Released past half way it snaps open; a tap
/// elsewhere closes it.
class _SwipeActions extends StatefulWidget {
  const _SwipeActions({
    required this.enabled,
    required this.pinned,
    required this.onPin,
    required this.onMarkRead,
    required this.child,
  });

  final bool enabled;
  final bool pinned;
  final VoidCallback onPin;
  final VoidCallback onMarkRead;
  final Widget child;

  @override
  State<_SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<_SwipeActions> {
  static const _width = 152.0;
  var _x = 0.0;

  void _close() {
    if (_x != 0) setState(() => _x = 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final c = context.hx.colors;
    Widget action(String icon, String label, VoidCallback run) => Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: () {
          run();
          _close();
        },
        child: InkWell(
          onTap: () {
            run();
            _close();
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HxIcon(icon, size: 22, color: c.foreground),
              const SizedBox(height: 4),
              Text(label, style: HxType.caption.copyWith(color: c.foreground)),
            ],
          ),
        ),
      ),
    );
    return TapRegion(
      onTapOutside: (_) => _close(),
      child: GestureDetector(
        onHorizontalDragUpdate: (d) =>
            setState(() => _x = (_x + d.delta.dx).clamp(-_width, 0.0)),
        onHorizontalDragEnd: (_) =>
            setState(() => _x = _x < -_width / 2 ? -_width : 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              if (_x < 0)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: _width,
                      color: c.raised,
                      child: Row(
                        children: [
                          action('pin', widget.pinned ? 'Unpin' : 'Pin', widget.onPin),
                          action('check', 'Mark read', widget.onMarkRead),
                        ],
                      ),
                    ),
                  ),
                ),
              Transform.translate(offset: Offset(_x, 0), child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}
