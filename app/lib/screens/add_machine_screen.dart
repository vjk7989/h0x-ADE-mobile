import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../conn/machine_connection.dart';
import '../data/ssh_gateway.dart';
import '../data/ssh_machines_repo.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../widgets/hx.dart';
import '../widgets/machine_sheets.dart';

/// What went wrong and what to do, for a failed first connect.
({String title, String hint}) explainFailure(
  String reason, {
  required String host,
  required int port,
  required bool tailscale,
}) {
  final r = reason.toLowerCase();
  if (r.startsWith('login refused')) {
    return tailscale
        ? (
            title: 'Tailscale SSH refused the login',
            hint:
                'Check that Tailscale SSH is on for that machine and that '
                'your tailnet policy lets this phone in.',
          )
        : (
            title: 'Permission denied (publickey)',
            hint:
                'Add this phone\'s key to ~/.ssh/authorized_keys on the '
                'machine, then try again. Or use Tailscale SSH.',
          );
  }
  if (r.contains('host key refused') || r.contains('did not trust')) {
    return (
      title: 'Host key not trusted',
      hint: 'Nothing was saved. Connect again and trust the key to continue.',
    );
  }
  if (r.contains('path')) {
    return (
      title: 'h0x-core is not installed for SSH logins',
      hint:
          'Install h0x-core on the machine and make sure it is on the PATH '
          'of non-interactive logins.',
    );
  }
  if (r.contains('prints text') || r.contains('banner')) {
    return (
      title: 'The login prints text',
      hint:
          'Remove output from the shell start-up files (.bashrc, .profile) '
          'for non-interactive logins, then try again.',
    );
  }
  if (r.startsWith('cannot connect') ||
      r.contains('timed out') ||
      r.contains('socket') ||
      r.contains('unreachable')) {
    return (
      title: 'Cannot reach $host:$port',
      hint:
          'Check the address, that the machine is on, and that this phone is '
          'on the same network or on Tailscale.',
    );
  }
  return (title: 'Could not connect', hint: reason);
}

final phoneKeyProvider = FutureProvider.autoDispose<PhoneKeyInfo>(
  (ref) => ref.read(sshGatewayProvider).phoneKey(),
);

/// Add a machine. The SSH form works with no account; the "Same account"
/// tab is part of account mode and not built in this build.
class AddMachineScreen extends ConsumerStatefulWidget {
  const AddMachineScreen({super.key});

  @override
  ConsumerState<AddMachineScreen> createState() => _AddMachineScreenState();
}

class _AddMachineScreenState extends ConsumerState<AddMachineScreen> {
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _name = TextEditingController();
  final _hostFocus = FocusNode();
  final _userFocus = FocusNode();
  final _portFocus = FocusNode();

  bool _tailscale = false;
  String? _hostError;
  String? _userError;
  String? _portError;
  bool _connecting = false;
  SshSession? _session;
  ({String title, String hint})? _failure;

  @override
  void dispose() {
    for (final c in [_host, _user, _port, _name]) {
      c.dispose();
    }
    for (final f in [_hostFocus, _userFocus, _portFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _hostError = validateHost(_host.text);
      _userError = validateUser(_user.text);
      _portError = validatePort(_port.text);
    });
    // Focus moves to the first invalid field.
    if (_hostError != null) {
      _hostFocus.requestFocus();
    } else if (_userError != null) {
      _userFocus.requestFocus();
    } else if (_portError != null) {
      _portFocus.requestFocus();
    }
    return _hostError == null && _userError == null && _portError == null;
  }

