import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Icon;

import 'hx_icon_compat.dart';
import '../state/inbox.dart';
import '../theme/themes.dart';
import '../theme/type.dart';
import 'hx.dart';

class _Dest {
  const _Dest(this.label, this.path, this.icon);
  final String label;
  final String path;
  final IconData icon;
}

const _dests = [
  _Dest('Inbox', '/inbox', Icons.inbox_outlined),
  _Dest('Machines', '/machines', Icons.computer_outlined),
  _Dest('Spaces', '/spaces', Icons.dashboard_outlined),
  _Dest('To-do', '/todo', Icons.checklist),
  _Dest('Settings', '/settings', Icons.settings_outlined),
];

/// The five-item navigation: a bottom bar (80 dp) below 600 dp, a rail
/// (80 dp wide) from 600 dp up (design/tokens.md section 6).
class NavShell extends ConsumerWidget {
  const NavShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  int get _index {
    final i = _dests.indexWhere((d) => location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hx.colors;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final inbox = ref.watch(inboxProvider).value;
    Widget item(int i, {required bool rail}) => ValueListenableBuilder<InboxState>(
      valueListenable: inbox,
      builder: (context, state, _) => _NavItem(
        dest: _dests[i],
        selected: i == _index,
        rail: rail,
        // The Inbox shows how many agents need the person.
        badge: i == 0 ? state.needsYou : 0,
        onTap: () => context.go(_dests[i].path),
      ),
    );
    if (wide) {
      return Scaffold(
        backgroundColor: c.screen,
        body: Row(
          children: [
            Container(
              width: 80,
              color: c.chrome,
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // The brand mark tops the rail.
                    const HxMark(size: 28),
                    const SizedBox(height: 16),
                    for (var i = 0; i < _dests.length; i++) item(i, rail: true),
                  ],
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: c.screen,
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.chrome,
          border: Border(top: BorderSide(color: c.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 80,
            child: Row(
              children: [
                for (var i = 0; i < _dests.length; i++)
                  Expanded(child: item(i, rail: false)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.dest,
    required this.selected,
    required this.rail,
    required this.onTap,
    this.badge = 0,
  });

  final _Dest dest;
  final bool selected;
  final bool rail;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.hx.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Selected: accent on dark, foreground on light (the boards).
    final color = selected ? (dark ? c.accent : c.foreground) : c.muted;
    final base = selected ? '${dest.label}, selected' : dest.label;
    // Labels grow with the text size, but stop at 1.3x (tokens section 14).
    final scaler = MediaQuery.textScalerOf(context);
    final labelScale = scaler.scale(12) / 12 > 1.3
        ? const TextScaler.linear(1.3)
        : scaler;
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$base, $badge needs you' : base,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minHeight: rail ? 76 : 64,
            minWidth: 48,
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? c.selected : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Icon(dest.icon, size: 24, color: color),
                    if (badge > 0)
                      Positioned(
                        top: -4,
                        right: 6,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: dark ? c.accent : c.working,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '$badge',
                            textScaler: TextScaler.noScaling,
                            style: HxType.mono.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: dark ? c.accentForeground : Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dest.label,
                maxLines: 1,
                textScaler: labelScale,
                style: HxType.caption.copyWith(
                  color: color,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  fontVariations: [
                    FontVariation('wght', selected ? 600 : 500),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
