import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import '../widgets/hx_icon_compat.dart';
import '../auth/app_lock.dart';
import '../auth/auth_service.dart';
import '../config.dart';
import '../conn/machine_connection.dart';
import '../conn/ssh/ssh_keys.dart';
import '../state/connections.dart';
import '../state/ssh.dart';
import '../theme/theme_controller.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import '../widgets/app_shell.dart';
import '../widgets/hx.dart';
import '../widgets/hx_bits.dart';
import '../widgets/hx_icons.dart';

/// Settings (design: Settings): theme, security, notifications, this phone's
/// SSH key, known hosts. Account-only blocks sit behind [kAccountMode].
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.onNavigate, this.onOpenTheme});

  final void Function(NavDest dest)? onNavigate;

  /// Opens the theme picker (default: the router's `/settings/theme`).
  final VoidCallback? onOpenTheme;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  KeyResult? _key;
  var _keyLoaded = false;
  Map<String, String> _hosts = const {};
  String? _category;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final key = await ref.read(sshKeysProvider).existing();
    final hosts = await ref.read(knownHostsProvider).entries();
    if (!mounted) return;
    setState(() {
      _key = key == null ? null : KeyResult(key, addAgain: false);
      _keyLoaded = true;
      _hosts = hosts;
    });
  }

  Future<void> _createKey() async {
    final KeyResult r;
    try {
      r = await ref.read(sshKeysProvider).ensure();
    } on StateError catch (e) {
      // A storage read error: say so, and never make a new key over it.
      if (mounted) showHxSnack(context, e.message);
      return;
    }
    if (mounted) setState(() => _key = r);
  }

  Future<void> _regenerate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _Confirm(
        icon: Icons.vpn_key_outlined,
        title: "Regenerate this phone's key?",
        text: 'Machines that trust the current key will refuse this phone. '
            'After this you add the new key to each one. Tailscale SSH machines are not affected.',
        action: 'Regenerate',
      ),
    );
    if (ok != true) return;
    final r = await ref.read(sshKeysProvider).regenerate();
    if (mounted) setState(() => _key = r);
  }

  Future<void> _copy(String line) async {
    await ref.read(copyTextProvider)(line);
    if (!mounted) return;
    showHxSnack(context, 'Public key copied');
  }

  Future<void> _forget(String key) async {
    await ref.read(knownHostsProvider).forgetEntry(key);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final wide = MediaQuery.sizeOf(context).width >= kRailBreakpoint;
    final theme = ref.watch(themeControllerProvider);
    final hasBiometrics = ref.watch(biometricsAvailableProvider).value ?? false;
    final lock = ref.watch(appLockProvider);
    final machines = ref.watch(connectionsProvider);
    final prefs = ref.watch(sharedPrefsProvider);
    final key = _key?.key;

    final children = <Widget>[
      if (kAccountMode)
        _Group(
          label: 'ACCOUNT',
          children: [
            _Row(
              icon: Icons.person_outline,
              title: 'Account',
              subtitle: 'HyperOx account',
            ),
            HxButton(
              label: 'Sign out',
              kind: HxButtonKind.danger,
              minHeight: 48,
              onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            ),
          ],
        ),
      _Group(
        label: 'APPEARANCE',
        children: [
          _Row(
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: _themeLine(theme),
            trailing: Icon(Icons.chevron_right, color: c.muted),
            onTap: widget.onOpenTheme ?? () => context.push('/settings/theme'),
          ),
        ],
      ),
      // Hidden when the device has no fingerprint or face enrolled.
      if (hasBiometrics)
        _Group(
          label: 'SECURITY',
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: const Text('Unlock with fingerprint'),
              subtitle: const Text('after 5 min away'),
              value: lock.enabled,
              onChanged: (on) => ref.read(appLockProvider.notifier).setEnabled(on),
            ),
          ],
        ),
      if (machines.isNotEmpty)
        _Group(
          label: 'NOTIFICATIONS',
          children: [
            for (final m in machines)
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(m.machine.name),
                subtitle: Text(m.machine.mode == ConnMode.ssh
                    ? 'ssh · while the app is open'
                    : 'account · push'),
                value: prefs.getBool('notify.${m.machine.id}') ?? true,
                onChanged: (on) async {
                  await prefs.setBool('notify.${m.machine.id}', on);
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
      _Group(
        label: 'SSH KEY OF THIS PHONE',
        children: [
          if (!_keyLoaded)
            const SizedBox(height: 48)
          else if (key == null) ...[
            Text(
              'No key yet. It is made when you add your first SSH machine, or now.',
              style: HxType.body.copyWith(color: c.muted),
            ),
            const SizedBox(height: 12),
            HxButton(label: 'Create key', onPressed: _createKey, minHeight: 48),
          ] else ...[
            _Row(
              icon: Icons.vpn_key_outlined,
              title: 'ed25519',
              subtitle: key.fingerprint,
              mono: true,
            ),
            HxBannerSlot(
              child: !_key!.addAgain
                  ? null
                  : const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: HxBanner(
                        title: 'New key',
                        message: 'Add it to every machine again.',
                        kind: HxBannerKind.info,
                      ),
                    ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.well, borderRadius: BorderRadius.circular(12)),
              child: Semantics(
                label: 'Public key',
                child: SelectableText(key.publicLine, style: HxType.monoKey),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: HxButton(
                    label: 'Copy',
                    icon: Icons.copy_outlined,
                    minHeight: 48,
                    onPressed: () => _copy(key.publicLine),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: HxButton(
                    label: 'Share',
                    icon: Icons.ios_share,
                    minHeight: 48,
                    onPressed: () => ref.read(shareTextProvider)(key.publicLine),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            HxButton(
              label: 'Regenerate key…',
              icon: Icons.refresh,
              kind: HxButtonKind.danger,
              minHeight: 48,
              onPressed: _regenerate,
            ),
          ],
        ],
      ),
      _Group(
        label: 'KNOWN HOSTS',
        children: [
          if (_hosts.isEmpty)
            Text('No host has been trusted yet.', style: HxType.body.copyWith(color: c.muted)),
          for (final e in _hosts.entries)
            _Row(
              icon: Icons.dns_outlined,
              title: e.key,
              subtitle: e.value,
              mono: true,
              trailing: HxIconButton(
                icon: Icons.close,
                label: 'Forget host key for ${e.key}',
                onPressed: () => _forget(e.key),
              ),
            ),
        ],
      ),
      _Group(
        label: 'ABOUT',
        children: [
          _Row(
            icon: Icons.info_outline,
            title: 'HyperOx mobile',
            subtitle: kAccountMode ? 'Account and SSH modes' : 'SSH mode',
          ),
        ],
      ),
    ];

    if (wide) {
      // Two panes: the categories (320 wide, on chrome) and the selected
      // category's group (settings board 03).
      final groups = children.whereType<_Group>().toList();
      final current = groups.firstWhere(
        (g) => g.label == _category,
        orElse: () => groups.first,
      );
      return ScreenBody(
        body: Column(
          children: [
            const ScreenHeader(title: 'Settings'),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 320,
                    color: c.chrome,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (final g in groups)
                          _CategoryRow(
                            group: g,
                            selected: g.label == current.label,
                            onTap: () => setState(() => _category = g.label),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [current],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ScreenBody(
      body: Column(
        children: [
          const ScreenHeader(title: 'Settings'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A category of the two-pane layout: icon and title, 52 dp.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final _Group group;
  final bool selected;
  final VoidCallback onTap;

  static const _meta = {
    'ACCOUNT': ('Account', 'user'),
    'APPEARANCE': ('Appearance', 'palette'),
    'SECURITY': ('Security', 'shield-check'),
    'NOTIFICATIONS': ('Notifications', 'bell'),
    'SSH KEY OF THIS PHONE': ('SSH key', 'key'),
    'KNOWN HOSTS': ('Known hosts', 'server'),
    'ABOUT': ('About', 'info'),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final (title, icon) = _meta[group.label] ?? (group.label, 'settings');
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = selected ? (dark ? c.accent : c.foreground) : c.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? '$title, selected' : title,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? c.selected : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              HxIcon(icon, size: 20, color: tint),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: HxType.weight(HxType.bodyLg, selected ? 600 : 500)
                      .copyWith(color: selected ? c.foreground : c.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _themeLine(ThemeSettings s) {
  final mode = switch (s.mode) {
    HxThemeMode.system => 'System',
    HxThemeMode.light => 'Light',
    HxThemeMode.dark => 'Dark',
  };
  return '$mode · ${themeById(s.light).label} / ${themeById(s.dark).label}';
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: SectionLabel(label),
          ),
          HxCard(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.mono = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(icon, size: 22, color: c.muted)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: mono ? HxType.mono : HxType.bodyLg),
                  if (subtitle != null)
                    Text(subtitle!, style: (mono ? HxType.monoKey : HxType.caption).copyWith(color: c.muted)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
    if (onTap == null) return body;
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: body),
    );
  }
}

class _Confirm extends StatelessWidget {
  const _Confirm({required this.icon, required this.title, required this.text, required this.action});
  final IconData icon;
  final String title;
  final String text;
  final String action;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    return AlertDialog(
      backgroundColor: c.card,
      icon: Icon(icon, color: c.blocked),
      title: Text(title),
      content: Text(text, style: HxType.body),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 48),
            backgroundColor: c.blocked,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    );
  }
}