  Future<void> _connect() async {
    if (_connecting || !_validate()) return;
    final host = normalizeHost(_host.text);
    final port = int.parse(_port.text.trim());
    final user = _user.text.trim();
    final machine = SshMachine(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      name: _name.text.trim().isEmpty ? host : _name.text.trim(),
      host: host,
      user: user,
      port: port,
      tailscale: _tailscale,
    );
    if (ref.read(sshMachinesProvider).any(machine.sameTarget)) {
      setState(
        () => _failure = (
          title: 'Already saved',
          hint: '$user@$host:$port is already on this phone.',
        ),
      );
      return;
    }
    final session = ref.read(sshGatewayProvider).open(machine);
    setState(() {
      _connecting = true;
      _failure = null;
      _session = session;
    });
    final sub = session.state.listen((s) async {
      if (s is HostKeyNew) {
        final trust = await _askTrust(s.fingerprint);
        if (trust) {
          session.acceptHostKey();
        } else {
          session.rejectHostKey();
        }
      } else if (s is HostKeyChanged) {
        session.rejectHostKey();
      }
    });
    ConnState end;
    try {
      end = await session.start();
    } catch (e) {
      end = Failed('$e');
    }
    // The attempt is over: stop listening and release the connection.
    unawaited(sub.cancel());
    unawaited(session.close());
    // Cancel clears _session; a cancelled attempt saves nothing.
    if (_session != session || !mounted) return;
    setState(() {
      _connecting = false;
      _session = null;
    });
    if (end is Ready) {
      final added = await ref.read(sshMachinesProvider.notifier).add(machine);
      if (!mounted) return;
      if (added) {
        context.go('/machines');
      } else {
        setState(
          () => _failure = (
            title: 'Already saved',
            hint: '$user@$host:$port is already on this phone.',
          ),
        );
      }
    } else if (end is Failed) {
      setState(
        () => _failure = explainFailure(
          end.reason,
          host: host,
          port: port,
          tailscale: _tailscale,
        ),
      );
    }
  }

  void _cancel() {
    final s = _session;
    setState(() {
      _session = null;
      _connecting = false;
    });
    s?.rejectHostKey();
    unawaited(s?.close());
  }

