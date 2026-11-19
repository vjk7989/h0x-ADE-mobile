import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;
import 'package:share_plus/share_plus.dart';
import 'package:xterm/xterm.dart';

import '../widgets/hx_icon_compat.dart';
import '../conn/machine_connection.dart';
import '../state/agent_session.dart';
import '../state/connections.dart';
import '../state/key_input.dart';
import '../theme/motion.dart';
import '../theme/terminal_theme.dart';
import '../theme/theme_controller.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../state/inbox.dart';
import '../widgets/app_shell.dart';
import '../widgets/hx.dart';
import '../widgets/hx_bits.dart';
import '../widgets/hx_icons.dart';
import 'inbox_screen.dart';
import '../widgets/key_bar.dart';

const kTermMinSize = 9.0;
const kTermMaxSize = 20.0;
const kTermDefaultSize = 12.0;

String zoomKey(String machineId) => 'agent.zoom.$machineId';

/// A live terminal of one machine: header, output, prompt card, compose
/// row and key bar. [connection] is for tests; the app finds it by
/// [machineId] among the started connections.
class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({
    super.key,
    required this.machineId,
    required this.terminal,
    this.connection,
    this.embedded = false,
  });

  final String machineId;
  final String terminal;
  final MachineConnection? connection;

  /// Shown beside the inbox list (no back button, no sidebar of its own).
  final bool embedded;

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  AgentController? _agent;
  final _modifiers = Modifiers();
  final _compose = TextEditingController();
  final _composeFocus = FocusNode();
  double _fontSize = kTermDefaultSize;
  double _zoomBase = kTermDefaultSize;
  String? _locked;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(sharedPrefsProvider).getDouble(
      zoomKey(widget.machineId),
    );
    if (saved != null) _fontSize = saved.clamp(kTermMinSize, kTermMaxSize);
    _compose.addListener(() => setState(() {}));
    final conn = widget.connection ?? _find();
    if (conn != null) {
      final a = AgentController(conn, widget.terminal);
      a.terminal.onOutput = _typed;
      a.addListener(() {
        if (mounted) setState(() {});
      });
      _agent = a;
      unawaited(a.start());
    }
  }

  MachineConnection? _find() {
    for (final c in ref.read(connectionsProvider)) {
      if (c.machine.id == widget.machineId) return c;
    }
    return null;
  }

  @override
  void dispose() {
    _agent?.dispose();
    _modifiers.dispose();
    _compose.dispose();
    _composeFocus.dispose();
    super.dispose();
  }

  bool get _ready => _agent?.phase == AgentPhase.ready;

  /// Typing straight into the terminal sends keys as typed.
  void _typed(String data) {
    final a = _agent;
    if (a == null || !_ready) return;
    final keys = keysFromOutput(data);
    if (keys.isEmpty) return;
    keys[0] = _modifiers.apply(keys[0]);
    unawaited(_handle(a.sendKeys(keys)));
  }

  Future<void> _handle(Future<Reply> call) async {
    final a = _agent!;
    var r = await call;
    while (true) {
      final pending = r;
      if (pending is! NeedsConfirm) break;
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm'),
          content: Text('Do you want to ${pending.what}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      r = await a.confirm(pending.token);
    }
    if (!mounted) return;
    switch (r) {
      case Done():
        if (_locked != null) setState(() => _locked = null);
        unawaited(a.refreshNow());
      case Locked():
        setState(
          () => _locked =
              'HyperOx on ${a.conn.machine.name} is locked. Unlock it '
              'before sending input or approving.',
        );
      case RateLimited(:final secs):
        _snack('Too many requests · try in $secs s');
      case ReplyFailed(:final message):
        _snack(message);
      case NotPaired():
        _snack('This phone is not paired with this machine.');
      case NeedsConfirm():
        break;
    }
  }

  /// Messages float above the compose row and the key bar, never over them
  /// (tokens section 13): inverse fill, 16 dp margins, radius 12.
  final _bottomKey = GlobalKey();

  void _snack(String text) {
    final lift = (_bottomKey.currentContext?.size?.height ?? 100) + 8;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    showHxSnack(context, text, bottom: lift);
  }

  Future<void> _send() async {
    final a = _agent;
    final text = _compose.text;
    if (a == null || !_ready || text.trim().isEmpty || messageTooLong(text)) {
      return;
    }
    _compose.clear();
    await _handle(a.send(text));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final sel = _compose.selection;
    final at = sel.isValid ? sel.start : _compose.text.length;
    final end = sel.isValid ? sel.end : at;
    _compose.value = TextEditingValue(
      text: _compose.text.replaceRange(at, end, text),
      selection: TextSelection.collapsed(offset: at + text.length),
    );
    _composeFocus.requestFocus();
  }

  Future<void> _interrupt() async {
    final a = _agent;
    if (a == null) return;
    final name = a.session?.agent ?? 'the agent';
    final folder = a.session?.folder ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.stop_circle_outlined, color: context.hx.colors.blocked),
        title: Text('Interrupt $name?'),
        content: Text(
          'Sends Ctrl+C to $name'
          '${folder.isEmpty ? '' : ' in $folder'} on '
          '${a.conn.machine.name}. The agent stops what it is doing; the '
          'terminal stays open.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.hx.colors.blocked,
            ),
            child: const Text('Interrupt'),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.heavyImpact();
      await _handle(a.interrupt());
    }
  }

  String _selectedText() {
    final a = _agent!;
    final range = a.selection.selection;
    return range == null ? '' : a.terminal.buffer.getText(range);
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _snack('$what copied');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final a = _agent;
    if (a == null) return _NotConnected(machineId: widget.machineId);
    final phase = a.phase;
    final session = a.session;
    final name = session?.agent.isNotEmpty ?? false ? session!.agent : 'terminal';
    final reason = switch (phase) {
      AgentPhase.attaching => 'attaching to $name',
      AgentPhase.reconnecting => 'reconnecting to ${a.conn.machine.name}',
      AgentPhase.finished => 'the terminal has exited',
      AgentPhase.ready => null,
    };
    final blocked = session != null &&
        session.live &&
        session.status == 'blocked';
    final wide = MediaQuery.sizeOf(context).width >= kRailBreakpoint;
    final main = Column(
          children: [
            _Header(
              name: name,
              session: session,
              machine: a.conn.machine.name,
              onBack: widget.embedded
                  ? null
                  : () => context.canPop() ? context.pop() : context.go('/inbox'),
              onInterrupt: phase == AgentPhase.finished ? null : _interrupt,
              onCopyAll: () => _copy(a.terminal.buffer.getText(), 'Output'),
              onShareAll: () => SharePlus.instance.share(
                ShareParams(text: a.terminal.buffer.getText()),
              ),
            ),
            // History replays under a thin bar, which fades out when done.
            _ReplayBar(progress: a.replayProgress, active: a.replaying),
            if (phase == AgentPhase.reconnecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: HxBanner(
                  kind: HxBannerKind.info,
                  title: 'Reconnecting to ${a.conn.machine.name}',
                  message: a.error ?? 'Output so far stays here.',
                  trailing: a.retryIn == null
                      ? null
                      : _RetryRing(total: a.retryIn!, epoch: a.retryEpoch),
                ),
              ),
            if (_locked != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: HxBanner(
                  kind: HxBannerKind.info,
                  title: 'Locked on the computer',
                  message: _locked!,
                ),
              ),
            Expanded(child: _terminalArea(context, a)),
            if (blocked && phase == AgentPhase.ready)
              _PromptCard(
                session: session,
                onDeny: () {
                  HapticFeedback.lightImpact();
                  _handle(a.deny());
                },
                onApprove: () {
                  HapticFeedback.mediumImpact();
                  _handle(a.approve());
                },
              ),
            if (phase == AgentPhase.finished)
              _ResultCard(
                name: name,
                onClose: () async {
                  await _handle(a.kill());
                  if (mounted) context.go('/inbox');
                },
                onBack: () => context.go('/inbox'),
              )
            else
              Column(
                key: _bottomKey,
                mainAxisSize: MainAxisSize.min,
                children: [
              _ComposeRow(
                name: name,
                controller: _compose,
                focus: _composeFocus,
                enabled: phase == AgentPhase.ready,
                disabledReason: reason,
                onPaste: _paste,
                onSend: _send,
              ),
              KeyBar(
                modifiers: _modifiers,
                enabled: phase == AgentPhase.ready,
                disabledReason: reason,
                onKeys: (keys) => _handle(a.sendKeys(keys)),
              ),
                ],
              ),
          ],
        );
    final body = !wide || widget.embedded
        ? main
        : Row(
            children: [
              SizedBox(
                width: 300,
                child: _Sidebar(machineId: widget.machineId, terminal: widget.terminal),
              ),
              VerticalDivider(width: 1, color: c.hairline),
              Expanded(child: main),
            ],
          );
    return Scaffold(
      backgroundColor: c.screen,
      body: SafeArea(child: body),
    );
  }

  Widget _terminalArea(BuildContext context, AgentController a) {
    final hx = context.hx;
    final theme = terminalThemeFor(hx.terminal);
    return LayoutBuilder(
      builder: (context, box) {
        // The view fills the screen and the local terminal takes the
        // columns that fit; lines wider than the phone wrap. The computer's
        // terminal is never resized from here (no resize is forwarded).
        final view = TerminalView(
          a.terminal,
          controller: a.selection,
          theme: theme,
          textStyle: TerminalStyle(
            fontSize: _fontSize,
            height: 16 / 12,
            fontFamily: 'JetBrainsMono',
          ),
          textScaler: TextScaler.noScaling,
          padding: const EdgeInsets.all(10),
          autofocus: false,
          readOnly: !_ready,
        );
        // expand: inside a Column the Stack would otherwise shrink to the
        // width of its only unpositioned child (zero).
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: hx.terminal.background,
                child: GestureDetector(
                  onScaleStart: (_) => _zoomBase = _fontSize,
                  onScaleUpdate: (d) {
                    if (d.pointerCount < 2) return;
                    setState(
                      () => _fontSize = (_zoomBase * d.scale).clamp(
                        kTermMinSize,
                        kTermMaxSize,
                      ),
                    );
                  },
                  onScaleEnd: (_) => ref
                      .read(sharedPrefsProvider)
                      .setDouble(zoomKey(widget.machineId), _fontSize),
                  child: Opacity(
                    opacity: a.phase == AgentPhase.reconnecting ? 0.55 : 1,
                    child: view,
                  ),
                ),
              ),
            ),
            if (a.phase == AgentPhase.attaching)
              Positioned.fill(
                child: _Attaching(
                  name: a.session?.agent.isNotEmpty ?? false
                      ? a.session!.agent
                      : 'terminal',
                ),
              ),
            ListenableBuilder(
              listenable: a.selection,
              builder: (context, _) {
                if (a.selection.selection == null) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _SelectionToolbar(
                      onCopy: () => _copy(_selectedText(), 'Selection'),
                      onCopyAll: () =>
                          _copy(a.terminal.buffer.getText(), 'Output'),
                      onShare: () => SharePlus.instance.share(
                        ShareParams(text: _selectedText()),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _NotConnected extends StatelessWidget {
  const _NotConnected({required this.machineId});

  final String machineId;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Scaffold(
      backgroundColor: c.screen,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This machine is not connected',
                style: HxType.titleSm,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Open Machines, check that it is online, and try again.',
                style: HxType.body.copyWith(color: c.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              HxButton(
                label: 'Back to Machines',
                onPressed: () => context.go('/machines'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.session,
    required this.machine,
    required this.onBack,
    required this.onInterrupt,
    required this.onCopyAll,
    required this.onShareAll,
  });

  final String name;
  final Session? session;
  final String machine;

  /// Null: no back button (embedded beside the inbox).
  final VoidCallback? onBack;
  final VoidCallback? onInterrupt;
  final VoidCallback onCopyAll;
  final VoidCallback onShareAll;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final s = session;
    final (word, tone) = switch (s?.group) {
      AgentGroup.needsYou => (
        s!.blockedKind == 'permission' || s.blockedKind == null
            ? 'needs you'
            : 'question',
        c.working,
      ),
      AgentGroup.working => ('working', c.done),
      AgentGroup.done => ('done', c.ok),
      AgentGroup.idle => (s!.live ? 'idle' : 'exited', c.muted),
      null => ('', c.muted),
    };
    final folder = s?.folder ?? '';
    final stacked = MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.5;
    final back = onBack == null
        ? const SizedBox(width: 12)
        : Padding(
            padding: const EdgeInsets.only(left: 4),
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              ),
            ),
          );
    final interrupt = SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        tooltip: 'Interrupt $name',
        icon: Icon(Icons.stop_circle_outlined, color: c.blocked),
        onPressed: onInterrupt,
      ),
    );
    final more = PopupMenuButton<String>(
      tooltip: 'More options',
      onSelected: (v) => v == 'copy' ? onCopyAll() : onShareAll(),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'copy', child: Text('Copy all')),
        PopupMenuItem(value: 'share', child: Text('Share output')),
      ],
    );
    final where = folder.isEmpty ? machine : '$folder · $machine';

    if (stacked) {
      // From 1.5x text: back, name, interrupt, more; then the folder; then
      // the state tag (agent board 11).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              back,
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(name, style: HxType.title),
                ),
              ),
              interrupt,
              more,
              const SizedBox(width: 4),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Text(where, style: HxType.mono.copyWith(color: c.muted)),
          ),
          if (word.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: HxTag(word, color: tone),
            ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          back,
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tone.withValues(alpha: 0.35)),
            ),
            child: Text(
              initials(name),
              style: HxType.weight(HxType.mono, 600).copyWith(
                fontSize: 12.5,
                color: c.foreground,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HxType.weight(HxType.heading, 600).copyWith(fontSize: 17),
                        ),
                      ),
                    ),
                    if (word.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      HxTag(word, color: tone),
                    ],
                  ],
                ),
                Text(
                  where,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HxType.mono.copyWith(color: c.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          interrupt,
          more,
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// The inbox, compact, beside the terminal on a tablet (agent board 03). It
/// reuses the inbox's own row.
class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.machineId, required this.terminal});

  final String machineId;
  final String terminal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hx.colors;
    final controller = ref.watch(inboxProvider);
    return ValueListenableBuilder<InboxState>(
      valueListenable: controller.value,
      builder: (context, state, _) {
        final items = state.items('');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Semantics(
                header: true,
                child: Text('Inbox', style: HxType.title),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No agents yet',
                        style: HxType.body.copyWith(color: c.muted),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final i in items)
                          AgentRow(
                            item: i,
                            compact: true,
                            selected: i.machine.id == machineId &&
                                i.session.terminal == terminal,
                            onOpen: () {
                              controller.markRead(i);
                              context.go('/agent/${i.machine.id}/${i.session.terminal}');
                            },
                            onAnswer: (_) {},
                            onPin: () => controller.togglePin(i.key),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Attaching extends StatelessWidget {
  const _Attaching({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return ColoredBox(
      color: c.screen,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final w in [0.9, 0.6, 0.75, 0.4])
            Container(
              height: 10,
              width: 260 * w,
              margin: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: c.hairline,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          const SizedBox(height: 24),
          Semantics(
            liveRegion: true,
            label: 'Attaching to $name, replaying the last 5000 lines',
            excludeSemantics: true,
            child: Column(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: c.accent,
                  ),
                ),
                const SizedBox(height: 12),
                Text('Attaching to $name', style: HxType.body),
                Text(
                  'replaying the last 5000 lines',
                  style: HxType.mono.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.session,
    required this.onDeny,
    required this.onApprove,
  });

  final Session session;
  final VoidCallback onDeny;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final permission = session.blockedKind == 'permission';
    final title = session.message.isEmpty
        ? (permission ? 'Waiting for your approval' : 'Waiting for your reply')
        : session.message;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.working.withAlpha(24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.working.withAlpha(115)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            container: true,
            child: Row(
              children: [
                HxIcon(permission ? 'bell' : 'info', size: 20, color: c.working),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: HxType.bodyLg),
                      Text(
                        permission
                            ? 'permission · ${session.agent}'
                            : 'question · reply in the box below',
                        style: HxType.mono.copyWith(
                          color: c.foreground.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (permission) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: HxButton(
                    label: 'Deny',
                    minHeight: 48,
                    onPressed: onDeny,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ApproveButton(onPressed: onApprove),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ApproveButton extends StatelessWidget {
  const _ApproveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Semantics(
      button: true,
      label: 'Approve',
      excludeSemantics: true,
      onTap: onPressed,
      child: Material(
        color: c.accent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check, size: 20, color: c.accentForeground),
                const SizedBox(width: 8),
                Text(
                  'Approve',
                  style: HxType.bodyLg.copyWith(color: c.accentForeground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.name,
    required this.onClose,
    required this.onBack,
  });

  final String name;
  final VoidCallback onClose;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 20, color: c.ok),
                const SizedBox(width: 8),
                Text('$name finished', style: HxType.bodyLg),
                const SizedBox(width: 8),
                Text(
                  '[process exited]',
                  style: HxType.mono.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: HxButton(label: 'Close terminal', onPressed: onClose),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HxButton(
                  label: 'Back to inbox',
                  kind: HxButtonKind.primary,
                  onPressed: onBack,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComposeRow extends StatelessWidget {
  const _ComposeRow({
    required this.name,
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.disabledReason,
    required this.onPaste,
    required this.onSend,
  });

  final String name;
  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final String? disabledReason;
  final VoidCallback onPaste;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final text = controller.text;
    final tooLong = messageTooLong(text);
    final empty = text.trim().isEmpty;
    final canSend = enabled && !empty && !tooLong;
    final why = !enabled
        ? disabledReason
        : tooLong
        ? 'message is over 60 KiB'
        : empty
        ? 'type a message first'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: enabled ? onPaste : null,
                ),
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: tooLong ? c.blocked : c.outline,
                      width: tooLong ? 2 : 1,
                    ),
                  ),
                  child: Semantics(
                    label: 'Message $name',
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      enabled: enabled,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      style: HxType.body,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Message $name…',
                        hintStyle: HxType.body.copyWith(color: c.muted),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Semantics(
                button: true,
                enabled: canSend,
                label: canSend ? 'Send' : 'Send, unavailable: $why',
                excludeSemantics: true,
                onTap: canSend ? onSend : null,
                child: InkResponse(
                  onTap: canSend ? onSend : null,
                  radius: 28,
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: canSend ? c.accent : c.card,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.send,
                        size: 20,
                        color: canSend ? c.accentForeground : c.dim,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (tooLong)
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 4, 0, 0),
              child: Text(
                'Message is over 60 KiB. Send it in parts.',
                style: HxType.caption.copyWith(color: c.blocked),
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.onCopy,
    required this.onCopyAll,
    required this.onShare,
  });

  final VoidCallback onCopy;
  final VoidCallback onCopyAll;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    Widget item(String label, VoidCallback onTap) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 80,
          height: 48,
          alignment: Alignment.center,
          child: Text(label, style: HxType.bodySm),
        ),
      ),
    );
    return Material(
      color: c.popover,
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item('Copy', onCopy),
          item('Copy all', onCopyAll),
          item('Share', onShare),
        ],
      ),
    );
  }
}

/// A 2 dp determinate bar under the header while the history replays; it
/// fades out when the replay is done.
class _ReplayBar extends StatelessWidget {
  const _ReplayBar({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: HxMotion.d(context, HxMotion.stateChange, fade: true),
      child: SizedBox(
        height: 2,
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 2,
          backgroundColor: Colors.transparent,
          color: c.accent,
        ),
      ),
    );
  }
}

/// A ring around the retry icon that runs down over the wait before the next
/// try. With reduced motion the ring stays full.
class _RetryRing extends StatefulWidget {
  const _RetryRing({required this.total, required this.epoch});

  final Duration total;
  final int epoch;

  @override
  State<_RetryRing> createState() => _RetryRingState();
}

class _RetryRingState extends State<_RetryRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  void _start() {
    if (HxMotion.reduced(context)) return;
    _c.duration = widget.total;
    _c.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_c.isAnimating && _c.value == 0) _start();
  }

  @override
  void didUpdateWidget(_RetryRing old) {
    super.didUpdateWidget(old);
    if (old.epoch != widget.epoch) _start();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Semantics(
      label: 'Retrying in ${widget.total.inSeconds} ${widget.total.inSeconds == 1 ? 'second' : 'seconds'}',
      excludeSemantics: true,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CustomPaint(
          painter: _RingPainter(c.working, _c),
          child: Center(child: Icon(Icons.refresh, size: 14, color: c.working)),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.anim) : super(repaint: anim);

  final Color color;
  final Animation<double> anim;

  @override
  void paint(Canvas canvas, Size size) {
    // Full at the start of the wait, empty at its end (the full ring when not
    // counting).
    final left = anim.value == 0 ? 1.0 : 1 - anim.value;
    canvas.drawArc(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      -math.pi / 2,
      2 * math.pi * left,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}