  Future<bool> _askTrust(String fingerprint) async {
    if (!mounted) return false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: context.hx.colors.popover,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => FirstHostKeySheet(
        address: '${_user.text.trim()}@${normalizeHost(_host.text)}:'
            '${_port.text.trim()}',
        fingerprint: fingerprint,
        onTrust: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    return ok ?? false;
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$what copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final key = ref.watch(phoneKeyProvider);
    return Scaffold(
      backgroundColor: c.screen,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go(
                              ref.read(sshMachinesProvider).isEmpty
                                  ? '/sign-in'
                                  : '/machines',
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    header: true,
                    child: Text('Add machine', style: HxType.title),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_failure != null) ...[
                          HxBanner(
                            title: _failure!.title,
                            message: _failure!.hint,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _Field(
                          label: 'Host, IP or Tailscale name',
                          hint: 'devbox.tail1234.ts.net',
                          controller: _host,
                          focus: _hostFocus,
                          error: _hostError,
                          keyboard: TextInputType.url,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _Field(
                                label: 'User',
                                hint: 'dev',
                                controller: _user,
                                focus: _userFocus,
                                error: _userError,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Field(
                                label: 'Port',
                                hint: '22',
                                controller: _port,
                                focus: _portFocus,
                                error: _portError,
                                keyboard: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          label: 'Name (optional)',
                          hint: 'devbox',
                          controller: _name,
                        ),
                        const SizedBox(height: 12),
                        _TailscaleSwitch(
                          value: _tailscale,
                          onChanged: _connecting
                              ? null
                              : (v) => setState(() => _tailscale = v),
                        ),
                        const SizedBox(height: 12),
                        if (_tailscale)
                          Text(
                            'Your tailnet signs this phone in; no key is '
                            'offered.',
                            style: HxType.caption.copyWith(color: c.muted),
                          )
                        else
                          _KeyCard(
                            key: const ValueKey('key-card'),
                            info: key,
                            onCopy: (t, w) => _copy(t, w),
                          ),
                        const SizedBox(height: 20),
                        if (_connecting)
                          _ConnectingRow(onCancel: _cancel)
                        else
                          HxButton(
                            label: 'Connect',
                            kind: HxButtonKind.primary,
                            onPressed: _connect,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.focus,
    this.error,
    this.keyboard,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode? focus;
  final String? error;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: w),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: HxType.bodySm.copyWith(color: c.muted)),
        ),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            focusNode: focus,
            keyboardType: keyboard,
            autocorrect: false,
            enableSuggestions: false,
            style: HxType.body.copyWith(fontFamily: 'JetBrainsMono'),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: HxType.body.copyWith(color: c.muted),
              errorText: error,
              errorMaxLines: 3,
              isDense: false,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              enabledBorder: border(c.outline),
              focusedBorder: border(c.accent, 2),
              errorBorder: border(c.blocked),
              focusedErrorBorder: border(c.blocked, 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _TailscaleSwitch extends StatelessWidget {
  const _TailscaleSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Semantics(
      toggled: value,
      label: 'Use Tailscale SSH, no key, ${value ? 'on' : 'off'}',
      excludeSemantics: true,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: HxCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: Text('Use Tailscale SSH (no key)', style: HxType.bodyLg),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: c.accentForeground,
                activeTrackColor: c.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({super.key, required this.info, required this.onCopy});

  final AsyncValue<PhoneKeyInfo> info;
  final void Function(String text, String what) onCopy;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return HxCard(
      child: info.when(
        loading: () => Text(
          'Preparing this phone\'s key…',
          style: HxType.body.copyWith(color: c.muted),
        ),
        error: (e, _) => Text(
          'Could not create this phone\'s key: $e',
          style: HxType.body,
        ),
        data: (k) {
          final command = "echo '${k.publicLine}' >> ~/.ssh/authorized_keys";
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'THIS PHONE\'S KEY',
                style: HxType.labelXs.copyWith(color: c.muted),
              ),
              const SizedBox(height: 8),
              if (k.addAgain) ...[
                const HxBanner(
                  kind: HxBannerKind.info,
                  title: 'New key',
                  message:
                      'This phone made a new key. Add it again on every '
                      'machine.',
                ),
                const SizedBox(height: 8),
              ],
              Semantics(
                label:
                    'This phone\'s public key, ed25519, '
                    '${spokenFingerprint(k.fingerprint)}',
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.well,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(k.publicLine, style: HxType.monoKey),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                k.fingerprint,
                style: HxType.mono.copyWith(color: c.muted, fontSize: 11.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: HxButton(
                      label: 'Copy',
                      icon: Icons.copy_outlined,
                      semanticsLabel: 'Copy public key',
                      minHeight: 48,
                      onPressed: () => onCopy(k.publicLine, 'Public key'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: HxButton(
                      label: 'Share',
                      icon: Icons.ios_share,
                      semanticsLabel: 'Share public key',
                      minHeight: 48,
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(text: k.publicLine),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Run this on the machine once:',
                style: HxType.caption.copyWith(color: c.muted),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.well,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(command, style: HxType.monoKey),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      tooltip: 'Copy command with key',
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: () => onCopy(command, 'Command'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                r'On Windows, for an administrator user, add the key to '
                r'C:\ProgramData\ssh\administrators_authorized_keys instead.',
                style: HxType.caption.copyWith(color: c.muted),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectingRow extends StatelessWidget {
  const _ConnectingRow({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        color: c.selected,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.accent),
      ),
      child: Row(
        children: [
          Semantics(
            liveRegion: true,
            label: 'Connecting',
            excludeSemantics: true,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: c.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text('Connecting…', style: HxType.bodyLg),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 52,
            child: TextButton(
              onPressed: onCancel,
              child: Text('Cancel', style: HxType.bodyLg.copyWith(color: c.accent)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The first time a host key is seen: its fingerprint, how to check it, and
/// "Trust and connect". Nothing is saved until the user trusts it.
class FirstHostKeySheet extends StatelessWidget {
  const FirstHostKeySheet({
    super.key,
    required this.address,
    required this.fingerprint,
    required this.onTrust,
    required this.onCancel,
  });

  final String address;
  final String fingerprint;
  final VoidCallback onTrust;
  final VoidCallback onCancel;

  static const checkCommand =
      'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub';

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text('Trust this machine?', style: HxType.titleSm),
            ),
            Text(address, style: HxType.mono.copyWith(color: c.muted)),
            const SizedBox(height: 12),
            Text(
              'This phone has not seen this machine before. Compare the '
              'fingerprint with the one on the machine.',
              style: HxType.body,
            ),
            const SizedBox(height: 12),
            FingerprintBox(fingerprint: fingerprint),
            const SizedBox(height: 12),
            Text(
              'Check it on the machine:',
              style: HxType.caption.copyWith(color: c.muted),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.well,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(checkCommand, style: HxType.monoKey),
            ),
            const SizedBox(height: 20),
            HxButton(
              label: 'Trust and connect',
              kind: HxButtonKind.primary,
              onPressed: onTrust,
            ),
            const SizedBox(height: 12),
            HxButton(label: 'Cancel', onPressed: onCancel),
          ],
        ),
      ),
    );
  }
}
